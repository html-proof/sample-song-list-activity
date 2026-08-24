from music_hub.config import Settings
from music_hub.main import create_app
from pydantic import ValidationError
import pytest


def test_api_v1_contract_contains_core_routes():
    app = create_app(Settings(database_url=None, redis_url=None))
    paths = app.openapi()["paths"]

    assert "/api/v1/auth/session" in paths
    assert "/api/v1/home" in paths
    assert "/api/v1/search" in paths
    assert "/api/v1/recommendations" in paths
    assert "/api/v1/history/events" in paths
    assert "/api/v1/playlists" in paths
    assert "/api/v1/onboarding/languages" in paths
    assert "/api/v1/settings" in paths
    assert "/api/v1/settings/playback" in paths
    assert "/api/v1/settings/privacy" in paths
    assert "/api/v1/preferences/languages" in paths
    assert "/api/v1/devices/{device_id}" in paths
    assert "/api/v1/account" in paths


def test_production_cors_does_not_default_to_wildcard():
    settings = Settings(database_url=None, redis_url=None)

    assert "*" not in settings.allowed_origins


def test_blank_firebase_credentials_path_is_optional():
    assert Settings(firebase_credentials_path="").firebase_credentials_path is None


def test_production_rejects_development_cursor_secret():
    with pytest.raises(ValidationError):
        Settings(app_env="production", cursor_secret="development-only-change-me")
