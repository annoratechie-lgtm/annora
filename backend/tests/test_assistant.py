"""Ask Annora: saved chat, confirm-before-change proposals, memory, isolation."""

import asyncio

import pytest
from fastapi.testclient import TestClient

from app.api.v1 import assistant as assistant_api
from app.core.auth import require_authenticated_user
from app.main import app
from app.services import assistant_service, plan_ops
from app.services.assistant_context import UserContext
from app.services.assistant_service import ToolRunner, history_messages, system_prompt

USER_ID = "cbd10f5c-c7fc-4a66-b279-3f30b12eec1a"
client = TestClient(app)


def make_context():
    slots = {
        "M1": {"id": "row-1", "meal_date": "2026-11-19", "meal_type": "dinner", "source_recipe_code": "ASC226", "name": "Aloo gobhi"},
        "M2": {"id": "row-2", "meal_date": "2026-11-19", "meal_type": "dinner", "source_recipe_code": "ASC113", "name": "Chapati"},
    }
    data = {
        "household": {"people": 2, "diet": "vegetarian", "foods_to_avoid": ["mushroom"]},
        "remembered_about_user": ["Doesn't like bhindi"],
        "active_meal_plan": {"meals": [{"ref": "M1", "dish": "Aloo gobhi"}, {"ref": "M2", "dish": "Chapati"}]},
    }
    return UserContext(user_id=USER_ID, data=data, plan={"id": "plan-1"}, slots=slots)


class FakeStore:
    """In-memory stand-in for assistant_store."""

    def __init__(self):
        self.messages = []
        self.expired = 0

    async def purge_expired(self, client):
        pass

    async def list_messages(self, client, user_id, limit=100):
        return [m for m in self.messages if m["user_id"] == user_id][-limit:]

    async def add_message(self, client, user_id, role, content, action=None, meal_id=None):
        m = {"id": f"msg-{len(self.messages) + 1}", "user_id": user_id, "role": role, "content": content,
             "action": action, "action_status": "proposed" if action else None, "meal_id": meal_id}
        self.messages.append(m)
        return {k: v for k, v in m.items() if k != "user_id"}

    async def get_message(self, client, user_id, message_id):
        m = next((m for m in self.messages if m["id"] == message_id and m["user_id"] == user_id), None)
        return {k: v for k, v in m.items() if k != "user_id"} if m else None

    async def set_action_status(self, client, user_id, message_id, status):
        for m in self.messages:
            if m["id"] == message_id and m["user_id"] == user_id:
                m["action_status"] = status

    async def expire_open_proposals(self, client, user_id):
        self.expired += 1
        for m in self.messages:
            if m["user_id"] == user_id and m["action_status"] == "proposed":
                m["action_status"] = "expired"


@pytest.fixture
def store(monkeypatch):
    fake = FakeStore()
    for name in ("purge_expired", "list_messages", "add_message", "get_message", "set_action_status", "expire_open_proposals"):
        monkeypatch.setattr(assistant_api.assistant_store, name, getattr(fake, name))
    monkeypatch.setattr(assistant_api.db, "configured", lambda: True)
    monkeypatch.setattr(assistant_api.settings, "grokapi", "test-key")
    monkeypatch.setattr(assistant_api.settings, "llm_model", "test-model")
    app.dependency_overrides[require_authenticated_user] = lambda: USER_ID
    yield fake
    app.dependency_overrides.pop(require_authenticated_user, None)


SWAP_ACTION = {
    "type": "swap",
    "summary": "Thursday dinner: Palak paneer instead of Aloo gobhi",
    "changes": [{"meal_plan_id": "row-1", "date": "2026-11-19", "meal_type": "dinner",
                 "from": {"code": "ASC226", "name": "Aloo gobhi"}, "to": {"code": "ASC300", "name": "Palak paneer"}}],
}


def test_chat_requires_a_bearer_token():
    r = client.post("/api/v1/assistant/chat", json={"message": "What's for dinner?"})
    assert r.status_code == 401


def test_chat_rejects_a_client_supplied_user_id(store):
    r = client.post("/api/v1/assistant/chat", json={"message": "hi", "user_id": "someone-else"})
    assert r.status_code == 422


