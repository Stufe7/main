from __future__ import annotations

import uuid

import psycopg

from app.db import runtime_connection
from app.runtime import set_runtime_context


MARKER = "phase1a.kernel"


def _seed(cur: psycopg.Cursor) -> dict[str, str]:
    user_dual = str(uuid.uuid4())
    user_b = str(uuid.uuid4())
    entity_a = str(uuid.uuid4())
    entity_b = str(uuid.uuid4())
    company_a = str(uuid.uuid4())
    company_b = str(uuid.uuid4())
    contact_a = str(uuid.uuid4())

    cur.execute(
        """
        insert into public.app_user (id, email, first_name, last_name, status)
        values
          (%s, %s, 'Dual', 'User', 'active'),
          (%s, %s, 'Only', 'B', 'active')
        """,
        (
            user_dual,
            f"dual@{MARKER}",
            user_b,
            f"onlyb@{MARKER}",
        ),
    )
    cur.execute(
        """
        insert into public.entity (
          id, entity_name, country, reference_timezone, digest_send_local_time
        )
        values
          (%s, %s, 'SG', 'Asia/Singapore', '08:00:00'),
          (%s, %s, 'SG', 'Asia/Singapore', '08:00:00')
        """,
        (entity_a, f"entity-a-{MARKER}", entity_b, f"entity-b-{MARKER}"),
    )
    cur.execute(
        """
        insert into public.entity_domain (
          entity_id, domain, status, is_primary, added_via
        )
        values
          (%s, %s, 'Approved', true, 'Signup'),
          (%s, %s, 'Approved', true, 'Signup')
        """,
        (entity_a, "tenant-a.kernel", entity_b, "tenant-b.kernel"),
    )
    cur.execute(
        """
        insert into public.user_entity (user_id, entity_id, role, status)
        values
          (%s, %s, 'Entity Admin', 'active'),
          (%s, %s, 'Entity Admin', 'active'),
          (%s, %s, 'User', 'active')
        """,
        (user_dual, entity_a, user_dual, entity_b, user_b, entity_b),
    )
    cur.execute(
        """
        insert into public.company (
          id, entity_id, company_name, status, record_state, owner_user_id
        )
        values
          (%s, %s, 'Company A', 'Prospect', 'Active', %s),
          (%s, %s, 'Company B', 'Prospect', 'Active', %s)
        """,
        (company_a, entity_a, user_dual, company_b, entity_b, user_dual),
    )
    cur.execute(
        """
        insert into public.contact (
          id, entity_id, company_id, first_name, last_name, record_state
        )
        values (%s, %s, %s, 'Ada', 'A', 'Active')
        """,
        (contact_a, entity_a, company_a),
    )
    return {
        "user_dual": user_dual,
        "user_b": user_b,
        "entity_a": entity_a,
        "entity_b": entity_b,
        "company_a": company_a,
        "company_b": company_b,
        "contact_a": contact_a,
    }


def _cleanup(cur: psycopg.Cursor) -> None:
    cur.execute(
        """
        select exists (
          select 1
          from pg_trigger t
          join pg_class c on c.oid = t.tgrelid
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'user_entity'
            and t.tgname = 'user_entity_last_admin_guard'
        )
        """
    )
    last_admin_trigger = bool(cur.fetchone()[0])
    if last_admin_trigger:
        cur.execute(
            "alter table public.user_entity disable trigger user_entity_last_admin_guard"
        )
    try:
        cur.execute(
            """
            delete from public.contact
            where entity_id in (
              select id from public.entity where entity_name like %s
            )
            """,
            (f"%{MARKER}%",),
        )
        cur.execute(
            """
            delete from public.company
            where entity_id in (
              select id from public.entity where entity_name like %s
            )
            """,
            (f"%{MARKER}%",),
        )
        cur.execute(
            """
            delete from public.user_entity
            where entity_id in (
              select id from public.entity where entity_name like %s
            )
            """,
            (f"%{MARKER}%",),
        )
        cur.execute("delete from public.entity where entity_name like %s", (f"%{MARKER}%",))
        cur.execute("delete from public.app_user where email like %s", (f"%@{MARKER}",))
    finally:
        if last_admin_trigger:
            cur.execute(
                "alter table public.user_entity enable trigger user_entity_last_admin_guard"
            )


def _as_runtime(cur: psycopg.Cursor, user_id: str, entity_id: str) -> None:
    set_runtime_context(cur, user_id=user_id, active_entity_id=entity_id)


