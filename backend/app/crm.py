from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import Annotated, Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["crm"])

ACTIVITY_TYPES = ("Note", "Phone Call", "Email", "Meeting / Visit", "WhatsApp")  # noqa: F401
ACTION_TYPES = ("Phone Call", "Email", "Meeting / Visit", "WhatsApp", "Task")  # noqa: F401


class FollowUpIn(BaseModel):
    action_type: str = "Task"
    description: str = Field(min_length=1)
    due_date: date
    due_time: str | None = None
    priority: str = "Normal"
    owner_user_id: str | None = None
    contact_id: str | None = None


class ActivityIn(BaseModel):
    company_id: str
    contact_id: str | None = None
    activity_type: str = "Note"
    activity_date: datetime | None = None
    subject: str = Field(min_length=1)
    description: str | None = None
    outcome: str | None = None
    follow_up: FollowUpIn | None = None


class ActivityOut(BaseModel):
    id: str
    company_id: str
    company_name: str | None = None
    contact_id: str | None
    activity_type: str
    activity_date: str
    subject: str
    description: str | None
    outcome: str | None
    source_action_id: str | None


class RevisionOut(BaseModel):
    revision_number: int
    subject: str
    description: str | None
    outcome: str | None
    edited_at: str
    edited_by_user_id: str


class ActionOut(BaseModel):
    id: str
    company_id: str
    company_name: str | None = None
    contact_id: str | None
    owner_user_id: str
    action_type: str
    description: str
    due_date: str | None
    due_time: str | None
    priority: str
    status: str
    source_activity_id: str | None


class ActionIn(BaseModel):
    company_id: str
    contact_id: str | None = None
    owner_user_id: str | None = None
    action_type: str = "Task"
    description: str = Field(min_length=1)
    due_date: date
    due_time: str | None = None
    priority: str = "Normal"


class CompleteIn(BaseModel):
    activity_type: str = "Note"
    subject: str = Field(min_length=1)
    outcome: str | None = None
    description: str | None = None
    follow_up: FollowUpIn | None = None


class CancelIn(BaseModel):
    reason: str = Field(min_length=1)


class HandoverOut(BaseModel):
    id: str
    company_id: str
    company_name: str
    reason: str
    created_at: str


class HomeOut(BaseModel):
    timezone: str
    today: str
    actions: list[ActionOut]
    attention_count: int
    handovers: list[HandoverOut]


def _activity_row(row: tuple) -> ActivityOut:
    return ActivityOut(
        id=str(row[0]),
        company_id=str(row[1]),
        company_name=row[2],
        contact_id=str(row[3]) if row[3] else None,
        activity_type=row[4],
        activity_date=row[5].isoformat(),
        subject=row[6],
        description=row[7],
        outcome=row[8],
        source_action_id=str(row[9]) if row[9] else None,
    )


def _action_row(row: tuple) -> ActionOut:
    due_time = row[8]
    return ActionOut(
        id=str(row[0]),
        company_id=str(row[1]),
        company_name=row[2],
        contact_id=str(row[3]) if row[3] else None,
        owner_user_id=str(row[4]),
        action_type=row[5],
        description=row[6],
        due_date=row[7].isoformat() if row[7] else None,
        due_time=str(due_time)[:8] if due_time else None,
        priority=row[9],
        status=row[10],
        source_activity_id=str(row[11]) if row[11] else None,
    )


_ACT_SELECT = """
    select a.id, a.company_id, co.company_name, a.contact_id, a.activity_type,
           a.activity_date, a.subject, a.description, a.outcome, a.source_action_id
    from public.activity a
    join public.company co on co.id = a.company_id and co.entity_id = a.entity_id
"""

_ACTN_SELECT = """
    select x.id, x.company_id, co.company_name, x.contact_id, x.owner_user_id,
           x.action_type, x.description, x.due_date, x.due_time, x.priority,
           x.status, x.source_activity_id
    from public.action x
    join public.company co on co.id = x.company_id and co.entity_id = x.entity_id
"""


