from __future__ import annotations

import json
import uuid

import psycopg

from app.db import runtime_connection


def prove_auth_uid() -> dict[str, object]:
    sub = str(uuid.uuid4())
    claims = json.dumps({"sub": sub, "role": "authenticated"})
    result: dict[str, object] = {"sub": sub}

    with runtime_connection() as connection, connection.cursor() as cur:
        cur.execute("select current_user")
        current_user = cur.fetchone()[0]
        result["current_user"] = current_user
        cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
        cur.execute("select auth.uid()")
        uid = cur.fetchone()[0]
        result["auth_uid"] = str(uid) if uid is not None else None
        result["matches_sub"] = str(uid) == sub if uid is not None else False

    with runtime_connection() as connection, connection.cursor() as cur:
        try:
            cur.execute("set role app_authz")
            result["set_role_app_authz_denied"] = False
        except psycopg.Error:
            result["set_role_app_authz_denied"] = True

    return result
