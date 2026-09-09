from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "local"
    app_version: str = "0.0.0-phase2"
    cors_origins: str = "http://localhost:5173"
    database_url: str = ""
    supabase_jwt_secret: str = ""
    supabase_url: str = ""
    terms_version: str = "2026-09-09"
    privacy_version: str = "2026-09-09"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
