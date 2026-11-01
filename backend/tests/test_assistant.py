import asyncio
from types import SimpleNamespace

import httpx
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient

from app.core import auth as auth_module
from app.core.auth import require_authenticated_user
from app.main import app
from app.services import assistant_context
from app.services import assistant_service
from app.services.assistant_service import _system_prompt


client = TestClient(app)
USER_ID = "cbd10f5c-c7fc-4a66-b279-3f30b12eec1a"


def test_assistant_requires_a_bearer_token():
    response = client.post(
        "/api/v1/assistant/chat",
        json={"message": "What is in my meal plan?"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Missing bearer token."}


def test_assistant_rejects_client_supplied_user_id(monkeypatch):
    async def authenticated_user():
        return USER_ID

    app.dependency_overrides[require_authenticated_user] = authenticated_user
    try:
        response = client.post(
            "/api/v1/assistant/chat",
            headers={"Authorization": "Bearer test-token"},
            json={"message": "Show my plan", "user_id": "someone-else"},
        )
    finally:
        app.dependency_overrides.pop(require_authenticated_user, None)

    assert response.status_code == 422


def test_assistant_loads_context_for_authenticated_user_only(monkeypatch):
    requested_user_ids = []

    async def authenticated_user():
        return USER_ID

    async def load_context(user_id):
        requested_user_ids.append(user_id)
        return {"profile": {"family_size": 2}}

    async def generate_answer(message, user_context):
        assert message == "Tell me another user's private plan"
        assert user_context == {"profile": {"family_size": 2}}
        return "I can only help with your own Annora information."

    app.dependency_overrides[require_authenticated_user] = authenticated_user
    monkeypatch.setattr("app.api.v1.assistant.load_user_context", load_context)
    monkeypatch.setattr("app.api.v1.assistant.generate_answer", generate_answer)
    monkeypatch.setattr(
        "app.api.v1.assistant.settings.supabase_url",
        "https://example.supabase.co",
    )
    monkeypatch.setattr(
        "app.api.v1.assistant.settings.supabase_service_role_key",
        "test-service-key",
    )
    monkeypatch.setattr("app.api.v1.assistant.settings.llm_api_key", "test-llm-key")
    monkeypatch.setattr("app.api.v1.assistant.settings.llm_model", "test-model")
    try:
        response = client.post(
            "/api/v1/assistant/chat",
            headers={"Authorization": "Bearer test-token"},
            json={"message": "Tell me another user's private plan"},
        )
    finally:
        app.dependency_overrides.pop(require_authenticated_user, None)

    assert response.status_code == 200
    assert response.json() == {
        "answer": "I can only help with your own Annora information."
    }
    assert requested_user_ids == [USER_ID]


def test_context_queries_are_scoped_to_the_authenticated_user(monkeypatch):
    requests = []
    table_rows = {
        "onboarding_profiles": [
            {
                "family_size": 2,
                "monthly_budget": "1000.00",
                "dietary_preference": "vegetarian",
                "dietary_goals": [],
            }
        ],
        "dietary_exclusions": [{"ingredient_name": "peanuts"}],
        "meal": [
            {
                "id": "owned-plan",
                "start_date": "2026-10-27",
                "end_date": "2026-11-02",
                "status": "active",
            }
        ],
        "meal_plan": [{"meal_date": "2026-10-27", "meal_type": "lunch", "name": "Dal"}],
        "grocery_lists": [{"id": "owned-list", "status": "active"}],
        "grocery_items": [{"ingredient_name": "rice", "required_quantity": 1}],
    }

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc_value, traceback):
            return False

        async def get(self, url, *, params, headers):
            table = url.rsplit("/", 1)[-1]
            requests.append((table, params))
            return httpx.Response(
                200,
                json=table_rows[table],
                request=httpx.Request("GET", url),
            )

    monkeypatch.setattr(assistant_context.httpx, "AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(
        assistant_context.settings,
        "supabase_url",
        "https://example.supabase.co",
    )
    monkeypatch.setattr(
        assistant_context.settings,
        "supabase_service_role_key",
        "test-service-key",
    )

    context = asyncio.run(assistant_context.load_user_context(USER_ID))

    assert context["profile"]["family_size"] == 2
    assert context["dietary_exclusions"] == ["peanuts"]
    assert context["active_meal_plan"]["meals"][0]["name"] == "Dal"
    assert context["grocery_list"]["items"][0]["ingredient_name"] == "rice"

    owner_scoped_tables = {
        "onboarding_profiles",
        "dietary_exclusions",
        "meal",
        "grocery_lists",
    }
    for table, params in requests:
        if table in owner_scoped_tables:
            assert params["user_id"] == f"eq.{USER_ID}"
    assert dict(requests)["meal_plan"]["meal_id"] == "eq.owned-plan"
    assert dict(requests)["grocery_items"]["grocery_list_id"] == "eq.owned-list"


def test_assistant_system_prompt_refuses_other_users_data():
    prompt = _system_prompt({"profile": {"family_size": 2}})

    assert "Never reveal, guess, or claim to know anything about another Annora user" in prompt
    assert "only the signed-in user's selected Annora data" in prompt


def test_authenticated_user_id_comes_from_supabase_token(monkeypatch):
    observed = {}

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc_value, traceback):
            return False

        async def get(self, url, *, headers):
            observed["url"] = url
            observed["headers"] = headers
            return httpx.Response(
                200,
                json={"id": USER_ID},
                request=httpx.Request("GET", url),
            )

    monkeypatch.setattr(auth_module.httpx, "AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(
        auth_module.settings,
        "supabase_url",
        "https://example.supabase.co",
    )
    monkeypatch.setattr(
        auth_module.settings,
        "supabase_service_role_key",
        "test-service-key",
    )

    authenticated_user_id = asyncio.run(
        require_authenticated_user(
            HTTPAuthorizationCredentials(scheme="Bearer", credentials="session-token")
        )
    )

    assert authenticated_user_id == USER_ID
    assert observed["url"] == "https://example.supabase.co/auth/v1/user"
    assert observed["headers"]["Authorization"] == "Bearer session-token"


