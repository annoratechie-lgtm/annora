from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class AssistantChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    message: str = Field(min_length=1, max_length=2000)

    @field_validator("message")
    @classmethod
    def message_must_not_be_blank(cls, value: str) -> str:
        message = value.strip()
        if not message:
            raise ValueError("Message must not be blank.")
        return message


class ChatMessage(BaseModel):
    id: str | None = None
    role: Literal["user", "assistant"]
    content: str
    # A proposed plan change: {"type": "swap" | "new_week", "summary": ..., ...}
    action: dict[str, Any] | None = None
    action_status: Literal["proposed", "applied", "dismissed", "failed", "expired"] | None = None
    meal_id: str | None = None
    created_at: str | None = None


class AssistantChatResponse(BaseModel):
    user_message: ChatMessage
    reply: ChatMessage
    remembered: list[str] = Field(default_factory=list)


class ApplyResponse(BaseModel):
    message: ChatMessage
    confirmation: ChatMessage
    meal_id: str


MemoryKind = Literal["dislike", "like", "preference", "routine", "health", "other"]


def _clean_fact(value: str) -> str:
    fact = " ".join(value.split()).strip()
    if len(fact) < 2:
        raise ValueError("Write a few words.")
    return fact


class MemoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    fact: str = Field(min_length=2, max_length=200)
    kind: MemoryKind = "preference"

    @field_validator("fact")
    @classmethod
    def clean_fact(cls, value: str) -> str:
        return _clean_fact(value)


class MemoryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    fact: str = Field(min_length=2, max_length=200)
    kind: MemoryKind | None = None

    @field_validator("fact")
    @classmethod
    def clean_fact(cls, value: str) -> str:
        return _clean_fact(value)
