from __future__ import annotations

import logging
import secrets
from datetime import UTC, datetime
from typing import Annotated, Any

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException

from app.db import job_connection
from app.mail import send_updates_mail
from app.settings import settings

log = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/jobs", tags=["jobs"])

DENY_LIST_URL = (
    "https://raw.githubusercontent.com/disposable-email-domains/"
    "disposable-email-domains/master/disposable_email_blocklist.conf"
)
DENY_SHA_URL = (
    "https://api.github.com/repos/disposable-email-domains/"
    "disposable-email-domains/commits"
)


def require_job_secret(
    x_job_secret: Annotated[str | None, Header()] = None,
) -> str:
    expected = settings.job_secret
    if not expected:
        raise HTTPException(status_code=503, detail="JOB_SECRET is not set")
    provided = x_job_secret or ""
    if len(provided) != len(expected) or not secrets.compare_digest(provided, expected):
        raise HTTPException(status_code=401, detail="Invalid job secret")
    return provided


def _format_actions(rows: list[tuple], bucket: str) -> list[str]:
    lines = [f"{bucket}"]
    for row in rows:
        company, action_type, description, due_date, due_time, _bucket, _company_id = row
        when = due_date.isoformat() if due_date else ""
        if due_time:
            when = f"{when} {str(due_time)[:5]}"
        lines.append(f"- {company}: {action_type} — {description} (due {when})")
    return lines


def _send_digest(cur, row: tuple) -> str:
    user_id, email, entity_id, entity_name, timezone, frequency, local_date = row
    cur.execute(
        "select * from public.app_job_digest_actions(%s, %s, %s, %s)",
        (user_id, entity_id, frequency, local_date),
    )
    actions = cur.fetchall()
    overdue = [item for item in actions if item[5] == "Overdue"]
    upcoming = [item for item in actions if item[5] == "Upcoming"]
    if overdue or upcoming:
        body_lines = [
            f"Stufe7 Action Digest — {entity_name} — {local_date.isoformat()}",
            f"Timezone: {timezone} · Cadence: {frequency}",
            "",
        ]
        if overdue:
            body_lines.extend(_format_actions(overdue, "Overdue"))
            body_lines.append("")
        if upcoming:
            body_lines.extend(_format_actions(upcoming, "Upcoming / Due"))
            body_lines.append("")
        body_lines.append(f"Open: {settings.public_app_url.rstrip('/')}/app")
        send_updates_mail(
            email,
            f"Action Digest — {entity_name}",
            "\n".join(body_lines),
        )
        result = "sent"
    else:
        result = "empty"
    cur.execute(
        "select public.app_job_mark_digest_sent(%s, %s, %s)",
        (user_id, entity_id, local_date),
    )
    return result


def _run_digests() -> dict[str, int]:
    counts = {"due": 0, "sent": 0, "empty": 0, "failed": 0}
    with job_connection() as connection, connection.cursor() as cur:
        cur.execute("select * from public.app_job_digest_due()")
        due_rows = cur.fetchall()
        counts["due"] = len(due_rows)
        for row in due_rows:
            try:
                outcome = _send_digest(cur, row)
                connection.commit()
                counts[outcome] = counts.get(outcome, 0) + 1
            except Exception:
                log.exception("digest send failed for %s", row[1])
                connection.rollback()
                counts["failed"] += 1
    return counts


def _run_campaigns() -> dict[str, Any]:
    with job_connection() as connection, connection.cursor() as cur:
        cur.execute("select public.app_job_close_ended_campaigns()")
        payload = cur.fetchone()[0]
        connection.commit()
    return payload


def _run_weekly_stat() -> dict[str, Any]:
    with job_connection() as connection, connection.cursor() as cur:
        cur.execute("select public.app_job_upsert_weekly_stat()")
        payload = cur.fetchone()[0]
        connection.commit()
    return payload


def _deny_source_version() -> str:
    try:
        response = httpx.get(
            DENY_SHA_URL,
            params={"path": "disposable_email_blocklist.conf", "per_page": 1},
            headers={"Accept": "application/vnd.github+json"},
            timeout=15.0,
        )
        if response.status_code < 300:
            sha = response.json()[0]["sha"]
            return f"disposable-email-domains:{sha[:12]}"
    except Exception:
        log.exception("deny-list version lookup failed")
    return f"disposable-email-domains:{datetime.now(UTC).date().isoformat()}"


