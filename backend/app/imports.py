from __future__ import annotations

import csv
import io
import re
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from app.authn import Claims, bearer_claims, require_user_id
from app.db import runtime_connection
from app.tenant import bind_request, raise_pg, require_entity_id

router = APIRouter(prefix="/v1", tags=["imports"])

HEADERS = [
    "Company Name",
    "Legal Name",
    "Country",
    "City",
    "Address",
    "Website",
    "Telephone",
    "Nature of Business",
    "Company Status",
    "Owner Email",
    "Contact First Name",
    "Contact Last Name",
    "Contact Title",
    "Contact Telephone",
    "Contact Mobile",
    "Contact Email",
    "LinkedIn URL",
]

STATUSES = {"Prospect", "Customer", "Former Customer", "Inactive"}
BATCH = 50
TEMPLATE = ",".join(HEADERS) + "\n"


class PreviewIn(BaseModel):
    filename: str = "import.csv"
    csv_text: str = Field(min_length=1)


class PreviewRow(BaseModel):
    index: int
    company_name: str
    legal_name: str | None = None
    country: str | None = None
    city: str | None = None
    address: str | None = None
    website: str | None = None
    telephone: str | None = None
    nature_of_business: str | None = None
    company_status: str = "Prospect"
    owner_email: str | None = None
    owner_user_id: str | None = None
    contact_first_name: str | None = None
    contact_last_name: str | None = None
    contact_title: str | None = None
    contact_telephone: str | None = None
    contact_mobile: str | None = None
    contact_email: str | None = None
    linkedin_url: str | None = None
    flag: str
    match_company_id: str | None = None
    match_company_name: str | None = None
    error: str | None = None
    action: str = "create"


class PreviewOut(BaseModel):
    filename: str
    row_count: int
    new_company_count: int
    possible_duplicate_count: int
    unmatched_owner_count: int
    invalid_row_count: int
    rows: list[PreviewRow]


class ConfirmIn(BaseModel):
    filename: str = "import.csv"
    owner_fallback: str = "null"
    rows: list[PreviewRow]


def _blank(value: str | None) -> str | None:
    text = (value or "").strip()
    return text or None


def _norm_name(value: str) -> str:
    folded = value.strip().casefold()
    folded = re.sub(r"[^\w\s]", "", folded, flags=re.UNICODE)
    return re.sub(r"\s+", " ", folded).strip()


def _cell(row: dict[str, str], key: str) -> str | None:
    return _blank(row.get(key))


def _parse_rows(csv_text: str) -> list[dict[str, str]]:
    reader = csv.DictReader(io.StringIO(csv_text))
    if not reader.fieldnames:
        raise HTTPException(status_code=400, detail="CSV has no header row")
    missing = [name for name in HEADERS if name not in reader.fieldnames]
    if missing:
        raise HTTPException(status_code=400, detail=f"CSV is missing columns: {', '.join(missing)}")
    return [{key: (row.get(key) or "") for key in HEADERS} for row in reader]


@router.get("/imports/template")
def import_template() -> PlainTextResponse:
    return PlainTextResponse(TEMPLATE, media_type="text/csv")


