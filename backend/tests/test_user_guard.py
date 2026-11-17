"""The meal-plan read/ingredient/grocery endpoints must only serve the caller's own data."""

import pytest
from fastapi.testclient import TestClient

import app.core.auth as auth
from app.core.auth import AuthenticatedUser
from app.core.config import settings
from app.main import app

ROUTES = [
    ("get", "/api/v1/meal-plans/{uid}"),
    ("get", "/api/v1/meal-plans/plan-1/ingredients?user_id={uid}"),
    ("get", "/api/v1/meal-plans/plan-1/grocery-list?user_id={uid}"),
    ("post", "/api/v1/meal-plans/plan-1/ingredients?user_id={uid}"),
    ("post", "/api/v1/meal-plans/plan-1/grocery-list?user_id={uid}"),
    ("patch", "/api/v1/meal-plans/plan-1/grocery-list/items/item-1?user_id={uid}"),
]


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(settings, "environment", "staging")
    # With Supabase "unconfigured", a request that passes the guard stops at a 503.
    monkeypatch.setattr(settings, "supabase_url", "")
    monkeypatch.setattr(settings, "supabase_service_role_key", "")

    async def fake_user(credentials):
        if credentials is None:
            from fastapi import HTTPException
            raise HTTPException(status_code=401, detail="Missing bearer token.")
        return AuthenticatedUser(id="user-a", email=None, user_metadata={})

    monkeypatch.setattr(auth, "_get_authenticated_user", fake_user)
    return TestClient(app)


def call(client, method, path, **kwargs):
    if method == "patch":
        kwargs["json"] = {"is_purchased": True}
    return getattr(client, method)(path, **kwargs)


@pytest.mark.parametrize("method,path", ROUTES)
def test_no_token_is_rejected(client, method, path):
    r = call(client, method, path.format(uid="user-a"))
    assert r.status_code == 401


@pytest.mark.parametrize("method,path", ROUTES)
def test_someone_elses_user_id_is_forbidden(client, method, path):
    r = call(client, method, path.format(uid="user-b"), headers={"Authorization": "Bearer token-a"})
    assert r.status_code == 403


@pytest.mark.parametrize("method,path", ROUTES)
def test_own_user_id_passes_the_guard(client, method, path):
    r = call(client, method, path.format(uid="user-a"), headers={"Authorization": "Bearer token-a"})
    assert r.status_code == 503  # reached the handler; Supabase is deliberately unconfigured
