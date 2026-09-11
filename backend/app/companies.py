from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.company_sheet import _norm_name, classify_row, read_rows, workbook_bytes

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


def _require_entity_admin(cur, user_id: str, entity_id: str) -> None:
    cur.execute(
        """
        select role from public.user_entity
        where user_id = %s and entity_id = %s and status = 'active'
        """,
        (user_id, entity_id),
    )
    role = cur.fetchone()
    if not role or role[0] != "Entity Admin":
        raise HTTPException(status_code=403, detail="not an Entity Admin")


@router.get("/companies/export")
def export_companies(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> StreamingResponse:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select c.id, c.company_name, c.legal_name, c.country, c.city, c.address,
                   c.website, c.telephone, c.nature_of_business, c.status, c.notes,
                   u.email
            from public.company c
            left join public.app_user u on u.id = c.owner_user_id
            where c.entity_id = %s and c.record_state = 'Active'
            order by lower(c.company_name)
            """,
            (entity_id,),
        )
        rows = [
            {
                "Company ID": str(row[0]),
                "Company Name": row[1],
                "Legal Name": row[2],
                "Country": row[3],
                "City": row[4],
                "Address": row[5],
                "Website": row[6],
                "Telephone": row[7],
                "Nature of Business": row[8],
                "Company Status": row[9],
                "Notes": row[10],
                "Owner Email": row[11],
            }
            for row in cur.fetchall()
        ]
    payload = workbook_bytes(rows)
    return StreamingResponse(
        iter([payload]),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": 'attachment; filename="companies.xlsx"'},
    )


@router.post("/companies/import")
def import_companies(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
    file: UploadFile = File(...),
) -> dict[str, object]:
    raw = file.file.read()
    try:
        parsed = read_rows(raw)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    added = 0
    updated = 0
    skipped = 0
    errors: list[str] = []
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        _require_entity_admin(cur, user_id, entity_id)
        cur.execute(
            """
            select id, company_name, country, legal_name, city, address, website,
                   telephone, nature_of_business, status, notes, owner_user_id
            from public.company
            where entity_id = %s and record_state = 'Active'
            """,
            (entity_id,),
        )
        existing = cur.fetchall()
        by_id = {str(row[0]): {"id": row[0], "name": row[1], "country": row[2]} for row in existing}
        by_name: dict[tuple[str, str], dict] = {}
        for row in existing:
            by_name[(_norm_name(row[1]), (row[2] or "").upper())] = {
                "id": row[0],
                "name": row[1],
                "country": row[2],
            }
        cur.execute("select * from public.app_list_members(%s, %s)", (user_id, entity_id))
        members = {str(row[1]).casefold(): str(row[0]) for row in cur.fetchall() if row[1]}
        planned = [classify_row(item, by_id, by_name, members) for item in parsed]
        try:
            for index, row in enumerate(planned, start=2):
                if row["action"] == "skip":
                    skipped += 1
                    if row["error"]:
                        errors.append(f"Row {index}: {row['error']}")
                    continue
                if row["action"] == "create":
                    cur.execute(
                        """
                        insert into public.company (
                          entity_id, company_name, legal_name, country, city, address,
                          website, telephone, nature_of_business, notes, status,
                          record_state, owner_user_id, created_by_user_id, updated_by_user_id
                        )
                        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'Active', %s, %s, %s)
                        """,
                        (
                            entity_id,
                            row["company_name"],
                            row["legal_name"],
                            row["country"],
                            row["city"],
                            row["address"],
                            row["website"],
                            row["telephone"],
                            row["nature_of_business"],
                            row["notes"],
                            row["status"] or "Prospect",
                            row["owner_user_id"] or user_id,
                            user_id,
                            user_id,
                        ),
                    )
                    added += 1
                    continue
                cur.execute(
                    """
                    update public.company
                    set company_name = coalesce(%s, company_name),
                        legal_name = coalesce(%s, legal_name),
                        country = coalesce(%s, country),
                        city = coalesce(%s, city),
                        address = coalesce(%s, address),
                        website = coalesce(%s, website),
                        telephone = coalesce(%s, telephone),
                        nature_of_business = coalesce(%s, nature_of_business),
                        notes = coalesce(%s, notes),
                        status = coalesce(%s, status),
                        owner_user_id = coalesce(%s, owner_user_id),
                        updated_by_user_id = %s,
                        updated_at = now()
                    where id = %s and entity_id = %s
                    """,
                    (
                        row["company_name"],
                        row["legal_name"],
                        row["country"],
                        row["city"],
                        row["address"],
                        row["website"],
                        row["telephone"],
                        row["nature_of_business"],
                        row["notes"],
                        row["status"],
                        row["owner_user_id"],
                        user_id,
                        row["company_id"],
                        entity_id,
                    ),
                )
                updated += 1
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return {
        "added": added,
        "updated": updated,
        "skipped": skipped,
        "errors": errors,
    }


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
