from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.mail import send_updates_mail
from app.signup import _runtime_claims
from app.tenant import raise_pg

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
    stale: bool = False


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
            stale=_stale(row[7]),
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


class DomainPending(BaseModel):
    id: str
    entity_id: str
    entity_name: str
    domain: str
    created_at: str


class DomainRejectIn(BaseModel):
    requester_feedback: str = Field(min_length=1)


@router.get("/domain-requests", response_model=list[DomainPending])
def list_domain_requests(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> list[DomainPending]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        try:
            cur.execute("select * from public.app_list_pending_domain_requests(%s)", (user_id,))
        except Exception as exc:
            from app.tenant import pg_detail

            raise HTTPException(status_code=403, detail=pg_detail(exc)) from exc
        rows = cur.fetchall()
    return [
        DomainPending(
            id=str(row[0]),
            entity_id=str(row[1]),
            entity_name=row[2],
            domain=row[3] or "",
            created_at=row[4].isoformat(),
        )
        for row in rows
    ]


@router.post("/domain-requests/{request_id}/approve")
def approve_domain(
    request_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        try:
            cur.execute("select public.app_approve_domain_addition(%s, %s)", (request_id, user_id))
        except Exception as exc:
            raise_pg(exc)
        connection.commit()
    return {"status": "approved"}


@router.post("/domain-requests/{request_id}/reject")
def reject_domain(
    request_id: str,
    body: DomainRejectIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        try:
            cur.execute(
                "select public.app_reject_domain_addition(%s, %s, %s)",
                (request_id, user_id, body.requester_feedback),
            )
        except Exception as exc:
            raise_pg(exc)
        connection.commit()
    return {"status": "rejected"}


class ChangePending(BaseModel):
    id: str
    request_type: str
    entity_id: str
    entity_name: str
    summary: str
    created_at: str
    stale: bool


class ChangeRejectIn(BaseModel):
    requester_feedback: str = ""


class WeekStat(BaseModel):
    week_start: str
    new_users: int
    new_entities: int
    active_entities: int
    active_users: int
    actions_created: int
    from_rollup: bool


class DenyHealth(BaseModel):
    refreshed_at: str | None
    status: str | None
    source_version: str | None
    entry_count: int | None
    error_summary: str | None


def _stale(created_at: datetime) -> bool:
    stamp = created_at if created_at.tzinfo else created_at.replace(tzinfo=UTC)
    return datetime.now(UTC) - stamp > timedelta(hours=24)


def _require_platform(cur, user_id: str) -> None:
    cur.execute("select public.app_is_platform_admin(%s)", (user_id,))
    if not cur.fetchone()[0]:
        raise HTTPException(status_code=403, detail="Not a platform admin")


def _requester_email(cur, request_id: str) -> str | None:
    cur.execute("select public.app_change_request_requester_email(%s)", (request_id,))
    row = cur.fetchone()
    return row[0] if row else None


@router.get("/change-requests", response_model=list[ChangePending])
def list_change_requests(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> list[ChangePending]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        _require_platform(cur, user_id)
        try:
            cur.execute("select * from public.app_list_pending_change_requests(%s)", (user_id,))
            rows = cur.fetchall()
        except Exception as extra:
            raise_pg(extra)
    return [
        ChangePending(
            id=str(row[0]),
            request_type=row[1],
            entity_id=str(row[2]),
            entity_name=row[3],
            summary=row[4] or "",
            created_at=row[5].isoformat(),
            stale=_stale(row[5]),
        )
        for row in rows
    ]


@router.post("/change-requests/{request_id}/approve")
def approve_change(
    request_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    email: str | None = None
    req_type = ""
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        _require_platform(cur, user_id)
        try:
            cur.execute(
                "select public.app_approve_change_request(%s, %s)",
                (request_id, user_id),
            )
            req_type = cur.fetchone()[0]
            email = _requester_email(cur, request_id)
            connection.commit()
        except Exception as extra:
            connection.rollback()
            raise_pg(extra)
    if email:
        send_updates_mail(email, f"{req_type} approved", f"Your {req_type} request was approved.")
    return {"status": "approved"}


@router.post("/change-requests/{request_id}/reject")
def reject_change(
    request_id: str,
    body: ChangeRejectIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> dict[str, str]:
    email: str | None = None
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        _require_platform(cur, user_id)
        try:
            cur.execute(
                "select public.app_reject_change_request(%s, %s, %s)",
                (request_id, user_id, body.requester_feedback),
            )
            email = _requester_email(cur, request_id)
            connection.commit()
        except Exception as extra:
            connection.rollback()
            raise_pg(extra)
    if email:
        send_updates_mail(
            email,
            "Request rejected",
            body.requester_feedback or "Your request was rejected.",
        )
    return {"status": "rejected"}


@router.get("/stats", response_model=list[WeekStat])
def weekly_stats(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> list[WeekStat]:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        _require_platform(cur, user_id)
        try:
            cur.execute("select * from public.app_platform_weekly_stats(%s)", (user_id,))
            rows = cur.fetchall()
        except Exception as extra:
            raise_pg(extra)
    return [
        WeekStat(
            week_start=row[0].isoformat(),
            new_users=row[1],
            new_entities=row[2],
            active_entities=row[3],
            active_users=row[4],
            actions_created=row[5],
            from_rollup=bool(row[6]),
        )
        for row in rows
    ]


@router.get("/deny-health", response_model=DenyHealth)
def deny_health(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
) -> DenyHealth:
    with runtime_connection() as connection, connection.cursor() as cur:
        _runtime_claims(cur, claims)
        _require_platform(cur, user_id)
        try:
            cur.execute("select * from public.app_platform_deny_health(%s)", (user_id,))
            row = cur.fetchone()
        except Exception as extra:
            raise_pg(extra)
    if not row:
        return DenyHealth(
            refreshed_at=None,
            status=None,
            source_version=None,
            entry_count=None,
            error_summary=None,
        )
    return DenyHealth(
        refreshed_at=row[0].isoformat() if row[0] else None,
        status=row[1],
        source_version=row[2],
        entry_count=row[3],
        error_summary=row[4],
    )
