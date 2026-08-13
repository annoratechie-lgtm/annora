from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Central backend configuration loaded from environment variables."""

    environment: str = "development"

    supabase_url: str = ""
    supabase_service_role_key: str = ""
    dev_user_id: str = ""

    # Groq server-side configuration. Keep the API key out of source control.
    grokapi: str = ""
    llm_model: str = "llama-3.1-8b-instant"
    llm_temperature: float = 0.2
    llm_timeout_seconds: float = 90.0

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
