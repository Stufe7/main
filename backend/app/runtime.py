from __future__ import annotations

import json

import psycopg

from app.spike1 import REQUEST_UID_SQL, _assume_runtime


def set_runtime_context(
    cur: psycopg.Cursor,
    *,
    user_id: str,
    active_entity_id: str | None,
) -> None:
    _assume_runtime(cur)
    claims = json.dumps({"sub": user_id, "role": "authenticated"})
    cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
    if active_entity_id is None:
        return
    cur.execute("select public.app_authorize_membership(%s, %s)", (user_id, active_entity_id))
    row = cur.fetchone()
    if row is None or not row[0]:
        raise PermissionError("no active membership for active_entity_id")
    cur.execute("select set_config('app.active_entity_id', %s, true)", (active_entity_id,))
    cur.execute(f"select {REQUEST_UID_SQL}")
    request_uid = cur.fetchone()[0]
    if str(request_uid) != user_id:
        raise RuntimeError("spec 17 claim-read did not match user_id")
