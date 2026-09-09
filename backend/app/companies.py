from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["companies"])


class CompanyOut(BaseModel):
    id: str
    company_name: str
    legal_name: str | None
    status: str
    record_state: str
    country: str | None
    website: str | None
    notes: str | None
    owner_user_id: str | None
    next_action_due_date: str | None


class MemberOut(BaseModel):
    user_id: str
    email: str
    first_name: str | None
    last_name: str | None
    role: str
    status: str


class CompanyIn(BaseModel):
    company_name: str = Field(min_length=1)
    legal_name: str | None = None
    status: str = "Prospect"
    country: str | None = None
    website: str | None = None
    notes: str | None = None
    owner_user_id: str | None = None
    record_state: str | None = None


class CompanyCampaignOut(BaseModel):
    id: str
    name: str
    status: str
    membership_status: str


def _row(row: tuple) -> CompanyOut:
    return CompanyOut(
        id=str(row[0]),
        company_name=row[1],
        legal_name=row[2],
        status=row[3],
        record_state=row[4],
        country=row[5],
        website=row[6],
        notes=row[7],
        owner_user_id=str(row[8]) if row[8] else None,
        next_action_due_date=row[9].isoformat() if row[9] else None,
    )


@router.get("/members", response_model=list[MemberOut])
def list_members(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> list[MemberOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute("select * from public.app_list_members(%s, %s)", (user_id, entity_id))
            rows = cur.fetchall()
        except Exception as exc:
            raise_pg(exc)
        return [
            MemberOut(
                user_id=str(row[0]),
                email=row[1],
                first_name=row[2],
                last_name=row[3],
                role=row[4],
                status=row[5],
            )
            for row in rows
        ]


@router.get("/companies", response_model=list[CompanyOut])
def list_companies(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
    q: str = "",
    record_state: str = Query(default="Active"),
    country: str = "",
) -> list[CompanyOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        params: list[object] = [entity_id]
        where = "entity_id = %s"
        if record_state:
            where += " and record_state = %s"
            params.append(record_state)
        if q.strip():
            where += " and company_name ilike %s"
            params.append(f"%{q.strip()}%")
        if country.strip():
            where += " and country = %s"
            params.append(country.strip().upper())
        cur.execute(
            f"""
            select id, company_name, legal_name, status, record_state, country,
                   website, null, owner_user_id, next_action_due_date
            from public.company
            where {where}
            order by lower(company_name)
            limit 500
            """,
            params,
        )
        return [_row(row) for row in cur.fetchall()]


@router.post("/companies", response_model=CompanyOut)
def create_company(
    body: CompanyIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> CompanyOut:
    owner = body.owner_user_id or user_id
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            insert into public.company (
              entity_id, company_name, legal_name, country, website, notes,
              status, record_state, owner_user_id, created_by_user_id, updated_by_user_id
            )
            values (%s, %s, %s, %s, %s, %s, %s, 'Active', %s, %s, %s)
            returning id, company_name, legal_name, status, record_state, country,
                      website, notes, owner_user_id, next_action_due_date
            """,
            (
                entity_id,
                body.company_name.strip(),
                body.legal_name,
                body.country,
                body.website,
                body.notes,
                body.status,
                owner,
                user_id,
                user_id,
            ),
        )
        row = cur.fetchone()
        connection.commit()
    return _row(row)


@router.get("/companies/{company_id}", response_model=CompanyOut)
def get_company(
    company_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> CompanyOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select id, company_name, legal_name, status, record_state, country,
                   website, notes, owner_user_id, next_action_due_date
            from public.company
            where id = %s and entity_id = %s
            """,
            (company_id, entity_id),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Company not found")
    return _row(row)


@router.get("/companies/{company_id}/campaigns", response_model=list[CompanyCampaignOut])
def list_company_campaigns(
    company_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> list[CompanyCampaignOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select 1 from public.company
            where id = %s and entity_id = %s
            """,
            (company_id, entity_id),
        )
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail="Company not found")
        cur.execute(
            """
            select cam.id, cam.name, cam.status, cc.status
            from public.campaign_company cc
            join public.campaign cam
              on cam.id = cc.campaign_id and cam.entity_id = cc.entity_id
            where cc.entity_id = %s
              and cc.company_id = %s
              and cc.record_state = 'Active'
            order by lower(cam.name)
            """,
            (entity_id, company_id),
        )
        return [
            CompanyCampaignOut(
                id=str(row[0]),
                name=row[1],
                status=row[2],
                membership_status=row[3],
            )
            for row in cur.fetchall()
        ]


@router.patch("/companies/{company_id}", response_model=CompanyOut)
def patch_company(
    company_id: str,
    body: CompanyIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> CompanyOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select owner_user_id from public.company
            where id = %s and entity_id = %s
            """,
            (company_id, entity_id),
        )
        current = cur.fetchone()
        if not current:
            raise HTTPException(status_code=404, detail="Company not found")
        previous_owner = str(current[0]) if current[0] else None
        new_owner = body.owner_user_id
        record_state = body.record_state or "Active"
        cur.execute(
            """
            update public.company
            set company_name = %s,
                legal_name = %s,
                country = %s,
                website = %s,
                notes = %s,
                status = %s,
                record_state = %s,
                owner_user_id = %s,
                updated_by_user_id = %s,
                updated_at = now()
            where id = %s and entity_id = %s
            returning id, company_name, legal_name, status, record_state, country,
                      website, notes, owner_user_id, next_action_due_date
            """,
            (
                body.company_name.strip(),
                body.legal_name,
                body.country,
                body.website,
                body.notes,
                body.status,
                record_state,
                new_owner,
                user_id,
                company_id,
                entity_id,
            ),
        )
        row = cur.fetchone()
        if (
            previous_owner
            and new_owner
            and previous_owner != new_owner
        ):
            cur.execute(
                """
                insert into public.company_handover (
                  entity_id, company_id, from_user_id, to_user_id, reason,
                  status, created_by_user_id
                )
                values (%s, %s, %s, %s, 'Manual Reassignment', 'Pending Review', %s)
                """,
                (entity_id, company_id, previous_owner, new_owner, user_id),
            )
        connection.commit()
    return _row(row)
