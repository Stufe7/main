from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["campaigns"])

STATUSES = ("Planned", "Active", "Completed", "Cancelled")
CC_STATUSES = (
    "Not Started",
    "Contacted",
    "Interested",
    "Qualified",
    "Demo / Meeting",
    "Proposal",
    "Won",
    "Lost",
    "Not Relevant",
)


class CampaignIn(BaseModel):
    name: str = Field(min_length=1)
    description: str | None = None
    owner_user_id: str | None = None
    start_date: date
    end_date: date
    status: str = "Planned"
    record_state: str | None = None
    cancel_open_actions: bool = False


class CampaignOut(BaseModel):
    id: str
    name: str
    description: str | None
    owner_user_id: str
    start_date: str
    end_date: str
    status: str
    record_state: str
    company_count: int = 0


class CampaignCompanyOut(BaseModel):
    id: str
    company_id: str
    company_name: str
    country: str | None
    nature_of_business: str | None
    status: str
    owner_user_id: str | None
    effective_owner_user_id: str | None
    next_action_due_date: str | None
    notes: str | None


class AddCompaniesIn(BaseModel):
    company_ids: list[str] = Field(min_length=1)


class CampaignCompanyPatch(BaseModel):
    status: str | None = None
    owner_user_id: str | None = None
    notes: str | None = None
    record_state: str | None = None


def _campaign_row(row: tuple) -> CampaignOut:
    return CampaignOut(
        id=str(row[0]),
        name=row[1],
        description=row[2],
        owner_user_id=str(row[3]),
        start_date=row[4].isoformat(),
        end_date=row[5].isoformat(),
        status=row[6],
        record_state=row[7],
        company_count=int(row[8] or 0),
    )


_CAM_SELECT = """
    select cam.id, cam.name, cam.description, cam.owner_user_id, cam.start_date,
           cam.end_date, cam.status, cam.record_state,
           (
             select count(*) from public.campaign_company cc
             where cc.campaign_id = cam.id and cc.entity_id = cam.entity_id
               and cc.record_state = 'Active'
           )
    from public.campaign cam
"""

_CAM_LIST_SELECT = """
    select cam.id, cam.name, null, cam.owner_user_id, cam.start_date,
           cam.end_date, cam.status, cam.record_state,
           (
             select count(*) from public.campaign_company cc
             where cc.campaign_id = cam.id and cc.entity_id = cam.entity_id
               and cc.record_state = 'Active'
           )
    from public.campaign cam
"""


