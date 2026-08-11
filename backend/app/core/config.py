from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Central configuration. All values come from environment variables (.env locally,
    real environment variables in any deployed environment) -- nothing is hardcoded,
    and no secret ever gets committed to source control.

    Milestone 1 doesn't use Supabase from the backend yet (onboarding writes go
    directly from Flutter), but these are wired up now so later milestones
    (meal planning, price aggregation, NLP) don't need a config refactor.
    """

    environment: str = "development"

    supabase_url: str = ""
    supabase_service_role_key: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
