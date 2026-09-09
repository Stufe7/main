from __future__ import annotations

import json
import uuid

import psycopg

from app.db import runtime_connection

# Spec 17 claim-read. Do not call auth.uid() in policies.
REQUEST_UID_SQL = (
    "(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid"
)


def _assume_runtime(cur: psycopg.Cursor) -> str:
    cur.execute("select current_user")
    login_user = cur.fetchone()[0]
    if login_user != "app_runtime":
        cur.execute("set local role app_runtime")
        cur.execute("select current_user")
        current = cur.fetchone()[0]
        if current != "app_runtime":
            raise RuntimeError(f"SET LOCAL ROLE app_runtime left current_user={current}")
        return login_user
    return login_user


def prove_auth_uid() -> dict[str, object]:
    sub = str(uuid.uuid4())
    claims = json.dumps({"sub": sub, "role": "authenticated"})
    result: dict[str, object] = {"sub": sub}

    with runtime_connection() as connection, connection.cursor() as cur:
        login_user = _assume_runtime(cur)
        cur.execute("select current_user")
        result["login_user"] = login_user
        result["current_user"] = cur.fetchone()[0]
        result["used_set_role_app_runtime"] = login_user != "app_runtime"
        cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
        cur.execute(f"select {REQUEST_UID_SQL}")
        request_uid = cur.fetchone()[0]
        result["request_uid"] = str(request_uid) if request_uid is not None else None
        result["request_uid_matches_sub"] = result["request_uid"] == sub

        try:
            cur.execute("select auth.uid()")
            uid = cur.fetchone()[0]
            result["auth_uid"] = str(uid) if uid is not None else None
            result["auth_uid_error"] = None
        except psycopg.Error as exc:
            result["auth_uid"] = None
            result["auth_uid_error"] = exc.diag.message_primary if exc.diag else str(exc)
            connection.rollback()
            _assume_runtime(cur)
            cur.execute("select set_config('request.jwt.claims', %s, true)", (claims,))

        result["matches_sub"] = result.get("request_uid") == sub

        try:
            cur.execute("set local role app_authz")
            result["set_role_app_authz_denied"] = False
        except psycopg.Error:
            result["set_role_app_authz_denied"] = True
            connection.rollback()

    return result