def _entity_today(cur, entity_id: str) -> tuple[str, date, date]:
    cur.execute(
        "select reference_timezone from public.entity where id = %s",
        (entity_id,),
    )
    row = cur.fetchone()
    tz_name = row[0] if row else "UTC"
    today = datetime.now(ZoneInfo(tz_name)).date()
    week_end = today + timedelta(days=(6 - today.weekday()))
    return tz_name, today, week_end


def _insert_follow_up(
    cur,
    *,
    entity_id: str,
    user_id: str,
    company_id: str,
    follow: FollowUpIn,
    source_activity_id: str,
    default_contact: str | None,
) -> None:
    cur.execute(
        """
        insert into public.action (
          entity_id, company_id, contact_id, owner_user_id, action_type, description,
          due_date, due_time, priority, status, source_activity_id,
          created_by_user_id, updated_by_user_id
        )
        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'Open', %s, %s, %s)
        """,
        (
            entity_id,
            company_id,
            follow.contact_id or default_contact,
            follow.owner_user_id or user_id,
            follow.action_type,
            follow.description.strip(),
            follow.due_date,
            follow.due_time,
            follow.priority,
            source_activity_id,
            user_id,
            user_id,
        ),
    )


@router.get("/activities", response_model=list[ActivityOut])
def list_activities(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
    company_id: str | None = None,
    contact_id: str | None = None,
) -> list[ActivityOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        params: list[object] = [entity_id]
        where = "a.entity_id = %s"
        if company_id:
            where += " and a.company_id = %s"
            params.append(company_id)
        if contact_id:
            where += " and a.contact_id = %s"
            params.append(contact_id)
        cur.execute(
            f"{_ACT_SELECT} where {where} order by a.activity_date desc, a.created_at desc limit 200",
            params,
        )
        return [_activity_row(row) for row in cur.fetchall()]


@router.post("/activities", response_model=ActivityOut)
def create_activity(
    body: ActivityIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> ActivityOut:
    when = body.activity_date or datetime.now(UTC)
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                """
                insert into public.activity (
                  entity_id, company_id, contact_id, activity_type, activity_date,
                  subject, description, outcome, created_by_user_id, updated_by_user_id
                )
                values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                returning id
                """,
                (
                    entity_id,
                    body.company_id,
                    body.contact_id,
                    body.activity_type,
                    when,
                    body.subject.strip(),
                    body.description,
                    body.outcome,
                    user_id,
                    user_id,
                ),
            )
            activity_id = str(cur.fetchone()[0])
            if body.follow_up:
                _insert_follow_up(
                    cur,
                    entity_id=entity_id,
                    user_id=user_id,
                    company_id=body.company_id,
                    follow=body.follow_up,
                    source_activity_id=activity_id,
                    default_contact=body.contact_id,
                )
            cur.execute(
                f"{_ACT_SELECT} where a.id = %s and a.entity_id = %s",
                (activity_id, entity_id),
            )
            row = cur.fetchone()
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return _activity_row(row)


@router.get("/activities/{activity_id}")
def get_activity(
    activity_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, Any]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            f"{_ACT_SELECT} where a.id = %s and a.entity_id = %s",
            (activity_id, entity_id),
        )
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Activity not found")
        cur.execute(
            """
            select revision_number, subject, description, outcome, edited_at, edited_by_user_id
            from public.activity_revision
            where activity_id = %s and entity_id = %s
            order by revision_number desc
            """,
            (activity_id, entity_id),
        )
        revisions = [
            RevisionOut(
                revision_number=item[0],
                subject=item[1],
                description=item[2],
                outcome=item[3],
                edited_at=item[4].isoformat(),
                edited_by_user_id=str(item[5]),
            )
            for item in cur.fetchall()
        ]
    return {"activity": _activity_row(row).model_dump(), "revisions": [r.model_dump() for r in revisions]}


