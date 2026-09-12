from uuid import uuid4

from app.company_sheet import classify_row, read_rows, workbook_bytes


def test_roundtrip_and_upsert_actions() -> None:
    company_id = str(uuid4())
    payload = workbook_bytes(
        [
            {
                "Company ID": company_id,
                "Company Name": "Acme Logistics",
                "Parent Company": "Acme Group",
                "Country": "SG",
                "Company Status": "Customer",
                "Owner Email": "marc@mmlogistix.com",
            },
            {
                "Company Name": "New Harbour",
                "Country": "SG",
                "Company Status": "Prospect",
            },
        ]
    )
    rows = read_rows(payload)
    assert len(rows) == 2
    existing = {"id": company_id, "name": "Acme Logistics", "country": "SG"}
    members = {"marc@mmlogistix.com": "user-1"}
    update = classify_row(rows[0], {company_id: existing}, {}, members)
    create = classify_row(rows[1], {}, {}, members)
    assert update["action"] == "update"
    assert update["company_id"] == company_id
    assert create["action"] == "create"
    assert create["company_name"] == "New Harbour"
