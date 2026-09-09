from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.mail import send_updates_mail
from app.settings import settings
from app.spike1 import _assume_runtime
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["invitations"])


class InviteIn(BaseModel):
    email: str
    role: str = Field(pattern="^(Entity Admin|Manager|User)$")


class InviteOut(BaseModel):
    id: str
    email: str
    role: str
    status: str
    expires_at: str


class InvitePreview(BaseModel):
    email: str
    role: str
    status: str
    entity_name: str
    expires_at: str


@router.get("/invitations", response_model=list[InviteOut])
def list_invitations(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> list[InviteOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select id, email, role, status, expires_at
            from public.user_invitation
            where entity_id = %s
            order by created_at desc
            """,
            (entity_id,),
        )
        rows = cur.fetchall()
    return [
        InviteOut(
            id=str(row[0]),
            email=row[1],
            role=row[2],
            status=row[3],
            expires_at=row[4].isoformat(),
        )
        for row in rows
    ]


@router.get("/invitations/{invitation_id}", response_model=InvitePreview)
def invitation_preview(invitation_id: str) -> InvitePreview:
    with runtime_connection() as connection, connection.cursor() as cur:
        _assume_runtime(cur)
        cur.execute(
            """
            select email, role, status, entity_name, expires_at
            from public.app_invitation_preview(%s)
            """,
            (invitation_id,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Invitation is not valid or has expired")
    return InvitePreview(
        email=row[0],
        role=row[1],
        status=row[2],
        entity_name=row[3],
        expires_at=row[4].isoformat(),
    )


@router.post("/invitations", response_model=InviteOut)
def create_invitation(
    body: InviteIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> InviteOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_invite_colleague(%s, %s, %s, %s)",
                (user_id, entity_id, str(body.email), body.role),
            )
        except Exception as exc:
            raise_pg(exc)
        invite_id = str(cur.fetchone()[0])
        cur.execute(
            """
            select id, email, role, status, expires_at
            from public.user_invitation where id = %s
            """,
            (invite_id,),
        )
        row = cur.fetchone()
        connection.commit()
    accept_url = f"{settings.public_app_url.rstrip('/')}/invite/{invite_id}"
    try:
        send_updates_mail(
            str(body.email),
            "You are invited to Stufe7",
            f"You were invited to join a Stufe7 workspace as {body.role}.\n\n{accept_url}\n",
        )
    except Exception:
        pass
    return InviteOut(
        id=str(row[0]),
        email=row[1],
        role=row[2],
        status=row[3],
        expires_at=row[4].isoformat(),
    )


@router.post("/invitations/{invitation_id}/accept")
def accept_invitation(
    invitation_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    email = str(claims.get("email") or "")
    if not email:
        raise HTTPException(status_code=400, detail="Session is missing an email")
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims)
        cur.execute(
            "select public.app_ensure_user(%s, %s, %s, %s)",
            (user_id, email, None, None),
        )
        try:
            cur.execute("select public.app_accept_invitation(%s, %s)", (user_id, invitation_id))
        except Exception as exc:
            raise_pg(exc)
        entity_id = str(cur.fetchone()[0])
        cur.execute("select public.app_seed_invite_timezone(%s, %s)", (user_id, entity_id))
        cur.execute(
            "select public.app_record_consent(%s, 'Terms', %s, 'Invitation')",
            (user_id, settings.terms_version),
        )
        cur.execute(
            "select public.app_record_consent(%s, 'Privacy', %s, 'Invitation')",
            (user_id, settings.privacy_version),
        )
        connection.commit()
    return {"status": "accepted", "entity_id": entity_id}
