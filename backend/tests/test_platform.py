from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

PLATFORM_GET = (
    "/v1/platform/stats",
    "/v1/platform/deny-health",
    "/v1/platform/change-requests",
    "/v1/platform/registrations",
    "/v1/platform/domain-requests",
)

PROBE = "00000000-0000-0000-0000-000000000001"


def test_platform_console_requires_session() -> None:
    for path in PLATFORM_GET:
        response = client.get(path)
        assert response.status_code == 401, path


def test_platform_mutations_require_session() -> None:
    assert (
        client.post(f"/v1/platform/change-requests/{PROBE}/approve").status_code == 401
    )
    assert (
        client.post(
            f"/v1/platform/change-requests/{PROBE}/reject",
            json={"requester_feedback": "no"},
        ).status_code
        == 401
    )


def test_entity_change_routes_require_session() -> None:
    assert client.post("/v1/domains/removals", json={"domain": "x.example"}).status_code == 401
    assert client.post("/v1/domains/primary", json={"domain": "x.example"}).status_code == 401
    assert (
        client.post("/v1/entity/rename", json={"entity_name": "Probe"}).status_code == 401
    )


def test_company_campaigns_require_session() -> None:
    assert client.get(f"/v1/companies/{PROBE}/campaigns").status_code == 401


def test_email_change_requires_session() -> None:
    assert (
        client.post("/v1/account/email-change/start", json={"email": "a@example.com"}).status_code
        == 401
    )
    assert client.post("/v1/account/email-change/commit").status_code == 401
