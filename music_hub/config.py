from functools import lru_cache
from pathlib import Path

from pydantic import SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_name: str = "Music Hub API"
    app_env: str = "development"
    app_debug: bool = False
    api_prefix: str = "/api/v1"

    database_url: str | None = None
    database_min_pool_size: int = 1
    database_max_pool_size: int = 10
    database_ssl: bool = True
    database_ssl_verify: bool = True

    redis_url: str | None = None
    upstash_redis_rest_url: str | None = None
    upstash_redis_rest_token: SecretStr | None = None
    cache_namespace: str = "music-hub"

    firebase_project_id: str | None = None
    firebase_credentials_path: Path | None = None
    firebase_check_revoked: bool = True

    cors_origins: str = "http://localhost:3000,http://localhost:5173"
    cursor_secret: SecretStr = SecretStr("development-only-change-me")
    rate_limit_requests: int = 120
    rate_limit_window_seconds: int = 60

    search_cache_ttl: int = 180
    artist_cache_ttl: int = 1800
    album_cache_ttl: int = 1800
    trending_cache_ttl: int = 300
    new_releases_cache_ttl: int = 600
    recommendation_cache_ttl: int = 300
    seen_songs_ttl: int = 21600

    @field_validator("firebase_credentials_path", mode="before")
    @classmethod
    def empty_credentials_path_is_none(cls, value):
        return None if value in (None, "") else value

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if bool(self.upstash_redis_rest_url) != bool(self.upstash_redis_rest_token):
            raise ValueError(
                "UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN must be set together"
            )
        if (
            self.app_env.casefold() == "production"
            and self.cursor_secret.get_secret_value() == "development-only-change-me"
        ):
            raise ValueError("CURSOR_SECRET must be changed in production")
        return self

    @property
    def allowed_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
