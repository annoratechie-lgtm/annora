from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auth import require_authenticated_user
from app.core.config import settings
from app.schemas.assistant import AssistantChatRequest, AssistantChatResponse
from app.services.assistant_context import AssistantContextError, load_user_context
from app.services.assistant_service import AssistantProviderError, generate_answer


router = APIRouter(prefix="/assistant", tags=["assistant"])


@router.post("/chat", response_model=AssistantChatResponse)
async def chat(
    request: AssistantChatRequest,
    user_id: str = Depends(require_authenticated_user),
) -> AssistantChatResponse:
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase backend configuration is missing.",
        )
    if not settings.grokapi or not settings.llm_model:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Annora Assist is not configured.",
        )

    try:
        user_context = await load_user_context(user_id)
    except AssistantContextError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not load your Annora data.",
        ) from exc

    try:
        answer = await generate_answer(request.message, user_context)
    except AssistantProviderError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    return AssistantChatResponse(answer=answer)
