from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from music_hub.config import Settings
from music_hub.dependencies import get_container, require_user
from music_hub.lyrics.models import LyricsDocument, LyricsStatus, SyncType
from music_hub.lyrics.models import LyricLine
from music_hub.main import create_app


def make_client(document: LyricsDocument):
    app = create_app(Settings(database_url=None, redis_url=None))
    container = AsyncMock()
    container.lyrics.for_song.return_value = document

    app.dependency_overrides[get_container] = lambda: container
    app.dependency_overrides[require_user] = lambda: {"uid": "test-user"}
    return TestClient(app), container


def test_available_lyrics_are_returned_with_timestamps():
    document = LyricsDocument(
        song_id="test-song",
        status=LyricsStatus.AVAILABLE,
        sync_type=SyncType.LINE,
        language="ml",
        confidence=0.97,
        lines=[
            LyricLine(start_ms=12120, end_ms=16400, text="ആദ്യ വരി"),
            LyricLine(start_ms=16400, end_ms=20000, text="രണ്ടാം വരി"),
        ],
    )
    client, container = make_client(document)

    response = client.get("/api/v1/songs/test-song/lyrics")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "available"
    assert payload["sync_type"] == "line"
    assert payload["language"] == "ml"
    # Indian scripts must survive the round trip intact.
    assert payload["lines"][0]["text"] == "ആദ്യ വരി"
    assert payload["lines"][0]["start_ms"] == 12120
    container.lyrics.for_song.assert_awaited_once_with("test-song")


def test_missing_lyrics_return_200_with_an_explaining_status():
    client, _ = make_client(
        LyricsDocument.unavailable("test-song", LyricsStatus.NOT_FOUND)
    )

    response = client.get("/api/v1/songs/test-song/lyrics")

    # Never a 404: a lyrics miss must not read as a playback failure.
    assert response.status_code == 200
    assert response.json()["status"] == "not_found"


def test_instrumental_status_is_surfaced_distinctly():
    client, _ = make_client(
        LyricsDocument.unavailable("test-song", LyricsStatus.INSTRUMENTAL)
    )

    payload = client.get("/api/v1/songs/test-song/lyrics").json()

    assert payload["status"] == "instrumental"
    assert payload["lines"] == []


def test_temporary_error_is_not_cached_by_the_client():
    client, _ = make_client(
        LyricsDocument.unavailable("test-song", LyricsStatus.TEMPORARY_ERROR)
    )

    response = client.get("/api/v1/songs/test-song/lyrics")

    assert response.json()["status"] == "temporary_error"
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["retry-after"] == "30"


def test_successful_lyrics_are_cacheable():
    client, _ = make_client(
        LyricsDocument(song_id="test-song", status=LyricsStatus.AVAILABLE)
    )

    response = client.get("/api/v1/songs/test-song/lyrics")

    assert "max-age=604800" in response.headers["cache-control"]


@pytest.mark.parametrize("seokey", ["Bad_Key", "with space", "UPPER"])
def test_malformed_song_keys_are_rejected(seokey):
    client, _ = make_client(
        LyricsDocument(song_id="x", status=LyricsStatus.AVAILABLE)
    )

    response = client.get(f"/api/v1/songs/{seokey}/lyrics")

    assert response.status_code == 422
