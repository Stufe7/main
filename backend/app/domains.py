from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["domains"])


class DomainRow(BaseModel):
    domain: str
    status: str
    is_primary: bool
    added_via: str


class DomainRequestRow(BaseModel):
    id: str
    domain: str
    status: str
    requester_feedback: str | None
    created_at: str


class DomainRequestIn(BaseModel):
    domain: str = Field(min_length=3)


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
            select id, payload ->> 'domain', status, requester_feedback, created_at
            from public.entity_change_request
            where entity_id = %s and request_type = 'Domain Addition'
            order by created_at desc
            """,
            (entity_id,),
        )
        requests = [
            DomainRequestRow(
                id=str(row[0]),
                domain=row[1] or "",
                status=row[2],
                requester_feedback=row[3],
                created_at=row[4].isoformat(),
            )
            for row in cur.fetchall()
        ]
    return {"domains": [row.model_dump() for row in domains], "requests": [row.model_dump() for row in requests]}


@router.post("/domains/requests", response_model=DomainRequestRow)
def request_domain(
    body: DomainRequestIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> DomainRequestRow:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_request_domain_addition(%s, %s, %s)",
                (user_id, entity_id, body.domain),
            )
        except Exception as exc:
            raise_pg(exc)
        request_id = str(cur.fetchone()[0])
        cur.execute(
            """
            select id, payload ->> 'domain', status, requester_feedback, created_at
            from public.entity_change_request where id = %s
            """,
            (request_id,),
        )
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=500, detail="Request was not stored")
        connection.commit()
    return DomainRequestRow(
        id=str(row[0]),
        domain=row[1] or "",
        status=row[2],
        requester_feedback=row[3],
        created_at=row[4].isoformat(),
    )