@router.patch("/activities/{activity_id}", response_model=ActivityOut)
def patch_activity(
    activity_id: str,
    body: ActivityIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> ActivityOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                """
                update public.activity
                set company_id = %s, contact_id = %s, activity_type = %s,
                    activity_date = coalesce(%s, activity_date),
                    subject = %s, description = %s, outcome = %s,
                    updated_by_user_id = %s, updated_at = now()
                where id = %s and entity_id = %s
                """,
                (
                    body.company_id,
                    body.contact_id,
                    body.activity_type,
                    body.activity_date,
                    body.subject.strip(),
                    body.description,
                    body.outcome,
                    user_id,
                    activity_id,
                    entity_id,
                ),
            )
        except Exception as exc:
            raise_pg(exc)
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Activity not found")
        cur.execute(
            f"{_ACT_SELECT} where a.id = %s and a.entity_id = %s",
            (activity_id, entity_id),
        )
        row = cur.fetchone()
        connection.commit()
    return _activity_row(row)


@router.get("/actions", response_model=list[ActionOut])
def list_actions(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
    company_id: str | None = None,
    contact_id: str | None = None,
    horizon: str = Query(default="open"),
    scope: str = Query(default="my"),
) -> list[ActionOut]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        _tz, today, week_end = _entity_today(cur, entity_id)
        params: list[object] = [entity_id]
        where = "x.entity_id = %s and x.status = 'Open'"
        if company_id:
            where += " and x.company_id = %s"
            params.append(company_id)
        if contact_id:
            where += " and x.contact_id = %s"
            params.append(contact_id)
        if scope == "my":
            where += " and x.owner_user_id = %s"
            params.append(user_id)
        if horizon == "overdue":
            where += " and x.due_date < %s"
            params.append(today)
        elif horizon == "today":
            where += " and x.due_date = %s"
            params.append(today)
        elif horizon == "week":
            where += " and x.due_date >= %s and x.due_date <= %s"
            params.extend([today, week_end])
        cur.execute(
            f"""
            {_ACTN_SELECT}
            where {where}
            order by x.due_date asc, (x.due_time is null), x.due_time asc,
                     case x.priority when 'High' then 0 when 'Normal' then 1 else 2 end,
                     x.created_at asc
            limit 200
            """,
            params,
        )
        return [_action_row(row) for row in cur.fetchall()]


