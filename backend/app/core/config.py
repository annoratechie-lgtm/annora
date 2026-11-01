from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Central backend configuration loaded from environment variables."""

    environment: str = "development"

    supabase_url: str = ""
    supabase_service_role_key: str = ""
    dev_user_id: str = ""

    # LLM-compatible provider configuration. Keep the API key server-side.
    llm_api_key: str = ""
    llm_base_url: str = "https://api.x.ai/v1"
    llm_timeout_seconds: float = 90.0
    grokapi: str = ""
    llm_model: str = "openai/gpt-oss-20b"
    llm_temperature: float = 0.2

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