def prove_kernel() -> dict[str, object]:
    result: dict[str, object] = {}
    with runtime_connection() as connection, connection.cursor() as cur:
        _cleanup(cur)
        ids = _seed(cur)
        connection.commit()
        result["seeded"] = True

        try:
            _as_runtime(cur, ids["user_dual"], ids["entity_a"])
            cur.execute("select id from public.company order by company_name")
            visible = [str(row[0]) for row in cur.fetchall()]
            result["dual_in_a_sees_company_ids"] = visible
            if visible != [ids["company_a"]]:
                raise RuntimeError(f"dual user in entity A saw {visible}")

            cur.execute("select id from public.contact")
            contacts = [str(row[0]) for row in cur.fetchall()]
            result["dual_in_a_sees_contact_ids"] = contacts
            if contacts != [ids["contact_a"]]:
                raise RuntimeError(f"dual user in entity A saw contacts {contacts}")

            try:
                cur.execute(
                    """
                    insert into public.company (
                      entity_id, company_name, status, record_state
                    )
                    values (%s, 'Leak', 'Prospect', 'Active')
                    """,
                    (ids["entity_b"],),
                )
                result["cross_tenant_company_insert_blocked"] = False
                raise RuntimeError("cross-tenant company insert succeeded")
            except psycopg.Error:
                result["cross_tenant_company_insert_blocked"] = True
                connection.rollback()

            _as_runtime(cur, ids["user_dual"], ids["entity_a"])
            try:
                cur.execute(
                    """
                    insert into public.contact (
                      entity_id, company_id, first_name, last_name, record_state
                    )
                    values (%s, %s, 'Bad', 'Fk', 'Active')
                    """,
                    (ids["entity_a"], ids["company_b"]),
                )
                result["cross_tenant_contact_fk_blocked"] = False
                raise RuntimeError("cross-tenant contact FK insert succeeded")
            except psycopg.Error:
                result["cross_tenant_contact_fk_blocked"] = True
                connection.rollback()

            _as_runtime(cur, ids["user_dual"], ids["entity_a"])
            cur.execute("select count(*) from public.user_entity")
            membership_count = cur.fetchone()[0]
            result["user_entity_select_count"] = membership_count
            if membership_count < 1:
                raise RuntimeError("USER_ENTITY select returned no rows or recursed to empty")

            cur.execute("select public.app_has_active_membership(%s, %s)", (ids["user_dual"], ids["entity_a"]))
            result["helper_true_for_member"] = bool(cur.fetchone()[0])
            cur.execute("select public.app_authorize_membership(%s, %s)", (ids["user_b"], ids["entity_a"]))
            auth_row = cur.fetchone()
            result["helper_empty_for_non_member"] = auth_row is None
            if auth_row is not None:
                raise RuntimeError("authorize leaked a non-membership row")

            try:
                cur.execute("set local role app_authz")
                result["set_role_app_authz_denied"] = False
                raise RuntimeError("app_runtime assumed app_authz")
            except psycopg.Error:
                result["set_role_app_authz_denied"] = True
                connection.rollback()

            cur.execute(
                """
                select
                  has_function_privilege(
                    'anon', 'public.app_has_active_membership(uuid,uuid)', 'EXECUTE'
                  )
                  or has_function_privilege(
                    'authenticated', 'public.app_has_active_membership(uuid,uuid)', 'EXECUTE'
                  )
                  or has_function_privilege(
                    'anon', 'public.app_authorize_membership(uuid,uuid)', 'EXECUTE'
                  )
                  or has_function_privilege(
                    'authenticated', 'public.app_authorize_membership(uuid,uuid)', 'EXECUTE'
                  )
                """
            )
            public_exec = bool(cur.fetchone()[0])
            result["helpers_not_executable_by_anon_authenticated"] = not public_exec
            if public_exec:
                raise RuntimeError("anon/authenticated can EXECUTE helpers")

            _as_runtime(cur, ids["user_dual"], ids["entity_a"])
            cur.execute("set local search_path = pg_temp, public")
            cur.execute(
                "select public.app_has_active_membership(%s, %s)",
                (ids["user_dual"], ids["entity_a"]),
            )
            result["helper_stable_under_search_path"] = bool(cur.fetchone()[0])
            if not result["helper_stable_under_search_path"]:
                raise RuntimeError("helper failed after search_path change")

            connection.rollback()
            cur.execute(
                """
                insert into public.entity_domain (
                  entity_id, domain, status, is_primary, added_via
                )
                values (%s, 'second-a.kernel', 'Approved', true, 'Domain Addition Request')
                """,
                (ids["entity_a"],),
            )
            try:
                connection.commit()
                result["two_primaries_blocked"] = False
                raise RuntimeError("two Approved primaries committed")
            except psycopg.Error:
                result["two_primaries_blocked"] = True
                connection.rollback()

            cur.execute(
                """
                update public.entity_domain
                set is_primary = false
                where entity_id = %s and domain = 'tenant-a.kernel'
                """,
                (ids["entity_a"],),
            )
            cur.execute(
                """
                insert into public.entity_domain (
                  entity_id, domain, status, is_primary, added_via
                )
                values (%s, 'second-a.kernel', 'Approved', true, 'Domain Addition Request')
                """,
                (ids["entity_a"],),
            )
            connection.commit()
            result["primary_transfer_commits"] = True

            _as_runtime(cur, ids["user_dual"], ids["entity_a"])
            cur.execute(
                """
                explain
                select id from public.company
                where entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
                """
            )
            result["company_explain"] = " | ".join(row[0] for row in cur.fetchall())
            connection.rollback()
        finally:
            _cleanup(cur)
            connection.commit()

    result["current_user_expected"] = "app_runtime"
    result["used_auth_uid"] = False
    return result
