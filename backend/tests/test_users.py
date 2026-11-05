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


def test_get_user_profile_returns_existing_user_row(monkeypatch):
    profile = {
        "user_id": USER_ID,
        "name": "Saved Name",
        "email": "person@example.com",
        "phone": "+91 98765 43210",
        "photo_uploaded": False,
    }

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc_value, traceback):
            return False

        async def get(self, url, *, params, headers):
            assert url == "https://example.supabase.co/rest/v1/users"
            assert params == {
                "select": "user_id,name,email,phone,photo_uploaded",
                "user_id": f"eq.{USER_ID}",
                "limit": "1",
            }
            return httpx.Response(
                200,
                json=[profile],
                request=httpx.Request("GET", url),
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
        response = client.get("/api/v1/users/me/profile")
    finally:
        _clear_authenticated_user_override()

    assert response.status_code == 200
    assert response.json() == profile


def test_get_user_profile_initializes_missing_user_row(monkeypatch):
    observed = {}

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc_value, traceback):
            return False

        async def get(self, url, *, params, headers):
            return httpx.Response(
                200,
                json=[],
                request=httpx.Request("GET", url),
            )

        async def post(self, url, *, headers, json):
            observed.update(url=url, body=json)
            return httpx.Response(
                200,
                json=[
                    {
                        "user_id": USER_ID,
                        "name": "Person Example",
                        "email": "person@example.com",
                        "phone": None,
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
        response = client.get("/api/v1/users/me/profile")
    finally:
        _clear_authenticated_user_override()

    assert response.status_code == 200
    assert observed["url"] == (
        "https://example.supabase.co/rest/v1/rpc/sync_user_profile"
    )
    assert observed["body"] == {
        "p_user_id": USER_ID,
        "p_name": "Person Example",
        "p_email": "person@example.com",
        "p_phone": None,
    }


def test_user_profile_upserts_authenticated_identity(monkeypatch):
    observed = {}

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc_value, traceback):
            return False

        async def post(self, url, *, headers, json):
            observed.update(
                url=url,
                headers=headers,
                body=json,
            )
            return httpx.Response(
                200,
                json=[
                    {
                        "user_id": json["p_user_id"],
                        "name": json["p_name"],
                        "email": json["p_email"],
                        "phone": json["p_phone"],
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
    assert observed["url"] == (
        "https://example.supabase.co/rest/v1/rpc/sync_user_profile"
    )
    assert observed["body"] == {
        "p_user_id": USER_ID,
        "p_name": "Updated Name",
        "p_email": "person@example.com",
        "p_phone": "+91 98765 43210",
    }


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
