from __future__ import annotations

import logging
from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.settings import settings
from app.tenant import bind_request, raise_pg

log = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/privacy", tags=["privacy"])


class PrivacyRequestOut(BaseModel):
    id: str
    subject_type: str
    subject_id: str
    entity_id: str | None
    status: str
    legal_basis: str
    requested_at: str
    executed_at: str | None


class ExecuteIn(BaseModel):
    subject_type: str = Field(pattern="^(CONTACT|USER|REGISTRATION_REQUEST)$")
    subject_id: str
    entity_id: str | None = None
    legal_basis: str = Field(min_length=1)


def _require_operator(cur, user_id: str) -> None:
    cur.execute("select public.app_is_privacy_operator(%s)", (user_id,))
    if not cur.fetchone()[0]:
        raise HTTPException(status_code=403, detail="Not a privacy operator")


def _ban_auth_user(user_id: str) -> None:
    key = settings.supabase_service_role_key
    base = settings.supabase_url.rstrip("/")
    if not key or not base:
        log.info("privacy Auth ban skipped (no SUPABASE_SERVICE_ROLE_KEY)")
        return
    response = httpx.delete(
        f"{base}/auth/v1/admin/users/{user_id}",
        headers={
            "Authorization": f"Bearer {key}",
            "apikey": key,
        },
        timeout=15.0,
    )
    if response.status_code not in (200, 204, 404):
        log.error("privacy Auth delete %s: %s", response.status_code, response.text)


@router.get("/requests", response_model=list[PrivacyRequestOut])
def list_requests(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> list[PrivacyRequestOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims)
        try:
            _require_operator(cur, user_id)
            cur.execute("select * from public.app_privacy_list(%s)", (user_id,))
            rows = cur.fetchall()
        except HTTPException:
            raise
        except Exception as exc:
            raise_pg(exc)
    return [
        PrivacyRequestOut(
            id=str(row[0]),
            subject_type=row[1],
            subject_id=str(row[2]),
            entity_id=str(row[3]) if row[3] else None,
            status=row[4],
            legal_basis=row[5],
            requested_at=row[6].isoformat(),
            executed_at=row[7].isoformat() if row[7] else None,
        )
        for row in rows
    ]


@router.post("/execute")
def execute(
    body: ExecuteIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims)
        try:
            _require_operator(cur, user_id)
            cur.execute(
                "select public.app_privacy_execute(%s, %s, %s, %s, %s)",
                (
                    user_id,
                    body.subject_type,
                    body.subject_id,
                    body.entity_id,
                    body.legal_basis.strip(),
                ),
            )
            request_id = str(cur.fetchone()[0])
            connection.commit()
        except HTTPException:
            raise
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    if body.subject_type == "USER":
        _ban_auth_user(body.subject_id)
    return {"status": "executed", "request_id": request_id}
