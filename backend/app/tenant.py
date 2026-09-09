from __future__ import annotations

from typing import Annotated

from fastapi import Header, HTTPException
import psycopg

from app.authn import Claims, claims_json
from app.runtime import _assume_runtime


def bind_request(cur, claims: Claims, entity_id: str | None = None) -> None:
    _assume_runtime(cur)
    cur.execute("select set_config('request.jwt.claims', %s, true)", (claims_json(claims),))
    if not entity_id:
        return
    cur.execute(
        "select public.app_has_active_membership(%s, %s)",
        (str(claims.get("sub")), entity_id),
    )
    row = cur.fetchone()
    if not row or not row[0]:
        raise HTTPException(status_code=403, detail="No access to this entity")
    cur.execute("select set_config('app.active_entity_id', %s, true)", (entity_id,))
    cur.execute("select public.app_touch_last_access(%s, %s)", (str(claims.get("sub")), entity_id))


def require_entity_id(
    x_entity_id: Annotated[str | None, Header()] = None,
) -> str:
    if not x_entity_id:
        raise HTTPException(status_code=400, detail="X-Entity-Id is required")
    return x_entity_id


def pg_detail(exc: BaseException) -> str:
    diag = getattr(exc, "diag", None)
    message = getattr(diag, "message_primary", None) if diag is not None else None
    return str(message or exc)


def raise_pg(exc: BaseException) -> None:
    raise HTTPException(status_code=400, detail=pg_detail(exc)) from exc


def is_unique_violation(exc: BaseException) -> bool:
    return isinstance(exc, psycopg.errors.UniqueViolation)
