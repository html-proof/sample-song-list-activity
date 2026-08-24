import ssl
from pathlib import Path

from music_hub.database.postgres import Database


def test_database_ssl_can_be_disabled():
    database = Database(None, require_ssl=False)

    assert database._ssl_parameter() is False


def test_database_ssl_require_mode_keeps_encryption_without_verification():
    database = Database(None, require_ssl=True, verify_ssl=False)

    assert database._ssl_parameter() == "require"


def test_database_ssl_verification_is_the_default():
    database = Database(None)

    context = database._ssl_parameter()

    assert isinstance(context, ssl.SSLContext)
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED


def test_user_interest_migration_enforces_user_owned_relationships():
    migration = (
        Path(__file__).parents[1]
        / "music_hub"
        / "database"
        / "migrations"
        / "004_user_interest_integrity.sql"
    ).read_text(encoding="utf-8")

    assert "user_interest_signals" in migration
    assert "user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE" in migration
    assert "playlist_tracks_owner_fk" in migration
    assert "FOREIGN KEY (playlist_id, user_id)" in migration
    assert "listening_history_interest_learn" in migration
    assert "liked_songs_interest_sync" in migration
