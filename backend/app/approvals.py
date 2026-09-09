from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.signup import _runtime_claims

router = APIRouter(prefix="/v1/platform", tags=["platform"])


class RegistrationRow(BaseModel):
    id: str
    company_name: str
    work_email: str
    country: str
    reason_code: str | None
    summary: str | None
    status: str
    created_at: str


class RejectIn(BaseModel):
    applicant_feedback: str = Field(min_length=1)


@router.get("/registrations", response_model=list[RegistrationRow])
def list_registrations(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> list[RegistrationRow]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        cur.execute("select public.app_is_platform_admin(%s)", (user_id,))
        if not cur.fetchone()[0]:
            raise HTTPException(status_code=403, detail="Not a platform admin")
        cur.execute(
            """
            select id, company_name, work_email, country, verification_reason_code,
                   verification_summary, status, created_at
            from public.registration_request
            where status = 'Pending Review'
            order by created_at
            """
        )
        rows = cur.fetchall()
    return [
        RegistrationRow(
            id=str(row[0]),
            company_name=row[1],
            work_email=row[2],
            country=row[3],
            reason_code=row[4],
            summary=row[5],
            status=row[6],
            created_at=row[7].isoformat(),
        )
        for row in rows
    ]


@router.post("/registrations/{request_id}/approve")
def approve_registration(
    request_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        cur.execute("select public.app_approve_registration(%s, %s)", (request_id, user_id))
        entity_id = cur.fetchone()[0]
        connection.commit()
    return {"status": "approved", "entity_id": str(entity_id)}


@router.post("/registrations/{request_id}/reject")
def reject_registration(
    request_id: str,
    body: RejectIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        cur.execute(
            "select public.app_reject_registration(%s, %s, %s)",
            (request_id, user_id, body.applicant_feedback),
        )
        connection.commit()
    return {"status": "rejected"}