@router.post("/actions", response_model=ActionOut)
def create_action(
    body: ActionIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> ActionOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            cur.execute(
                """
                insert into public.action (
                  entity_id, company_id, contact_id, owner_user_id, action_type,
                  description, due_date, due_time, priority, status,
                  created_by_user_id, updated_by_user_id
                )
                values (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'Open', %s, %s)
                returning id
                """,
                (
                    entity_id,
                    body.company_id,
                    body.contact_id,
                    body.owner_user_id or user_id,
                    body.action_type,
                    body.description.strip(),
                    body.due_date,
                    body.due_time,
                    body.priority,
                    user_id,
                    user_id,
                ),
            )
        except Exception as exc:
            raise_pg(exc)
        action_id = cur.fetchone()[0]
        cur.execute(f"{_ACTN_SELECT} where x.id = %s and x.entity_id = %s", (action_id, entity_id))
        row = cur.fetchone()
        connection.commit()
    return _action_row(row)


@router.post("/actions/{action_id}/complete", response_model=ActivityOut)
def complete_action(
    action_id: str,
    body: CompleteIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> ActivityOut:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select company_id, contact_id, status
            from public.action
            where id = %s and entity_id = %s
            """,
            (action_id, entity_id),
        )
        current = cur.fetchone()
        if not current:
            raise HTTPException(status_code=404, detail="Action not found")
        if current[2] != "Open":
            raise HTTPException(status_code=400, detail="Action is not open")
        company_id, contact_id = str(current[0]), str(current[1]) if current[1] else None
        try:
            cur.execute(
                """
                insert into public.activity (
                  entity_id, company_id, contact_id, activity_type, activity_date,
                  subject, description, outcome, source_action_id,
                  created_by_user_id, updated_by_user_id
                )
                values (%s, %s, %s, %s, now(), %s, %s, %s, %s, %s, %s)
                returning id
                """,
                (
                    entity_id,
                    company_id,
                    contact_id,
                    body.activity_type,
                    body.subject.strip(),
                    body.description,
                    body.outcome,
                    action_id,
                    user_id,
                    user_id,
                ),
            )
            activity_id = str(cur.fetchone()[0])
            cur.execute(
                """
                update public.action
                set status = 'Completed', completed_at = now(),
                    updated_by_user_id = %s, updated_at = now()
                where id = %s and entity_id = %s
                """,
                (user_id, action_id, entity_id),
            )
            if body.follow_up:
                _insert_follow_up(
                    cur,
                    entity_id=entity_id,
                    user_id=user_id,
                    company_id=company_id,
                    follow=body.follow_up,
                    source_activity_id=activity_id,
                    default_contact=contact_id,
                )
            cur.execute(
                f"{_ACT_SELECT} where a.id = %s and a.entity_id = %s",
                (activity_id, entity_id),
            )
            row = cur.fetchone()
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)
    return _activity_row(row)


@router.post("/actions/{action_id}/cancel")
def cancel_action(
    action_id: str,
    body: CancelIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            update public.action
            set status = 'Cancelled', cancelled_at = now(),
                cancellation_reason = %s, updated_by_user_id = %s, updated_at = now()
            where id = %s and entity_id = %s and status = 'Open'
            """,
            (body.reason, user_id, action_id, entity_id),
        )
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Open action not found")
        connection.commit()
    return {"status": "cancelled"}


@router.get("/home", response_model=HomeOut)
def home(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
    horizon: str = Query(default="today"),
    scope: str = Query(default="my"),
) -> HomeOut:
    actions = list_actions(
        claims=claims,
        user_id=user_id,
        entity_id=entity_id,
        horizon=horizon,
        scope=scope,
    )
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        tz_name, today, _week_end = _entity_today(cur, entity_id)
        cur.execute(
            """
            select count(*) from public.company
            where entity_id = %s and record_state = 'Active'
              and next_action_due_date is not null and next_action_due_date < %s
            """,
            (entity_id, today),
        )
        attention = int(cur.fetchone()[0])
        cur.execute(
            """
            select h.id, h.company_id, c.company_name, h.reason, h.created_at
            from public.company_handover h
            join public.company c on c.id = h.company_id and c.entity_id = h.entity_id
            where h.entity_id = %s and h.to_user_id = %s and h.status = 'Pending Review'
            order by h.created_at
            """,
            (entity_id, user_id),
        )
        handovers = [
            HandoverOut(
                id=str(row[0]),
                company_id=str(row[1]),
                company_name=row[2],
                reason=row[3],
                created_at=row[4].isoformat(),
            )
            for row in cur.fetchall()
        ]
    return HomeOut(
        timezone=tz_name,
        today=today.isoformat(),
        actions=actions,
        attention_count=attention,
        handovers=handovers,
    )


@router.post("/handovers/{handover_id}/ack")
def ack_handover(
    handover_id: str,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            update public.company_handover
            set status = 'Reviewed', reviewed_by_user_id = %s, reviewed_at = now()
            where id = %s and entity_id = %s and to_user_id = %s
              and status = 'Pending Review'
            """,
            (user_id, handover_id, entity_id, user_id),
        )
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Handover not found")
        connection.commit()
    return {"status": "reviewed"}


@router.post("/handovers/ack-all")
def ack_all_handovers(
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, str]:
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            update public.company_handover
            set status = 'Reviewed', reviewed_by_user_id = %s, reviewed_at = now()
            where entity_id = %s and to_user_id = %s and status = 'Pending Review'
            """,
            (user_id, entity_id, user_id),
        )
        connection.commit()
    return {"status": "reviewed"}
