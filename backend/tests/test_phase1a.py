from fastapi.testclient import TestClient

from app.main import app
from app.settings import settings

client = TestClient(app)


def test_phase1a_without_database_url(monkeypatch) -> None:
    monkeypatch.setattr(settings, "database_url", "")
    response = client.get("/v1/ops/phase1a")
    assert response.status_code == 503
    assert response.json()["detail"] == "DATABASE_URL is not set"


def test_phase1a_hidden_in_production(monkeypatch) -> None:
    monkeypatch.setattr(settings, "app_env", "production")
    response = client.get("/v1/ops/phase1a")
    assert response.status_code == 404
