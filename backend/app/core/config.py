from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Central backend configuration loaded from environment variables."""

    environment: str = "development"

    supabase_url: str = ""
    supabase_service_role_key: str = ""

    # Server-side LLM configuration. Keep the key out of source control.
    # The default API shape is OpenAI-compatible so the provider can be swapped
    # without changing the meal-planning contract.
    llm_api_key: str = ""
    llm_model: str = ""
    llm_base_url: str = "https://api.openai.com/v1"
    llm_timeout_seconds: float = 60.0

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
