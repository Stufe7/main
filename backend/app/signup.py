from __future__ import annotations

from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, HttpUrl

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.identity import email_domain, registrable_domain, verify_company_identity
from app.mail import send_admin_alert
from app.settings import settings
from app.tenant import bind_request

router = APIRouter(prefix="/v1", tags=["signup"])


class SignupCompleteIn(BaseModel):
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    company: str = Field(min_length=1)
    country: str = Field(min_length=2, max_length=2)
    company_url: HttpUrl
    timezone: str = Field(min_length=1)
    provisioning_key: str | None = None


class SignupCompleteOut(BaseModel):
    status: str
    entity_id: str | None = None
    request_id: str | None = None
    reason_code: str | None = None
    summary: str | None = None


class MembershipOut(BaseModel):
    entity_id: str
    entity_name: str
    role: str
    status: str


class SessionOut(BaseModel):
    user_id: str
    email: str | None
    memberships: list[MembershipOut]
    pending_registration: bool
    platform_admin: bool


def _runtime_claims(cur, claims: Claims) -> None:
    bind_request(cur, claims)


@router.post("/signup/complete", response_model=SignupCompleteOut)
def signup_complete(
    body: SignupCompleteIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> SignupCompleteOut:
    email = str(claims.get("email") or "")
    if not email:
        raise HTTPException(status_code=400, detail="Session is missing an email")
    key = body.provisioning_key or str(uuid4())
    verdict = verify_company_identity(
        work_email=email,
        company_name=body.company,
        company_url=str(body.company_url),
    )
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        cur.execute(
            "select public.app_ensure_user(%s, %s, %s, %s)",
            (user_id, email, body.first_name.strip(), body.last_name.strip()),
        )
        cur.execute(
            "select public.app_record_consent(%s, 'Terms', %s, 'Signup')",
            (user_id, settings.terms_version),
        )
        cur.execute(
            "select public.app_record_consent(%s, 'Privacy', %s, 'Signup')",
            (user_id, settings.privacy_version),
        )
        if verdict.decision == "Verified":
            cur.execute(
                """
                select public.app_provision_self_serve(%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    user_id,
                    key,
                    body.company.strip(),
                    body.country.upper(),
                    str(body.company_url),
                    body.timezone,
                    email_domain(email),
                ),
            )
            entity_id = str(cur.fetchone()[0])
            connection.commit()
            return SignupCompleteOut(
                status="provisioned",
                entity_id=entity_id,
                reason_code=verdict.reason_code,
                summary=verdict.summary,
            )
        cur.execute(
            """
            select public.app_create_registration_request(
              %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
            """,
            (
                user_id,
                body.first_name.strip(),
                body.last_name.strip(),
                email,
                email_domain(email),
                body.company.strip(),
                str(body.company_url),
                registrable_domain(str(body.company_url)),
                body.country.upper(),
                body.timezone,
                verdict.reason_code,
                verdict.summary,
            ),
        )
        request_id = str(cur.fetchone()[0])
        connection.commit()
        send_admin_alert(
            "Registration review required",
            f"{email} / {body.company.strip()} / {verdict.reason_code}\n{verdict.summary or ''}",
        )
        return SignupCompleteOut(
            status="pending_review",
            request_id=request_id,
            reason_code=verdict.reason_code,
            summary=verdict.summary,
        )


@router.get("/session", response_model=SessionOut)
def session(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> SessionOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        cur.execute(
            """
            select ue.entity_id, e.entity_name, ue.role, ue.status
            from public.user_entity ue
            join public.entity e on e.id = ue.entity_id
            where ue.user_id = %s and ue.status = 'active' and e.status = 'Active'
            order by e.entity_name
            """,
            (user_id,),
        )
        memberships = [
            MembershipOut(
                entity_id=str(row[0]),
                entity_name=row[1],
                role=row[2],
                status=row[3],
            )
            for row in cur.fetchall()
        ]
        cur.execute(
            """
            select exists (
              select 1 from public.registration_request
              where user_id = %s and status = 'Pending Review'
            )
            """,
            (user_id,),
        )
        pending = bool(cur.fetchone()[0])
        cur.execute("select public.app_is_platform_admin(%s)", (user_id,))
        platform_admin = bool(cur.fetchone()[0])
    return SessionOut(
        user_id=user_id,
        email=claims.get("email"),
        memberships=memberships,
        pending_registration=pending,
        platform_admin=platform_admin,
    )
