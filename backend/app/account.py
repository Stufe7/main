from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.signup import _runtime_claims
from app.tenant import pg_detail, raise_pg

router = APIRouter(prefix="/v1/account", tags=["account"])


class EmailChangeIn(BaseModel):
    email: str = Field(min_length=3)


class EmailChangeOut(BaseModel):
    status: str
    email: str
    change_id: str | None = None


def sync_confirmed_email_on(cur, connection, claims: Claims, user_id: str) -> str | None:
    """May commit or roll back. Caller must re-bind request claims afterwards."""
    auth_email = str(claims.get("email") or "").strip()
    if not auth_email:
        return None
    cur.execute("select email from public.app_user where id = %s", (user_id,))
    row = cur.fetchone()
    stored = row[0] if row else None
    if not stored or stored.lower() == auth_email.lower():
        return None
    try:
        cur.execute("select public.app_email_change_commit(%s, %s)", (user_id, auth_email))
        connection.commit()
    except Exception as extra:
        connection.rollback()
        return pg_detail(extra)
    return None


def sync_confirmed_email(claims: Claims, user_id: str) -> str | None:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        return sync_confirmed_email_on(cur, connection, claims, user_id)


@router.post("/email-change/start", response_model=EmailChangeOut)
def start_email_change(
    body: EmailChangeIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> EmailChangeOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        try:
            cur.execute("select public.app_email_change_start(%s, %s)", (user_id, str(body.email)))
            change_id = str(cur.fetchone()[0])
            connection.commit()
        except Exception as extra:
            connection.rollback()
            raise_pg(extra)
    return EmailChangeOut(status="confirm_email", email=str(body.email).lower(), change_id=change_id)


@router.post("/email-change/commit", response_model=EmailChangeOut)
def commit_email_change(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> EmailChangeOut:
    auth_email = str(claims.get("email") or "").strip()
    if not auth_email:
        raise HTTPException(status_code=400, detail="Session is missing an email")
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        try:
            cur.execute("select public.app_email_change_commit(%s, %s)", (user_id, auth_email))
            committed = str(cur.fetchone()[0])
            connection.commit()
        except Exception as extra:
            connection.rollback()
            raise_pg(extra)
    return EmailChangeOut(status="confirmed", email=committed)
