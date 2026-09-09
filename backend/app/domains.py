from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.mail import send_admin_alert
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["domains"])


class DomainRow(BaseModel):
    domain: str
    status: str
    is_primary: bool
    added_via: str


class DomainRequestRow(BaseModel):
    id: str
    request_type: str
    domain: str | None = None
    summary: str | None = None
    status: str
    requester_feedback: str | None
    created_at: str


class DomainRequestIn(BaseModel):
    domain: str = Field(min_length=3)


class RenameIn(BaseModel):
    entity_name: str = Field(min_length=1)
    legal_name: str | None = None


def _request_row(row: tuple) -> DomainRequestRow:
    payload_domain = row[2]
    return DomainRequestRow(
        id=str(row[0]),
        request_type=row[1],
        domain=payload_domain,
        summary=row[3],
        status=row[4],
        requester_feedback=row[5],
        created_at=row[6].isoformat(),
    )


@router.get("/domains")
def list_domains(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, list]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select domain, status, is_primary, added_via
            from public.entity_domain
            where entity_id = %s
            order by is_primary desc, domain
            """,
            (entity_id,),
        )
        domains = [
            DomainRow(domain=row[0], status=row[1], is_primary=row[2], added_via=row[3])
            for row in cur.fetchall()
        ]
        cur.execute(
            """
            select id, request_type,
                   payload ->> 'domain',
                   coalesce(
                     payload ->> 'domain',
                     concat_ws(' → ', payload ->> 'from_domain', payload ->> 'to_domain'),
                     payload ->> 'entity_name'
                   ),
                   status, requester_feedback, created_at
            from public.entity_change_request
            where entity_id = %s
            order by created_at desc
            """,
            (entity_id,),
        )
        requests = [_request_row(row) for row in cur.fetchall()]
    return {
        "domains": [row.model_dump() for row in domains],
        "requests": [row.model_dump() for row in requests],
    }


def _store_request(cur, sql: str, params: tuple) -> DomainRequestRow:
    try:
        cur.execute(sql, params)
    except Exception as exc:
        raise_pg(exc)
    request_id = str(cur.fetchone()[0])
    cur.execute(
        """
        select id, request_type, payload ->> 'domain',
               coalesce(
                 payload ->> 'domain',
                 concat_ws(' → ', payload ->> 'from_domain', payload ->> 'to_domain'),
                 payload ->> 'entity_name'
               ),
               status, requester_feedback, created_at
        from public.entity_change_request where id = %s
        """,
        (request_id,),
    )
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=500, detail="Request was not stored")
    return _request_row(row)


@router.post("/domains/requests", response_model=DomainRequestRow)
def request_domain(
    body: DomainRequestIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> DomainRequestRow:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        row = _store_request(
            cur,
            "select public.app_request_domain_addition(%s, %s, %s)",
            (user_id, entity_id, body.domain),
        )
        connection.commit()
    send_admin_alert("Domain addition request", f"{body.domain} for entity {entity_id}")
    return row


@router.post("/domains/removals", response_model=DomainRequestRow)
def request_removal(
    body: DomainRequestIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> DomainRequestRow:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        row = _store_request(
            cur,
            "select public.app_request_domain_removal(%s, %s, %s)",
            (user_id, entity_id, body.domain),
        )
        connection.commit()
    send_admin_alert("Domain removal request", f"{body.domain} for entity {entity_id}")
    return row


@router.post("/domains/primary", response_model=DomainRequestRow)
def request_primary(
    body: DomainRequestIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> DomainRequestRow:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        row = _store_request(
            cur,
            "select public.app_request_domain_primary(%s, %s, %s)",
            (user_id, entity_id, body.domain),
        )
        connection.commit()
    send_admin_alert("Primary domain transfer request", f"{body.domain} for entity {entity_id}")
    return row


@router.post("/entity/rename", response_model=DomainRequestRow)
def request_rename(
    body: RenameIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> DomainRequestRow:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        row = _store_request(
            cur,
            "select public.app_request_entity_rename(%s, %s, %s, %s)",
            (user_id, entity_id, body.entity_name, body.legal_name),
        )
        connection.commit()
    send_admin_alert("Entity rename request", f"{body.entity_name} for entity {entity_id}")
    return row
