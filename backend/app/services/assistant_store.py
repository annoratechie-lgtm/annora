"""Saved Ask Annora chat (one continuous thread per user) and long-term memory."""

import logging
from datetime import datetime, timezone

import httpx

from app.services import supabase_rest as db

logger = logging.getLogger(__name__)

RETENTION_DAYS = 90
HISTORY_FOR_MODEL = 20
MEMORY_KINDS = {"dislike", "like", "preference", "routine", "health", "other"}
MAX_MEMORY_FACTS = 50

_MESSAGE_FIELDS = "id,role,content,action,action_status,meal_id,created_at"
_MEMORY_FIELDS = "id,fact,kind,created_at,updated_at"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


async def purge_expired(client: httpx.AsyncClient) -> None:
    """Delete chat older than 90 days (all users). Never blocks a chat on failure."""
    try:
        await db.rpc(client, "purge_old_assistant_messages", {"p_days": RETENTION_DAYS})
    except (db.SupabaseError, httpx.HTTPError) as exc:
        logger.warning("Chat retention purge failed: %s", exc)


async def list_messages(client: httpx.AsyncClient, user_id: str, limit: int = 100) -> list[dict]:
    """Newest `limit` messages, returned oldest first."""
    rows = await db.select(client, "assistant_messages", {
        "select": _MESSAGE_FIELDS,
        "user_id": f"eq.{user_id}",
        "order": "created_at.desc",
        "limit": str(limit),
    })
    return list(reversed(rows))


async def get_message(client: httpx.AsyncClient, user_id: str, message_id: str) -> dict | None:
    rows = await db.select(client, "assistant_messages", {
        "select": _MESSAGE_FIELDS,
        "id": f"eq.{message_id}",
        "user_id": f"eq.{user_id}",
        "limit": "1",
    })
    return rows[0] if rows else None


async def add_message(
    client: httpx.AsyncClient,
    user_id: str,
    role: str,
    content: str,
    action: dict | None = None,
    meal_id: str | None = None,
) -> dict:
    row = {
        "user_id": user_id,
        "role": role,
        "content": content[:8000],
        "action": action,
        "action_status": "proposed" if action else None,
        "meal_id": meal_id,
    }
    saved = await db.insert(client, "assistant_messages", row)
    return {k: saved[0].get(k) for k in _MESSAGE_FIELDS.split(",")} if saved else row


async def set_action_status(client: httpx.AsyncClient, user_id: str, message_id: str, status: str) -> None:
    await db.update(
        client,
        "assistant_messages",
        {"id": f"eq.{message_id}", "user_id": f"eq.{user_id}"},
        {"action_status": status},
    )


async def expire_open_proposals(client: httpx.AsyncClient, user_id: str) -> None:
    """Older proposals are stale once the plan changes."""
    await db.update(
        client,
        "assistant_messages",
        {"user_id": f"eq.{user_id}", "action_status": "eq.proposed"},
        {"action_status": "expired"},
    )


async def clear_chat(client: httpx.AsyncClient, user_id: str) -> None:
    await db.delete(client, "assistant_messages", {"user_id": f"eq.{user_id}"})


# ---- memory -----------------------------------------------------------------

def clean_fact(fact: str) -> str:
    return " ".join(str(fact or "").split()).strip().rstrip(".")[:200]


async def list_memory(client: httpx.AsyncClient, user_id: str) -> list[dict]:
    return await db.select(client, "assistant_memory", {
        "select": _MEMORY_FIELDS,
        "user_id": f"eq.{user_id}",
        "order": "created_at.asc",
        "limit": str(MAX_MEMORY_FACTS),
    })


async def add_memory(
    client: httpx.AsyncClient,
    user_id: str,
    fact: str,
    kind: str = "preference",
    source_message_id: str | None = None,
) -> dict | None:
    """Save a fact; returns None when it's empty, a duplicate, or memory is full."""
    fact = clean_fact(fact)
    kind = kind if kind in MEMORY_KINDS else "other"
    if len(fact) < 2:
        return None
    existing = await list_memory(client, user_id)
    if any(m["fact"].casefold() == fact.casefold() for m in existing) or len(existing) >= MAX_MEMORY_FACTS:
        return None
    try:
        saved = await db.insert(client, "assistant_memory", {
            "user_id": user_id, "fact": fact, "kind": kind, "source_message_id": source_message_id,
        })
    except db.SupabaseError:
        return None  # unique index race: already remembered
    return saved[0] if saved else None


async def update_memory(client: httpx.AsyncClient, user_id: str, memory_id: str, fact: str, kind: str | None) -> dict | None:
    data = {"fact": clean_fact(fact), "updated_at": _now()}
    if kind in MEMORY_KINDS:
        data["kind"] = kind
    rows = await db.update(client, "assistant_memory", {"id": f"eq.{memory_id}", "user_id": f"eq.{user_id}"}, data)
    return rows[0] if rows else None


async def delete_memory(client: httpx.AsyncClient, user_id: str, memory_id: str) -> None:
    await db.delete(client, "assistant_memory", {"id": f"eq.{memory_id}", "user_id": f"eq.{user_id}"})


async def memory_facts(client: httpx.AsyncClient, user_id: str) -> list[str]:
    """Plain facts for prompts (chat and the meal planner). Failures return []."""
    try:
        return [m["fact"] for m in await list_memory(client, user_id)]
    except (db.SupabaseError, httpx.HTTPError):
        return []
