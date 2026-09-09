from fastapi.testclient import TestClient

from app.main import app
from app.settings import Settings

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "version" in body
    assert response.headers.get("x-request-id")
    assert response.headers.get("x-app-env")
    assert response.headers.get("x-content-type-options") == "nosniff"
    assert response.headers.get("x-frame-options") == "DENY"


def test_cors_allows_admin_when_www_is_listed() -> None:
    listed = Settings(cors_origins="https://www.stufe7.com,http://localhost:5173").cors_origin_list
    assert "https://admin.stufe7.com" in listed
    assert "https://www.stufe7.com" in listed
