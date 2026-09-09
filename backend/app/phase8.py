from __future__ import annotations

REQUIRED_INDEXES = (
    "user_entity_authz_idx",
    "company_entity_id_idx",
    "contact_entity_id_idx",
    "company_entity_state_name_idx",
    "contact_entity_state_name_idx",
    "activity_entity_company_date_idx",
    "action_entity_open_due_idx",
    "campaign_entity_id_idx",
    "campaign_entity_status_idx",
)

TENANT_TABLES = (
    "app_user",
    "entity",
    "user_entity",
    "entity_domain",
    "company",
    "contact",
    "campaign",
    "activity",
    "action",
    "job_run",
)


def prove_hardening(cur) -> dict[str, object]:
    cur.execute(
        """
        select indexname
        from pg_indexes
        where schemaname = 'public' and indexname = any(%s)
        """,
        (list(REQUIRED_INDEXES),),
    )
    found = {row[0] for row in cur.fetchall()}
    missing = [name for name in REQUIRED_INDEXES if name not in found]
    cur.execute(
        """
        select c.relname, c.relforcerowsecurity
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname = any(%s)
        """,
        (list(TENANT_TABLES),),
    )
    force = {row[0]: bool(row[1]) for row in cur.fetchall()}
    cur.execute(
        """
        select has_table_privilege('app_runtime', 'public.job_run', 'SELECT')
            or has_table_privilege('app_runtime', 'public.job_run', 'INSERT')
            or has_function_privilege(
              'app_runtime', 'public.app_job_record_run(text,text,jsonb,timestamptz)', 'EXECUTE'
            )
        """
    )
    runtime_job = bool(cur.fetchone()[0])
    return {
        "missing_indexes": missing,
        "force_rls": force,
        "runtime_cannot_touch_job_run": not runtime_job,
        "pass": not missing
        and all(force.get(name) for name in TENANT_TABLES)
        and not runtime_job,
    }