def test_chat_saves_both_messages_and_the_proposal(store, monkeypatch):
    async def load_context(_client, user_id):
        assert user_id == USER_ID
        return make_context()

    async def reply(_client, message, context, history):
        assert message == "Swap Thursday dinner for something with more protein"
        return "Palak paneer has more protein. Tap Apply to update your plan.", SWAP_ACTION, []

    monkeypatch.setattr(assistant_api, "load_user_context", load_context)
    monkeypatch.setattr(assistant_api, "generate_reply", reply)

    r = client.post("/api/v1/assistant/chat", json={"message": "Swap Thursday dinner for something with more protein"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["user_message"]["role"] == "user"
    assert body["reply"]["action"]["type"] == "swap"
    assert body["reply"]["action_status"] == "proposed"
    assert [m["role"] for m in store.messages] == ["user", "assistant"]
    assert all(m["meal_id"] == "plan-1" for m in store.messages)


def test_history_is_returned_oldest_first(store):
    asyncio.run(store.add_message(None, USER_ID, "user", "first"))
    asyncio.run(store.add_message(None, "other-user", "user", "not mine"))
    asyncio.run(store.add_message(None, USER_ID, "assistant", "second"))
    r = client.get("/api/v1/assistant/messages")
    assert [m["content"] for m in r.json()["messages"]] == ["first", "second"]
    assert r.json()["retention_days"] == 90


def test_apply_swaps_with_source_annora_chat(store, monkeypatch):
    asyncio.run(store.add_message(None, USER_ID, "assistant", "Tap Apply", action=SWAP_ACTION))
    calls = {}

    async def apply_swaps(_client, user_id, changes, source, message_id=None):
        calls.update(user_id=user_id, changes=changes, source=source, message_id=message_id)
        return {"meal_id": "plan-1", "changes": SWAP_ACTION["changes"], "grocery_list_rebuilt": True}

    monkeypatch.setattr(assistant_api.plan_ops, "apply_swaps", apply_swaps)
    r = client.post("/api/v1/assistant/messages/msg-1/apply")
    assert r.status_code == 200, r.text
    assert calls == {"user_id": USER_ID, "source": "annora_chat", "message_id": "msg-1",
                     "changes": [{"meal_plan_id": "row-1", "from_code": "ASC226", "to_code": "ASC300"}]}
    assert r.json()["message"]["action_status"] == "applied"
    assert "Thursday dinner: Palak paneer (was Aloo gobhi)" in r.json()["confirmation"]["content"]
    assert "grocery list is updated" in r.json()["confirmation"]["content"]

    again = client.post("/api/v1/assistant/messages/msg-1/apply")
    assert again.status_code == 409  # can't apply twice


def test_stale_proposal_is_expired_not_applied(store, monkeypatch):
    asyncio.run(store.add_message(None, USER_ID, "assistant", "Tap Apply", action=SWAP_ACTION))

    async def apply_swaps(*args, **kwargs):
        raise plan_ops.PlanChangeError("Dinner on 2026-11-19 has changed since this was suggested.")

    monkeypatch.setattr(assistant_api.plan_ops, "apply_swaps", apply_swaps)
    r = client.post("/api/v1/assistant/messages/msg-1/apply")
    assert r.status_code == 409
    assert store.messages[0]["action_status"] == "expired"


def test_cannot_apply_someone_elses_proposal(store):
    asyncio.run(store.add_message(None, "other-user", "assistant", "Tap Apply", action=SWAP_ACTION))
    assert client.post("/api/v1/assistant/messages/msg-1/apply").status_code == 404
    assert client.post("/api/v1/assistant/messages/msg-1/dismiss").status_code == 404


def test_dismiss(store):
    asyncio.run(store.add_message(None, USER_ID, "assistant", "Tap Apply", action=SWAP_ACTION))
    r = client.post("/api/v1/assistant/messages/msg-1/dismiss")
    assert r.json()["message"]["action_status"] == "dismissed"


def test_memory_rejects_blank_facts(store):
    assert client.post("/api/v1/assistant/memory", json={"fact": "   "}).status_code == 422
    assert client.post("/api/v1/assistant/memory", json={"fact": "Likes poha", "kind": "nonsense"}).status_code == 422


def test_prompt_has_rules_and_data_but_no_database_ids():
    prompt = system_prompt(make_context())
    assert "Doesn't like bhindi" in prompt and "mushroom" in prompt
    assert "only PROPOSE" in prompt
    assert "row-1" not in prompt and "plan-1" not in prompt


def test_history_marks_proposal_outcomes():
    msgs = history_messages([
        {"role": "user", "content": "swap dinner"},
        {"role": "assistant", "content": "Tap Apply", "action": SWAP_ACTION, "action_status": "applied"},
    ])
    assert msgs[1]["content"].endswith("— applied]")


def test_tool_proposal_maps_refs_to_real_rows(monkeypatch):
    seen = {}

    async def validate(_client, user_id, changes):
        seen["changes"] = changes
        return {"id": "plan-1"}, SWAP_ACTION["changes"]

    monkeypatch.setattr(assistant_service.plan_ops, "validate_swaps", validate)
    runner = ToolRunner(client=None, context=make_context())
    result = asyncio.run(runner.run("propose_swaps", {"changes": [{"meal_ref": "m1", "new_recipe_code": "ASC300"}], "summary": "More protein"}))
    assert result["status"] == "proposed"
    assert seen["changes"] == [{"meal_plan_id": "row-1", "from_code": "ASC226", "to_code": "ASC300"}]
    assert runner.action["type"] == "swap" and runner.action["meal_id"] == "plan-1"

    bad = asyncio.run(runner.run("propose_swaps", {"changes": [{"meal_ref": "M9", "new_recipe_code": "ASC300"}]}))
    assert "error" in bad


def test_tool_errors_go_back_to_the_model_not_the_user(monkeypatch):
    async def validate(*args):
        raise plan_ops.PlanChangeError("That recipe isn't available for this meal.")

    monkeypatch.setattr(assistant_service.plan_ops, "validate_swaps", validate)
    runner = ToolRunner(client=None, context=make_context())
    result = asyncio.run(runner.run("propose_swaps", {"changes": [{"meal_ref": "M1", "new_recipe_code": "XXX1"}], "summary": "x"}))
    assert result == {"error": "That recipe isn't available for this meal."}
    assert runner.action is None
    assert "error" in asyncio.run(runner.run("drop_tables", {}))


def test_new_week_proposal_never_starts_in_the_past():
    runner = ToolRunner(client=None, context=make_context())
    asyncio.run(runner.run("propose_new_week", {"start_date": "2020-01-01", "notes": "more protein"}))
    from datetime import date
    assert runner.action["type"] == "new_week"
    assert date.fromisoformat(runner.action["start_date"]) >= date.today()
