from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1/settings", tags=["settings"])


class EntitySettingsOut(BaseModel):
    entity_name: str
    country: str
    timezone: str
    digest_send_local_time: str
    digest_frequency: str


class DigestIn(BaseModel):
    frequency: str = Field(pattern="^(Off|Daily|Weekly|Monthly)$")
    timezone: str = Field(min_length=1)


class GeneralIn(BaseModel):
    digest_send_local_time: str = Field(pattern="^([01]\\d|2[0-3]):00:00$")


@router.get("/entity", response_model=EntitySettingsOut)
def get_entity_settings(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> EntitySettingsOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute("select * from public.app_entity_settings(%s, %s)", (user_id, entity_id))
            row = cur.fetchone()
        except Exception as exc:
            raise_pg(exc)
    if not row:
        raise HTTPException(status_code=404, detail="Entity settings not found")
    return EntitySettingsOut(
        entity_name=row[0],
        country=row[1],
        timezone=row[2],
        digest_send_local_time=str(row[3])[:8],
        digest_frequency=row[4],
    )


@router.patch("/digest")
def set_digest(
    body: DigestIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_set_digest_frequency(%s, %s, %s)",
                (user_id, entity_id, body.frequency),
            )
            cur.execute(
                "select public.app_set_user_timezone(%s, %s)",
                (user_id, body.timezone),
            )
            connection.commit()
        except Exception as exc:
            raise_pg(exc)
    return {"status": "updated", "frequency": body.frequency, "timezone": body.timezone}


@router.patch("/entity")
def update_general(
    body: GeneralIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                "select public.app_update_entity_general(%s, %s, %s)",
                (user_id, entity_id, body.digest_send_local_time),
            )
            connection.commit()
        except Exception as exc:
            raise_pg(exc)
    return {"status": "updated"}
