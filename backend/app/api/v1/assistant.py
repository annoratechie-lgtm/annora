"""Ask Annora endpoints: saved chat, confirm-before-change proposals, memory.

The user is always taken from the bearer token; no endpoint accepts a user id.
"""

from datetime import date

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.core.auth import require_authenticated_user
from app.core.config import settings
from app.schemas.assistant import (
    AssistantChatRequest,
    AssistantChatResponse,
    ApplyResponse,
    MemoryCreate,
    MemoryUpdate,
)
from app.services import assistant_store, plan_ops
from app.services import supabase_rest as db
from app.services.assistant_context import AssistantContextError, load_user_context
from app.services.assistant_service import AssistantProviderError, generate_reply
from app.services.grocery_list_service import GroceryListError

router = APIRouter(prefix="/assistant", tags=["assistant"])


def _require_supabase() -> None:
    if not db.configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )


def _client() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=20)


@router.post("/chat", response_model=AssistantChatResponse)
async def chat(request: AssistantChatRequest, user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    if not settings.grokapi or not settings.llm_model:
        raise HTTPException(status_code=503, detail="Annora Assist is not configured.")

    try:
        async with _client() as client:
            await assistant_store.purge_expired(client)
            history = await assistant_store.list_messages(client, user_id, assistant_store.HISTORY_FOR_MODEL)
            try:
                context = await load_user_context(client, user_id)
            except AssistantContextError as exc:
                raise HTTPException(status_code=502, detail="Could not load your Annora data.") from exc

            meal_id = context.plan["id"] if context.plan else None
            user_message = await assistant_store.add_message(client, user_id, "user", request.message, meal_id=meal_id)
            try:
                text, action, remembered = await generate_reply(client, request.message, context, history)
            except AssistantProviderError as exc:
                raise HTTPException(status_code=502, detail=str(exc)) from exc
            if action:
                # Only the newest suggestion can be applied.
                await assistant_store.expire_open_proposals(client, user_id)
            reply = await assistant_store.add_message(client, user_id, "assistant", text, action=action, meal_id=meal_id)
    except db.SupabaseError as exc:
        raise HTTPException(status_code=502, detail="Could not save the chat.") from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc

    return {"user_message": user_message, "reply": reply, "remembered": remembered}


@router.get("/messages")
async def list_messages(limit: int = 100, user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with _client() as client:
            await assistant_store.purge_expired(client)
            messages = await assistant_store.list_messages(client, user_id, max(1, min(limit, 200)))
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not load the chat.") from exc
    return {"messages": messages, "retention_days": assistant_store.RETENTION_DAYS}


@router.delete("/messages", status_code=204)
async def clear_messages(user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with _client() as client:
            await assistant_store.clear_chat(client, user_id)
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not clear the chat.") from exc
    return Response(status_code=204)


async def _open_proposal(client: httpx.AsyncClient, user_id: str, message_id: str) -> dict:
    message = await assistant_store.get_message(client, user_id, message_id)
    if message is None or message.get("role") != "assistant" or not message.get("action"):
        raise HTTPException(status_code=404, detail="Suggestion not found.")
    if message.get("action_status") != "proposed":
        raise HTTPException(status_code=409, detail=f"This suggestion was already {message.get('action_status')}.")
    return message


def _swap_confirmation(changes: list[dict]) -> str:
    lines = [
        f"- {date.fromisoformat(c['date']).strftime('%A')} {c['meal_type']}: {c['to']['name']} (was {c['from']['name']})"
        for c in changes
    ]
    return "Done! Your plan is updated:\n" + "\n".join(lines)


@router.post("/messages/{message_id}/apply", response_model=ApplyResponse)
async def apply_proposal(message_id: str, user_id: str = Depends(require_authenticated_user)):
    """Apply the change Annora proposed in this reply (the user tapped Apply)."""
    _require_supabase()
    # Imported here: meal_plans imports the planner/LLM stack.
    from app.api.v1.meal_plans import create_meal_plan

    try:
        async with _client() as client:
            message = await _open_proposal(client, user_id, message_id)
            action = message["action"]
            try:
                if action.get("type") == "swap":
                    result = await plan_ops.apply_swaps(
                        client,
                        user_id,
                        [
                            {"meal_plan_id": c["meal_plan_id"], "from_code": c["from"]["code"], "to_code": c["to"]["code"]}
                            for c in action.get("changes") or []
                        ],
                        source="annora_chat",
                        message_id=message_id,
                    )
                    meal_id = result["meal_id"]
                    confirmation = _swap_confirmation(result["changes"])
                    if result["grocery_list_rebuilt"]:
                        confirmation += "\n\nYour grocery list is updated too (ticked items kept)."
                elif action.get("type") == "new_week":
                    start = max(date.fromisoformat(action.get("start_date") or date.today().isoformat()), date.today())
                    notes = [action["notes"]] if action.get("notes") else []
                    meal_id, _ = await create_meal_plan(user_id, start, "annora_chat", notes, message_id)
                    await plan_ops.refresh_meal_ingredients(client, meal_id)
                    try:
                        await plan_ops.rebuild_grocery_list(client, user_id, meal_id)
                    except GroceryListError:
                        pass
                    confirmation = f"Done! Your new plan starts {start.strftime('%A %d %b')}, and your grocery list is ready."
                else:
                    raise HTTPException(status_code=422, detail="Unknown suggestion type.")
            except plan_ops.PlanChangeError as exc:
                await assistant_store.set_action_status(client, user_id, message_id, "expired")
                raise HTTPException(status_code=409, detail=f"{exc} Ask Annora again for a fresh suggestion.") from exc

            await assistant_store.expire_open_proposals(client, user_id)
            await assistant_store.set_action_status(client, user_id, message_id, "applied")
            reply = await assistant_store.add_message(client, user_id, "assistant", confirmation, meal_id=meal_id)
            updated = await assistant_store.get_message(client, user_id, message_id)
    except db.SupabaseError as exc:
        raise HTTPException(status_code=502, detail="Could not update your plan. Please try again.") from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase.") from exc

    return {"message": updated, "confirmation": reply, "meal_id": meal_id}


@router.post("/messages/{message_id}/dismiss")
async def dismiss_proposal(message_id: str, user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with _client() as client:
            await _open_proposal(client, user_id, message_id)
            await assistant_store.set_action_status(client, user_id, message_id, "dismissed")
            updated = await assistant_store.get_message(client, user_id, message_id)
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not update the suggestion.") from exc
    return {"message": updated}


# ---- memory (shown and editable in Profile) ----------------------------------

@router.get("/memory")
async def list_memory(user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with _client() as client:
            return {"memory": await assistant_store.list_memory(client, user_id)}
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not load what Annora remembers.") from exc


@router.post("/memory", status_code=201)
async def add_memory(body: MemoryCreate, user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with _client() as client:
            saved = await assistant_store.add_memory(client, user_id, body.fact, body.kind)
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not save that.") from exc
    if saved is None:
        raise HTTPException(status_code=409, detail="Annora already remembers that, or the list is full.")
    return saved


@router.patch("/memory/{memory_id}")
async def update_memory(memory_id: str, body: MemoryUpdate, user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with _client() as client:
            updated = await assistant_store.update_memory(client, user_id, memory_id, body.fact, body.kind)
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not save that.") from exc
    if updated is None:
        raise HTTPException(status_code=404, detail="Not found.")
    return updated


@router.delete("/memory/{memory_id}", status_code=204)
async def delete_memory(memory_id: str, user_id: str = Depends(require_authenticated_user)):
    _require_supabase()
    try:
        async with _client() as client:
            await assistant_store.delete_memory(client, user_id, memory_id)
    except (db.SupabaseError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail="Could not delete that.") from exc
    return Response(status_code=204)
