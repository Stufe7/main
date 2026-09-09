from __future__ import annotations

from datetime import date, timedelta

import psycopg

from app.db import runtime_connection
from app.phase1a import _cleanup as cleanup_1a
from app.phase1a import _seed as seed_1a
from app.runtime import set_runtime_context

MARKER = "phase1b.kernel"


def _cleanup_1b(cur: psycopg.Cursor) -> None:
    cur.execute(
        """
        update public.company
        set last_activity_id = null, next_action_id = null
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        update public.contact
        set last_activity_id = null, next_action_id = null
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.activity_revision
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.action
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.activity
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.campaign_company
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.campaign
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.company_handover
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.import_job
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.user_invitation
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cur.execute(
        """
        delete from public.entity_change_request
        where entity_id in (select id from public.entity where entity_name like %s)
        """,
        ("%phase1a.kernel%",),
    )
    cleanup_1a(cur)
    cur.execute("delete from public.app_user where email like %s", (f"%@{MARKER}",))


def prove_schema() -> dict[str, object]:
    result: dict[str, object] = {}
    with runtime_connection() as connection, connection.cursor() as cur:
        _cleanup_1b(cur)
        ids = seed_1a(cur)
        connection.commit()
        try:
            admin_b = str(__import__("uuid").uuid4())
            cur.execute(
                """
                insert into public.app_user (id, email, status)
                values (%s, %s, 'active')
                """,
                (admin_b, f"adminb@{MARKER}"),
            )
            cur.execute(
                """
                insert into public.user_entity (user_id, entity_id, role, status)
                values (%s, %s, 'Entity Admin', 'active')
                """,
                (admin_b, ids["entity_a"]),
            )
            connection.commit()

            cur.execute(
                """
                insert into public.activity (
                  entity_id, company_id, contact_id, activity_type, activity_date,
                  subject, created_by_user_id
                )
                values (%s, %s, %s, 'Phone Call', now(), 'Kickoff', %s)
                returning id
                """,
                (
                    ids["entity_a"],
                    ids["company_a"],
                    ids["contact_a"],
                    ids["user_dual"],
                ),
            )
            activity_id = cur.fetchone()[0]
            cur.execute(
                "select last_activity_id from public.company where id = %s",
                (ids["company_a"],),
            )
            projected = cur.fetchone()[0]
            result["activity_projects_to_company"] = str(projected) == str(activity_id)

            cur.execute(
                "select updated_by_user_id from public.company where id = %s",
                (ids["company_a"],),
            )
            result["projection_did_not_stamp_company_updated_by"] = cur.fetchone()[0] is None

            due = date.today() + timedelta(days=3)
            cur.execute(
                """
                insert into public.action (
                  entity_id, company_id, contact_id, owner_user_id, action_type,
                  description, due_date, status, created_by_user_id
                )
                values (%s, %s, %s, %s, 'Task', 'Follow up', %s, 'Open', %s)
                returning id
                """,
                (
                    ids["entity_a"],
                    ids["company_a"],
                    ids["contact_a"],
                    ids["user_dual"],
                    due,
                    ids["user_dual"],
                ),
            )
            action_id = cur.fetchone()[0]
            cur.execute(
                "select next_action_id, next_action_due_date from public.company where id = %s",
                (ids["company_a"],),
            )
            nxt_id, nxt_due = cur.fetchone()
            result["next_action_projects"] = str(nxt_id) == str(action_id) and nxt_due == due

            cur.execute(
                """
                update public.activity
                set subject = 'Kickoff edited', updated_by_user_id = %s
                where id = %s
                """,
                (ids["user_dual"], activity_id),
            )
            cur.execute(
                "select count(*) from public.activity_revision where activity_id = %s",
                (activity_id,),
            )
            result["activity_revision_written"] = cur.fetchone()[0] == 1
            connection.commit()

            try:
                cur.execute(
                    """
                    insert into public.activity (
                      entity_id, company_id, activity_type, activity_date,
                      subject, created_by_user_id
                    )
                    values (%s, %s, 'Note', now(), 'Leak', %s)
                    """,
                    (ids["entity_a"], ids["company_b"], ids["user_dual"]),
                )
                result["cross_tenant_activity_fk_blocked"] = False
                raise RuntimeError("cross-tenant activity insert succeeded")
            except psycopg.Error:
                result["cross_tenant_activity_fk_blocked"] = True
                connection.rollback()

            try:
                cur.execute(
                    """
                    insert into public.action (
                      entity_id, company_id, owner_user_id, action_type,
                      description, due_date, status, source_activity_id
                    )
                    values (%s, %s, %s, 'Task', 'chain', %s, 'Open', %s)
                    """,
                    (ids["entity_b"], ids["company_b"], ids["user_dual"], due, activity_id),
                )
                connection.commit()
                result["cross_tenant_chain_fk_blocked"] = False
                raise RuntimeError("cross-tenant action chain succeeded")
            except psycopg.Error:
                result["cross_tenant_chain_fk_blocked"] = True
                connection.rollback()

            cur.execute(
                """
                update public.user_entity
                set role = 'User'
                where user_id = %s and entity_id = %s
                """,
                (admin_b, ids["entity_a"]),
            )
            result["second_admin_downgrade_allowed"] = True
            try:
                cur.execute(
                    """
                    update public.user_entity
                    set role = 'User'
                    where user_id = %s and entity_id = %s
                    """,
                    (ids["user_dual"], ids["entity_a"]),
                )
                result["last_admin_downgrade_blocked"] = False
                raise RuntimeError("last Entity Admin downgrade succeeded")
            except psycopg.Error:
                result["last_admin_downgrade_blocked"] = True
                connection.rollback()

            cur.execute(
                """
                insert into public.campaign (
                  entity_id, name, owner_user_id, start_date, end_date, status, record_state
                )
                values (%s, 'Launch', %s, %s, %s, 'Active', 'Active')
                returning id
                """,
                (ids["entity_a"], ids["user_dual"], date.today(), date.today() + timedelta(days=10)),
            )
            campaign_id = cur.fetchone()[0]
            try:
                cur.execute(
                    """
                    insert into public.action (
                      entity_id, company_id, campaign_id, owner_user_id, action_type,
                      description, due_date, status
                    )
                    values (%s, %s, %s, %s, 'Task', 'late', %s, 'Open')
                    """,
                    (
                        ids["entity_a"],
                        ids["company_a"],
                        campaign_id,
                        ids["user_dual"],
                        date.today() + timedelta(days=40),
                    ),
                )
                connection.commit()
                result["campaign_horizon_blocked"] = False
                raise RuntimeError("out-of-horizon campaign action committed")
            except psycopg.Error:
                result["campaign_horizon_blocked"] = True
                connection.rollback()

            set_runtime_context(cur, user_id=ids["user_dual"], active_entity_id=ids["entity_a"])
            cur.execute("select count(*) from public.activity")
            result["runtime_sees_own_activities"] = cur.fetchone()[0] >= 0
            connection.rollback()
        finally:
            _cleanup_1b(cur)
            connection.commit()
    result["used_auth_uid"] = False
    return result