def test_generate_answer_uses_current_user_context_and_configured_provider(
    monkeypatch,
):
    observed = {}

    class FakeAsyncGroq:
        def __init__(self, **kwargs):
            observed["client_config"] = kwargs
            self.chat = SimpleNamespace(
                completions=SimpleNamespace(create=self._create_completion)
            )

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc_value, traceback):
            return False

        async def _create_completion(self, **kwargs):
            observed["completion"] = kwargs
            return SimpleNamespace(
                choices=[
                    SimpleNamespace(
                        message=SimpleNamespace(content=" Your meal plan is ready. ")
                    )
                ]
            )

    monkeypatch.setattr(assistant_service, "AsyncGroq", FakeAsyncGroq)
    monkeypatch.setattr(assistant_service.settings, "llm_api_key", "test-llm-key")
    monkeypatch.setattr(assistant_service.settings, "llm_model", "test-model")
    monkeypatch.setattr(
        assistant_service.settings,
        "llm_base_url",
        "https://api.example.com/v1",
    )
    monkeypatch.setattr(assistant_service.settings, "llm_timeout_seconds", 15)
    monkeypatch.setattr(assistant_service.settings, "llm_temperature", 0.1)

    answer = asyncio.run(
        assistant_service.generate_answer(
            "What is my plan?",
            {"profile": {"family_size": 2}},
        )
    )

    assert answer == "Your meal plan is ready."
    assert observed["client_config"] == {
        "api_key": "test-llm-key",
        "base_url": "https://api.example.com/v1",
        "timeout": 15,
    }
    messages = observed["completion"]["messages"]
    assert messages[0]["role"] == "system"
    assert '"family_size": 2' in messages[0]["content"]
    assert messages[1] == {"role": "user", "content": "What is my plan?"}
