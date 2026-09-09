from fastapi.testclient import TestClient

from app.main import app
from app.ratelimit import LIMITS
from app.settings import settings

client = TestClient(app)


def test_jobs_run_without_secret(monkeypatch) -> None:
    monkeypatch.setattr(settings, "job_secret", "")
    response = client.post("/v1/jobs/run")
    assert response.status_code == 503
    assert response.json()["detail"] == "JOB_SECRET is not set"


def test_jobs_run_rejects_wrong_secret(monkeypatch) -> None:
    monkeypatch.setattr(settings, "job_secret", "expected-secret")
    response = client.post("/v1/jobs/run", headers={"X-Job-Secret": "nope"})
    assert response.status_code == 401


def test_jobs_status_requires_secret(monkeypatch) -> None:
    monkeypatch.setattr(settings, "job_secret", "")
    assert client.get("/v1/jobs/status").status_code == 503
    monkeypatch.setattr(settings, "job_secret", "expected-secret")
    assert client.get("/v1/jobs/status", headers={"X-Job-Secret": "nope"}).status_code == 401


def test_privacy_requires_session() -> None:
    response = client.get("/v1/privacy/requests")
    assert response.status_code == 401
    response = client.post(
        "/v1/privacy/execute",
        json={
            "subject_type": "CONTACT",
            "subject_id": "00000000-0000-0000-0000-000000000001",
            "legal_basis": "test",
        },
    )
    assert response.status_code == 401


def test_invite_rate_limit(monkeypatch) -> None:
    from app.ratelimit import clear_hits

    monkeypatch.setitem(LIMITS, ("POST", "/v1/invitations"), (1, 3600))
    clear_hits()
    first = client.post("/v1/invitations", json={"email": "a@example.com", "role": "User"})
    second = client.post("/v1/invitations", json={"email": "b@example.com", "role": "User"})
    assert first.status_code in (400, 401)
    assert second.status_code == 429
    assert second.headers.get("retry-after")
    clear_hits()
