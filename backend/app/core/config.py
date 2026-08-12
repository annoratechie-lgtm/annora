from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Central backend configuration loaded from environment variables."""

    environment: str = "development"

    supabase_url: str = ""
    supabase_service_role_key: str = ""

    # xAI / Grok server-side configuration. Keep the API key out of source control.
    llm_api_key: str = ""
    llm_model: str = "grok-4.5"
    llm_base_url: str = "https://api.x.ai/v1"
    llm_timeout_seconds: float = 90.0

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
