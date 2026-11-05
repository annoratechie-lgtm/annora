import httpx
from fastapi.testclient import TestClient

from app.core.auth import AuthenticatedUser, require_authenticated_user_details
from app.main import app


client = TestClient(app)
USER_ID = "cbd10f5c-c7fc-4a66-b279-3f30b12eec1a"
AUTHENTICATED_USER = AuthenticatedUser(
    id=USER_ID,
    email="person@example.com",
    user_metadata={"full_name": "Person Example"},
)


def _override_authenticated_user():
    app.dependency_overrides[require_authenticated_user_details] = (
        lambda: AUTHENTICATED_USER
    )


def _clear_authenticated_user_override():
    app.dependency_overrides.pop(require_authenticated_user_details, None)


def test_user_profile_requires_bearer_token():
    response = client.put("/api/v1/users/me/profile", json={"name": "Person"})

    assert response.status_code == 401
    assert response.json() == {"detail": "Missing bearer token."}


def test_user_profile_upserts_authenticated_identity(monkeypatch):
    observed = {}

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc_value, traceback):
            return False

        async def post(self, url, *, params, headers, json):
            observed.update(
                url=url,
                params=params,
                headers=headers,
                body=json,
            )
            return httpx.Response(
                201,
                json=[
                    {
                        **json,
                        "photo_uploaded": False,
                    }
                ],
                request=httpx.Request("POST", url),
            )

    monkeypatch.setattr("app.api.v1.users.httpx.AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(
        "app.api.v1.users.settings.supabase_url",
        "https://example.supabase.co",
    )
    monkeypatch.setattr(
        "app.api.v1.users.settings.supabase_service_role_key",
        "test-service-key",
    )
    _override_authenticated_user()
    try:
        response = client.put(
            "/api/v1/users/me/profile",
            json={"name": "  Updated Name  ", "phone": "+91 98765 43210"},
        )
    finally:
        _clear_authenticated_user_override()

    assert response.status_code == 200
    assert response.json() == {
        "user_id": USER_ID,
        "name": "Updated Name",
        "email": "person@example.com",
        "phone": "+91 98765 43210",
        "photo_uploaded": False,
    }
    assert observed["url"] == "https://example.supabase.co/rest/v1/users"
    assert observed["params"] == {"on_conflict": "user_id"}
    assert observed["body"] == {
        "user_id": USER_ID,
        "name": "Updated Name",
        "email": "person@example.com",
        "phone": "+91 98765 43210",
    }
    assert observed["headers"]["Prefer"] == (
        "resolution=merge-duplicates,return=representation"
    )


def test_user_profile_rejects_client_supplied_email(monkeypatch):
    _override_authenticated_user()
    try:
        response = client.put(
            "/api/v1/users/me/profile",
            json={"name": "Person", "email": "forged@example.com"},
        )
    finally:
        _clear_authenticated_user_override()

    assert response.status_code == 422


def test_user_profile_rejects_invalid_phone(monkeypatch):
    _override_authenticated_user()
    try:
        response = client.put(
            "/api/v1/users/me/profile",
            json={"phone": "not a phone"},
        )
    finally:
        _clear_authenticated_user_override()

    assert response.status_code == 422
