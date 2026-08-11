from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_check_returns_ok():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_root_returns_service_name():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["service"] == "annora-backend"