def _run_deny_list() -> dict[str, Any]:
    with job_connection() as connection, connection.cursor() as cur:
        cur.execute("select public.app_job_deny_refresh_stale()")
        stale = bool(cur.fetchone()[0])
        if not stale:
            return {"status": "skipped", "reason": "refreshed within 7 days"}
        try:
            response = httpx.get(DENY_LIST_URL, timeout=30.0)
            response.raise_for_status()
            domains = [
                line.strip().lower()
                for line in response.text.splitlines()
                if line.strip() and not line.strip().startswith("#")
            ]
            if not domains:
                raise RuntimeError("deny list download was empty")
            version = _deny_source_version()
            cur.execute(
                "select public.app_job_replace_source_deny(%s, %s)",
                (domains, version),
            )
            kept = cur.fetchone()[0]
            connection.commit()
            return {"status": "Success", "entry_count": kept, "source_version": version}
        except Exception as exc:
            log.exception("deny-list refresh failed")
            connection.rollback()
            cur.execute("select public.app_job_deny_refresh_failed(%s)", (str(exc)[:500],))
            connection.commit()
            return {"status": "FailedKeptLastGood", "error": str(exc)[:200]}


def _auth_headers() -> dict[str, str] | None:
    key = settings.supabase_service_role_key
    base = settings.supabase_url.rstrip("/")
    if not key or not base:
        return None
    return {
        "Authorization": f"Bearer {key}",
        "apikey": key,
        "Content-Type": "application/json",
    }


def _delete_auth_user(user_id: str) -> str:
    headers = _auth_headers()
    if headers is None:
        return "skipped"
    base = settings.supabase_url.rstrip("/")
    response = httpx.delete(
        f"{base}/auth/v1/admin/users/{user_id}",
        headers=headers,
        timeout=15.0,
    )
    if response.status_code in (200, 204, 404):
        return "deleted" if response.status_code != 404 else "missing"
    log.error("Auth orphan delete %s: %s", response.status_code, response.text)
    return "failed"


def _sweep_auth_orphans() -> dict[str, int]:
    headers = _auth_headers()
    counts = {"deleted": 0, "skipped": 0, "failed": 0}
    if headers is None:
        log.info("Auth orphan sweep skipped (no SUPABASE_SERVICE_ROLE_KEY)")
        counts["skipped"] = 1
        return counts
    base = settings.supabase_url.rstrip("/")
    page = 1
    cutoff = datetime.now(UTC).timestamp() - (30 * 24 * 3600)
    while True:
        response = httpx.get(
            f"{base}/auth/v1/admin/users",
            params={"page": page, "per_page": 200},
            headers=headers,
            timeout=30.0,
        )
        if response.status_code >= 300:
            log.error("Auth list users %s: %s", response.status_code, response.text)
            counts["failed"] += 1
            break
        users = response.json().get("users") or []
        if not users:
            break
        ids = [str(row.get("id")) for row in users if row.get("id")]
        created = {
            str(row.get("id")): row.get("created_at")
            for row in users
            if row.get("id")
        }
        if not ids:
            break
        with job_connection() as connection, connection.cursor() as cur:
            cur.execute(
                """
                select u.id::text
                from unnest(%s::uuid[]) as u(id)
                where not exists (
                  select 1 from public.app_user a where a.id = u.id
                )
                and not exists (
                  select 1 from public.user_entity ue where ue.user_id = u.id
                )
                and not public.app_job_held('AUTH_IDENTITY', u.id)
                and not public.app_job_held('USER', u.id)
                """,
                (ids,),
            )
            eligible = {row[0] for row in cur.fetchall()}
        for user_id in eligible:
            stamp = created.get(user_id) or ""
            try:
                created_at = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
                if created_at.timestamp() > cutoff:
                    continue
            except ValueError:
                continue
            outcome = _delete_auth_user(user_id)
            counts[outcome if outcome in counts else "failed"] = (
                counts.get(outcome if outcome in counts else "failed", 0) + 1
            )
        if len(users) < 200:
            break
        page += 1
    return counts


def _run_retention() -> dict[str, Any]:
    with job_connection() as connection, connection.cursor() as cur:
        cur.execute("select public.app_job_retain_registrations()")
        payload = cur.fetchone()[0]
        connection.commit()
    orphan_ids = [str(item) for item in (payload.get("orphan_user_ids") or [])]
    auth_from_sql = {"deleted": 0, "missing": 0, "failed": 0, "skipped": 0}
    for user_id in orphan_ids:
        outcome = _delete_auth_user(user_id)
        auth_from_sql[outcome] = auth_from_sql.get(outcome, 0) + 1
    payload["auth_orphans_from_sql"] = auth_from_sql
    if datetime.now(UTC).hour == 0:
        payload["auth_orphans_unverified"] = _sweep_auth_orphans()
    else:
        payload["auth_orphans_unverified"] = {"skipped": 1, "reason": "not UTC hour 0"}
    return payload


def run_all_jobs() -> dict[str, Any]:
    return {
        "ran_at": datetime.now(UTC).isoformat(),
        "campaigns": _run_campaigns(),
        "digest": _run_digests(),
        "weekly_stat": _run_weekly_stat(),
        "deny_list": _run_deny_list(),
        "retention": _run_retention(),
    }


@router.post("/run")
def run_jobs(_secret: Annotated[str, Depends(require_job_secret)]) -> dict[str, Any]:
    return run_all_jobs()
