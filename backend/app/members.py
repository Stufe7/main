from __future__ import annotations

import json
import logging
from typing import Annotated, Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.mail import send_updates_mail
from app.tenant import bind_request, raise_pg, require_entity_id

log = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["users"])


class UserOut(BaseModel):
    user_id: str
    email: str
    first_name: str | None
    last_name: str | None
    role: str
    status: str
    last_accessed_at: str | None
    deactivated_at: str | None


class RoleIn(BaseModel):
    role: str = Field(pattern="^(Entity Admin|Manager|User)$")


class ResponsibilityOut(BaseModel):
    kind: str
    id: str
    label: str


class DeactivateIn(BaseModel):
    default_to_user_id: str | None = None
    companies: dict[str, str] = Field(default_factory=dict)
    actions: dict[str, str] = Field(default_factory=dict)
    campaigns: dict[str, str] = Field(default_factory=dict)
    campaign_companies: dict[str, str] = Field(default_factory=dict)


def _user_row(row: tuple) -> UserOut:
    return UserOut(
        user_id=str(row[0]),
        email=row[1],
        first_name=row[2],
        last_name=row[3],
        role=row[4],
        status=row[5],
        last_accessed_at=row[6].isoformat() if row[6] else None,
        deactivated_at=row[7].isoformat() if row[7] else None,
    )


@router.get("/users", response_model=list[UserOut])
def list_users(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> list[UserOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute("select * from public.app_admin_list_members(%s, %s)", (user_id, entity_id))
            rows = cur.fetchall()
        except Exception as exc:
            raise_pg(exc)
    return [_user_row(row) for row in rows]


@router.get("/users/{target_id}/responsibilities", response_model=list[ResponsibilityOut])
def list_responsibilities(
    target_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> list[ResponsibilityOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select * from public.app_member_responsibilities(%s, %s, %s)",
                (user_id, entity_id, target_id),
            )
            rows = cur.fetchall()
        except Exception as exc:
            raise_pg(exc)
    return [ResponsibilityOut(kind=row[0], id=str(row[1]), label=row[2]) for row in rows]


@router.patch("/users/{target_id}/role", response_model=dict[str, str])
def set_role(
    target_id: str,
    body: RoleIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_set_member_role(%s, %s, %s, %s)",
                (user_id, entity_id, target_id, body.role),
            )
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return {"status": "ok"}


@router.post("/users/{target_id}/deactivate")
def deactivate_user(
    target_id: str,
    body: DeactivateIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, Any]:
    payload = {
        "default_to_user_id": body.default_to_user_id,
        "companies": body.companies,
        "actions": body.actions,
        "campaigns": body.campaigns,
        "campaign_companies": body.campaign_companies,
    }
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_deactivate_member(%s, %s, %s, %s::jsonb)",
                (user_id, entity_id, target_id, json.dumps(payload)),
            )
            notices = cur.fetchone()[0] or []
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    if not isinstance(notices, list):
        notices = []
    seen: set[str] = set()
    for item in notices:
        if not isinstance(item, dict):
            continue
        email = item.get("to_email")
        company = item.get("company_name") or "a company"
        if not email or email in seen:
            continue
        seen.add(email)
        try:
            send_updates_mail(
                email,
                "Customer handover in Stufe7",
                f"Companies were reassigned to you, including {company}. "
                "Open Home to review each handover.\n",
            )
        except Exception:
            log.exception("handover mail failed")
    return {"status": "inactive", "handovers": notices}


@router.post("/users/{target_id}/reactivate")
def reactivate_user(
    target_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_reactivate_member(%s, %s, %s)",
                (user_id, entity_id, target_id),
            )
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return {"status": "active"}


@router.post("/users/{target_id}/remove")
def remove_user(
    target_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_remove_member(%s, %s, %s)",
                (user_id, entity_id, target_id),
            )
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return {"status": "removed"}
