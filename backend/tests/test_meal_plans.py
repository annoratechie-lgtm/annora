from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_generate_meal_plan_requires_bearer_token():
    response = client.post("/api/v1/meal-plans/generate", json={})

    assert response.status_code == 401
    assert response.json() == {"detail": "Missing Bearer access token."}


def test_generate_meal_plan_rejects_empty_bearer_token():
    response = client.post(
        "/api/v1/meal-plans/generate",
        headers={"Authorization": "Bearer "},
        json={},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid Bearer access token."}
