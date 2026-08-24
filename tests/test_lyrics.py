from unittest.mock import AsyncMock

import pytest

from music_hub.lyrics import (
    LyricsDocument,
    LyricsStatus,
    LyricsSyncType,
    ProviderLyricsCandidate,
    SongIdentity,
)
from music_hub.lyrics.matcher import LyricsMatcher
from music_hub.services.lyrics import LyricsService


def _song() -> dict:
    return {
        "provider": "gaana",
        "provider_id": "track-1",
        "seokey": "simtaangaran",
        "title": "Simtaangaran",
        "artists": "A.R. Rahman, Bamba Bakya",
        "album": "Sarkar (Tamil)",
        "duration": "285",
        "language": "Tamil",
    }


def _candidate(**updates) -> ProviderLyricsCandidate:
    values = {
        "provider": "licensed-test",
        "provider_song_id": "track-1",
        "title": "Simtaangaran",
        "primary_artist": "A.R. Rahman",
        "album": "Sarkar (Tamil)",
        "duration_ms": 285_000,
        "language": "Tamil",
        "sync_type": "line",
        "lines": [
            {"start_ms": 1000, "end_ms": 3000, "text": "முதல் வரி"},
            {"start_ms": 3000, "end_ms": 5000, "text": "இரண்டாம் வரி"},
        ],
    }
    values.update(updates)
    return ProviderLyricsCandidate.model_validate(values)


def _service(*, configured=True, candidates=None, cached=None):
    music = AsyncMock()
    music.name = "gaana"
    music.get_song.return_value = _song()
    provider = AsyncMock()
    provider.configured = configured
    provider.search.return_value = candidates or []
    cache = AsyncMock()
    cache.get.return_value = cached
    return LyricsService(music, provider, cache, LyricsMatcher()), music, provider, cache


@pytest.mark.asyncio
async def test_exact_provider_id_returns_timestamped_unicode_lyrics():
    service, _, _, cache = _service(candidates=[_candidate()])

    result = await service.get("simtaangaran")

    assert result.status == LyricsStatus.AVAILABLE
    assert result.sync_type == LyricsSyncType.LINE
    assert result.confidence == 1.0
    assert result.lines[0].text == "முதல் வரி"
    assert result.song_identity_hash
    cache.put.assert_awaited_once()


@pytest.mark.asyncio
async def test_unconfigured_provider_returns_explicit_unsupported_status():
    service, _, provider, _ = _service(configured=False)

    result = await service.get("simtaangaran")

    assert result.status == LyricsStatus.UNSUPPORTED
    provider.search.assert_not_awaited()


@pytest.mark.asyncio
async def test_invalid_timestamps_fall_back_to_plain_lyrics():
    candidate = _candidate(
        provider_song_id="track-1",
        lines=[
            {"start_ms": 5000, "end_ms": 6000, "text": "Line one"},
            {"start_ms": 4000, "end_ms": 7000, "text": "Line two"},
        ],
    )
    service, _, _, _ = _service(candidates=[candidate])

    result = await service.get("simtaangaran")

    assert result.status == LyricsStatus.PLAIN_ONLY
    assert result.plain_text == "Line one\nLine two"
    assert result.lines == []


@pytest.mark.asyncio
async def test_cached_lyrics_are_returned_without_provider_request():
    cached = LyricsDocument(
        song_id="simtaangaran",
        status=LyricsStatus.INSTRUMENTAL,
    )
    service, _, provider, _ = _service(cached=cached)

    result = await service.get("simtaangaran")

    assert result is cached
    provider.search.assert_not_awaited()


def test_matcher_rejects_live_lyrics_for_original_recording():
    identity = SongIdentity(
        song_id="song",
        provider="gaana",
        title="A Song",
        primary_artist="An Artist",
        album="An Album",
        duration_ms=200_000,
        language="English",
    )
    live = ProviderLyricsCandidate(
        provider="licensed-test",
        title="A Song (Live)",
        primary_artist="An Artist",
        album="An Album",
        duration_ms=200_000,
        language="English",
        plain_text="Not the original lyrics",
    )

    assert LyricsMatcher().best(identity, [live]) is None


def test_matcher_uses_duration_to_reject_a_different_recording():
    identity = SongIdentity(
        song_id="song",
        provider="gaana",
        title="A Song",
        primary_artist="An Artist",
        album="An Album",
        duration_ms=200_000,
        language="English",
    )
    different = ProviderLyricsCandidate(
        provider="licensed-test",
        title="A Song",
        primary_artist="An Artist",
        album="An Album",
        duration_ms=260_000,
        language="English",
        plain_text="Potentially wrong lyrics",
    )

    assert LyricsMatcher().best(identity, [different]) is None
