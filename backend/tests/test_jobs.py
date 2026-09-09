from fastapi.testclient import TestClient

from app.main import app
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
