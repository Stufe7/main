from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "local"
    app_version: str = "0.0.0-phase8"
    cors_origins: str = "http://localhost:5173"
    database_url: str = ""
    supabase_jwt_secret: str = ""
    supabase_url: str = ""
    terms_version: str = "2026-09-09"
    privacy_version: str = "2026-09-09"
    sendgrid_api_key: str = ""
    mail_from_updates: str = "updates@stufe7.com"
    mail_reply_to_support: str = "support@stufe7.com"
    mail_from_noreply: str = "noreply@stufe7.com"
    mail_admin_to: str = "admin@stufe7.com"
    public_app_url: str = "https://www.stufe7.com"
    job_secret: str = ""
    supabase_service_role_key: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