@router.get("/campaigns", response_model=list[CampaignOut])
def list_campaigns(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
    record_state: str = Query(default="Active"),
) -> list[CampaignOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        params: list[object] = [entity_id]
        where = "cam.entity_id = %s"
        if record_state:
            where += " and cam.record_state = %s"
            params.append(record_state)
        cur.execute(
            f"{_CAM_LIST_SELECT} where {where} order by cam.start_date desc, cam.name limit 200",
            params,
        )
        return [_campaign_row(row) for row in cur.fetchall()]


@router.post("/campaigns", response_model=CampaignOut)
def create_campaign(
    body: CampaignIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> CampaignOut:
    if body.end_date < body.start_date:
        raise HTTPException(status_code=400, detail="end_date must be on or after start_date")
    if body.status not in STATUSES:
        raise HTTPException(status_code=400, detail="invalid status")
    owner = body.owner_user_id or user_id
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                """
                insert into public.campaign (
                  entity_id, name, description, owner_user_id, start_date, end_date,
                  status, record_state, created_by_user_id, updated_by_user_id
                )
                values (%s, %s, %s, %s, %s, %s, %s, 'Active', %s, %s)
                returning id
                """,
                (
                    entity_id,
                    body.name.strip(),
                    body.description,
                    owner,
                    body.start_date,
                    body.end_date,
                    body.status,
                    user_id,
                    user_id,
                ),
            )
            campaign_id = str(cur.fetchone()[0])
            cur.execute(
                f"{_CAM_SELECT} where cam.id = %s and cam.entity_id = %s",
                (campaign_id, entity_id),
            )
            row = cur.fetchone()
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return _campaign_row(row)


@router.get("/campaigns/{campaign_id}", response_model=CampaignOut)
def get_campaign(
    campaign_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> CampaignOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            f"{_CAM_SELECT} where cam.id = %s and cam.entity_id = %s",
            (campaign_id, entity_id),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Campaign not found")
    return _campaign_row(row)


@router.patch("/campaigns/{campaign_id}", response_model=CampaignOut)
def patch_campaign(
    campaign_id: str,
    body: CampaignIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> CampaignOut:
    if body.end_date < body.start_date:
        raise HTTPException(status_code=400, detail="end_date must be on or after start_date")
    record_state = body.record_state or "Active"
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_campaign_assert_end_date(%s, %s, %s)",
                (entity_id, campaign_id, body.end_date),
            )
            if body.cancel_open_actions:
                cur.execute(
                    """
                    update public.action
                    set status = 'Cancelled', cancelled_at = now(),
                        cancellation_reason = 'Campaign ended',
                        updated_by_user_id = %s, updated_at = now()
                    where entity_id = %s and campaign_id = %s and status = 'Open'
                    """,
                    (user_id, entity_id, campaign_id),
                )
            cur.execute(
                """
                update public.campaign
                set name = %s, description = %s, owner_user_id = %s,
                    start_date = %s, end_date = %s, status = %s, record_state = %s,
                    updated_by_user_id = %s, updated_at = now()
                where id = %s and entity_id = %s
                """,
                (
                    body.name.strip(),
                    body.description,
                    body.owner_user_id or user_id,
                    body.start_date,
                    body.end_date,
                    body.status,
                    record_state,
                    user_id,
                    campaign_id,
                    entity_id,
                ),
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Campaign not found")
            cur.execute(
                f"{_CAM_SELECT} where cam.id = %s and cam.entity_id = %s",
                (campaign_id, entity_id),
            )
            row = cur.fetchone()
            connection.commit()
        except HTTPException:
            connection.rollback()
            raise
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return _campaign_row(row)


@router.get("/campaigns/{campaign_id}/companies", response_model=list[CampaignCompanyOut])
def list_campaign_companies(
    campaign_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> list[CampaignCompanyOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select cc.id, cc.company_id, c.company_name, c.country, c.nature_of_business,
                   cc.status, cc.owner_user_id,
                   coalesce(cc.owner_user_id, c.owner_user_id),
                   c.next_action_due_date, null
            from public.campaign_company cc
            join public.company c on c.id = cc.company_id and c.entity_id = cc.entity_id
            where cc.entity_id = %s and cc.campaign_id = %s and cc.record_state = 'Active'
            order by lower(c.company_name)
            """,
            (entity_id, campaign_id),
        )
        return [
            CampaignCompanyOut(
                id=str(row[0]),
                company_id=str(row[1]),
                company_name=row[2],
                country=row[3],
                nature_of_business=row[4],
                status=row[5],
                owner_user_id=str(row[6]) if row[6] else None,
                effective_owner_user_id=str(row[7]) if row[7] else None,
                next_action_due_date=row[8].isoformat() if row[8] else None,
                notes=row[9],
            )
            for row in cur.fetchall()
        ]


@router.post("/campaigns/{campaign_id}/companies")
def add_campaign_companies(
    campaign_id: str,
    body: AddCompaniesIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, int]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_campaign_add_companies(%s, %s, %s, %s::uuid[])",
                (user_id, entity_id, campaign_id, body.company_ids),
            )
            added = int(cur.fetchone()[0])
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return {"added": added}


@router.patch("/campaigns/{campaign_id}/companies/{company_id}")
def patch_campaign_company(
    campaign_id: str,
    company_id: str,
    body: CampaignCompanyPatch,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    if body.status and body.status not in CC_STATUSES:
        raise HTTPException(status_code=400, detail="invalid campaign-company status")
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select status, owner_user_id, notes, record_state
            from public.campaign_company
            where entity_id = %s and campaign_id = %s and company_id = %s
            """,
            (entity_id, campaign_id, company_id),
        )
        current = cur.fetchone()
        if not current:
            raise HTTPException(status_code=404, detail="Campaign company not found")
        status = body.status or current[0]
        owner = current[1] if body.owner_user_id is None else (body.owner_user_id or None)
        notes = current[2] if body.notes is None else body.notes
        record_state = body.record_state or current[3]
        removed_sql = "now()" if record_state == "Archived" else "null"
        cur.execute(
            f"""
            update public.campaign_company
            set status = %s, owner_user_id = %s, notes = %s, record_state = %s,
                removed_at = {removed_sql}, updated_by_user_id = %s, updated_at = now()
            where entity_id = %s and campaign_id = %s and company_id = %s
            """,
            (status, owner, notes, record_state, user_id, entity_id, campaign_id, company_id),
        )
        connection.commit()
    return {"status": "ok"}
