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


class AssistantChatResponse(BaseModel):
    answer: str = Field(min_length=1, max_length=4000)