@router.post("/imports/preview", response_model=PreviewOut)
def preview_import(
    body: PreviewIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> PreviewOut:
    parsed = _parse_rows(body.csv_text)
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select role from public.user_entity
            where user_id = %s and entity_id = %s and status = 'active'
            """,
            (user_id, entity_id),
        )
        role = cur.fetchone()
        if not role or role[0] != "Entity Admin":
            raise HTTPException(status_code=403, detail="not an Entity Admin")
        cur.execute(
            """
            select id, company_name, country
            from public.company
            where entity_id = %s and record_state = 'Active'
            """,
            (entity_id,),
        )
        existing = [
            {
                "id": str(row[0]),
                "name": row[1],
                "norm": _norm_name(row[1]),
                "country": row[2],
            }
            for row in cur.fetchall()
        ]
        cur.execute("select * from public.app_list_members(%s, %s)", (user_id, entity_id))
        members = {str(row[1]).casefold(): str(row[0]) for row in cur.fetchall() if row[1]}
    rows = [_classify(index, raw, existing, members) for index, raw in enumerate(parsed, start=1)]
    return PreviewOut(
        filename=body.filename,
        row_count=len(rows),
        new_company_count=sum(1 for row in rows if row.flag == "new"),
        possible_duplicate_count=sum(
            1 for row in rows if row.flag in ("duplicate", "possible_duplicate")
        ),
        unmatched_owner_count=sum(1 for row in rows if row.flag == "unmatched_owner"),
        invalid_row_count=sum(1 for row in rows if row.flag == "invalid"),
        rows=rows,
    )


@router.post("/imports/confirm")
def confirm_import(
    body: ConfirmIn,
    claims: Annotated[Claims, Depends(bearer_claims)],
    user_id: Annotated[str, Depends(require_user_id)],
    entity_id: Annotated[str, Depends(require_entity_id)],
) -> dict[str, Any]:
    to_import = [row for row in body.rows if row.action in ("create", "attach") and row.flag != "invalid"]
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        cur.execute(
            """
            select role from public.user_entity
            where user_id = %s and entity_id = %s and status = 'active'
            """,
            (user_id, entity_id),
        )
        role = cur.fetchone()
        if not role or role[0] != "Entity Admin":
            raise HTTPException(status_code=403, detail="not an Entity Admin")
        try:
            cur.execute(
                """
                insert into public.import_job (
                  entity_id, filename, status, row_count, new_company_count,
                  possible_duplicate_count, unmatched_owner_count, invalid_row_count,
                  created_by_user_id
                )
                values (%s, %s, 'Validated', %s, %s, %s, %s, %s, %s)
                returning id
                """,
                (
                    entity_id,
                    body.filename,
                    len(body.rows),
                    sum(1 for row in body.rows if row.flag == "new"),
                    sum(1 for row in body.rows if row.flag in ("duplicate", "possible_duplicate")),
                    sum(1 for row in body.rows if row.flag == "unmatched_owner"),
                    sum(1 for row in body.rows if row.flag == "invalid"),
                    user_id,
                ),
            )
            job_id = str(cur.fetchone()[0])
            connection.commit()
        except Exception as exc:
            connection.rollback()
            raise_pg(exc)

    imported = 0
    try:
        for offset in range(0, len(to_import), BATCH):
            batch = to_import[offset : offset + BATCH]
            imported += _import_batch(
                claims, user_id, entity_id, batch, body.owner_fallback
            )
        with runtime_connection() as connection, connection.cursor() as cur:
            bind_request(cur, claims, entity_id)
            cur.execute(
                """
                update public.import_job
                set status = 'Imported', completed_at = now()
                where id = %s and entity_id = %s
                """,
                (job_id, entity_id),
            )
            connection.commit()
    except Exception as exc:
        with runtime_connection() as connection, connection.cursor() as cur:
            bind_request(cur, claims, entity_id)
            cur.execute(
                """
                update public.import_job
                set status = 'Failed', completed_at = now()
                where id = %s and entity_id = %s
                """,
                (job_id, entity_id),
            )
            connection.commit()
        raise_pg(exc)
    return {"status": "Imported", "job_id": job_id, "imported_rows": imported}


def _classify(
    index: int,
    raw: dict[str, str],
    existing: list[dict[str, Any]],
    members: dict[str, str],
) -> PreviewRow:
    name = _cell(raw, "Company Name")
    country = _cell(raw, "Country")
    status = _cell(raw, "Company Status") or "Prospect"
    owner_email = _cell(raw, "Owner Email")
    contact_email = _cell(raw, "Contact Email")
    error = None
    if not name:
        error = "Company Name is required"
    elif status not in STATUSES:
        error = "invalid Company Status"
    elif country and len(country) != 2:
        error = "Country must be a 2-letter code"
    elif contact_email and "@" not in contact_email:
        error = "invalid Contact Email"
    owner_id = members.get(owner_email.casefold()) if owner_email else None
    flag = "new"
    match_id = None
    match_name = None
    action = "create"
    if error:
        flag = "invalid"
        action = "skip"
    else:
        norm = _norm_name(name or "")
        hits = [row for row in existing if row["norm"] == norm]
        if country:
            same = [row for row in hits if row["country"] and row["country"].upper() == country.upper()]
            if same:
                flag = "duplicate"
                match_id = same[0]["id"]
                match_name = same[0]["name"]
                action = "skip"
        elif hits:
            flag = "possible_duplicate"
            match_id = hits[0]["id"]
            match_name = hits[0]["name"]
            action = "skip"
        if owner_email and not owner_id and flag == "new":
            flag = "unmatched_owner"
    return PreviewRow(
        index=index,
        company_name=name or "",
        legal_name=_cell(raw, "Legal Name"),
        country=country.upper() if country else None,
        city=_cell(raw, "City"),
        address=_cell(raw, "Address"),
        website=_cell(raw, "Website"),
        telephone=_cell(raw, "Telephone"),
        nature_of_business=_cell(raw, "Nature of Business"),
        company_status=status if status in STATUSES else "Prospect",
        owner_email=owner_email,
        owner_user_id=owner_id,
        contact_first_name=_cell(raw, "Contact First Name"),
        contact_last_name=_cell(raw, "Contact Last Name"),
        contact_title=_cell(raw, "Contact Title"),
        contact_telephone=_cell(raw, "Contact Telephone"),
        contact_mobile=_cell(raw, "Contact Mobile"),
        contact_email=contact_email,
        linkedin_url=_cell(raw, "LinkedIn URL"),
        flag=flag,
        match_company_id=match_id,
        match_company_name=match_name,
        error=error,
        action=action,
    )


def _import_batch(
    claims: Claims,
    user_id: str,
    entity_id: str,
    batch: list[PreviewRow],
    owner_fallback: str,
) -> int:
    count = 0
    with runtime_connection() as connection, connection.cursor() as cur:
        bind_request(cur, claims, entity_id)
        try:
            for row in batch:
                company_id = row.match_company_id if row.action == "attach" else None
                if row.action == "create":
                    owner = row.owner_user_id
                    if not owner and owner_fallback == "self":
                        owner = user_id
                    cur.execute(
                        """
                        insert into public.company (
                          entity_id, company_name, legal_name, country, city, address,
                          website, telephone, nature_of_business, status, record_state,
                          owner_user_id, created_by_user_id, updated_by_user_id
                        )
                        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'Active', %s, %s, %s)
                        returning id
                        """,
                        (
                            entity_id,
                            row.company_name.strip(),
                            row.legal_name,
                            row.country,
                            row.city,
                            row.address,
                            row.website,
                            row.telephone,
                            row.nature_of_business,
                            row.company_status,
                            owner,
                            user_id,
                            user_id,
                        ),
                    )
                    company_id = str(cur.fetchone()[0])
                if company_id and row.contact_first_name and row.contact_last_name:
                    if row.contact_email:
                        cur.execute(
                            """
                            select id from public.contact
                            where entity_id = %s and company_id = %s and lower(email) = lower(%s)
                              and record_state = 'Active'
                            """,
                            (entity_id, company_id, row.contact_email),
                        )
                        if cur.fetchone():
                            count += 1
                            continue
                    cur.execute(
                        """
                        insert into public.contact (
                          entity_id, company_id, first_name, last_name, job_title, email,
                          telephone, mobile, linkedin_url, record_state,
                          created_by_user_id, updated_by_user_id
                        )
                        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'Active', %s, %s)
                        """,
                        (
                            entity_id,
                            company_id,
                            row.contact_first_name,
                            row.contact_last_name,
                            row.contact_title,
                            row.contact_email,
                            row.contact_telephone,
                            row.contact_mobile,
                            row.linkedin_url,
                            user_id,
                            user_id,
                        ),
                    )
                count += 1
            connection.commit()
        except Exception:
            connection.rollback()
            raise
    return count
