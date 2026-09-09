from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["contacts"])


class ContactOut(BaseModel):
    id: str
    company_id: str
    company_name: str | None = None
    first_name: str
    last_name: str
    job_title: str | None
    email: str | None
    telephone: str | None
    mobile: str | None
    linkedin_url: str | None
    notes: str | None
    record_state: str
    next_action_due_date: str | None


class ContactIn(BaseModel):
    company_id: str
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    job_title: str | None = None
    email: str | None = None
    telephone: str | None = None
    mobile: str | None = None
    linkedin_url: str | None = None
    notes: str | None = None
    record_state: str | None = None
    cancel_open_actions: bool = False


def _row(row: tuple) -> ContactOut:
    return ContactOut(
        id=str(row[0]),
        company_id=str(row[1]),
        company_name=row[2],
        first_name=row[3],
        last_name=row[4],
        job_title=row[5],
        email=row[6],
        telephone=row[7],
        mobile=row[8],
        linkedin_url=row[9],
        notes=row[10],
        record_state=row[11],
        next_action_due_date=row[12].isoformat() if row[12] else None,
    )


_SELECT = """
    select c.id, c.company_id, co.company_name, c.first_name, c.last_name, c.job_title,
           c.email, c.telephone, c.mobile, c.linkedin_url, c.notes, c.record_state,
           c.next_action_due_date
    from public.contact c
    join public.company co on co.id = c.company_id and co.entity_id = c.entity_id
"""


@router.get("/contacts", response_model=list[ContactOut])
def list_contacts(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
    company_id: str | None = None,
    q: str = "",
    record_state: str = Query(default="Active"),
) -> list[ContactOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        params: list[object] = [entity_id]
        where = "c.entity_id = %s"
        if record_state:
            where += " and c.record_state = %s"
            params.append(record_state)
        if company_id:
            where += " and c.company_id = %s"
            params.append(company_id)
        if q.strip():
            where += (
                " and (c.first_name ilike %s or c.last_name ilike %s or c.email ilike %s"
                " or co.company_name ilike %s)"
            )
            like = f"%{q.strip()}%"
            params.extend([like, like, like, like])
        cur.execute(
            f"{_SELECT} where {where} order by lower(c.last_name), lower(c.first_name) limit 500",
            params,
        )
        return [_row(row) for row in cur.fetchall()]


@router.post("/contacts", response_model=ContactOut)
def create_contact(
    body: ContactIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> ContactOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                """
                insert into public.contact (
                  entity_id, company_id, first_name, last_name, job_title, email,
                  telephone, mobile, linkedin_url, notes, record_state,
                  created_by_user_id, updated_by_user_id
                )
                values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'Active', %s, %s)
                returning id
                """,
                (
                    entity_id,
                    body.company_id,
                    body.first_name.strip(),
                    body.last_name.strip(),
                    body.job_title,
                    body.email,
                    body.telephone,
                    body.mobile,
                    body.linkedin_url,
                    body.notes,
                    user_id,
                    user_id,
                ),
            )
        except Exception as exc:
            raise_pg(exc)
        contact_id = cur.fetchone()[0]
        cur.execute(f"{_SELECT} where c.id = %s and c.entity_id = %s", (contact_id, entity_id))
        row = cur.fetchone()
        connection.commit()
    return _row(row)


@router.get("/contacts/{contact_id}", response_model=ContactOut)
def get_contact(
    contact_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> ContactOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(f"{_SELECT} where c.id = %s and c.entity_id = %s", (contact_id, entity_id))
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Contact not found")
    return _row(row)


@router.patch("/contacts/{contact_id}", response_model=ContactOut)
def patch_contact(
    contact_id: str,
    body: ContactIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> ContactOut:
    record_state = body.record_state or "Active"
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        if record_state == "Archived" and body.cancel_open_actions:
            cur.execute(
                """
                update public.action
                set status = 'Cancelled', cancelled_at = now(),
                    cancellation_reason = 'Parent archived',
                    updated_by_user_id = %s, updated_at = now()
                where entity_id = %s and contact_id = %s and status = 'Open'
                """,
                (user_id, entity_id, contact_id),
            )
        try:
            cur.execute(
                """
                update public.contact
                set company_id = %s, first_name = %s, last_name = %s, job_title = %s,
                    email = %s, telephone = %s, mobile = %s, linkedin_url = %s,
                    notes = %s, record_state = %s, updated_by_user_id = %s, updated_at = now()
                where id = %s and entity_id = %s
                """,
                (
                    body.company_id,
                    body.first_name.strip(),
                    body.last_name.strip(),
                    body.job_title,
                    body.email,
                    body.telephone,
                    body.mobile,
                    body.linkedin_url,
                    body.notes,
                    record_state,
                    user_id,
                    contact_id,
                    entity_id,
                ),
            )
        except Exception as exc:
            raise_pg(exc)
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Contact not found")
        cur.execute(f"{_SELECT} where c.id = %s and c.entity_id = %s", (contact_id, entity_id))
        row = cur.fetchone()
        connection.commit()
    return _row(row)
