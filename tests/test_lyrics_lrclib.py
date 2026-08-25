from unittest.mock import AsyncMock

import pytest

from music_hub.lyrics import (
    LyricsRequestHint,
    LyricsStatus,
    LyricsSyncType,
    ProviderLyricsCandidate,
)
from music_hub.lyrics.lrc import parse_lrc, parse_offset
from music_hub.lyrics.matcher import LyricsMatcher
from music_hub.providers.lyrics import LyricsProviderTemporaryError
from music_hub.providers.lyrics.lrclib import LrclibLyricsProvider, _candidate
from music_hub.services.lyrics import LyricsService


SYNCED = """[ar:A.R. Rahman]
[ti:Simtaangaran]
[00:12.50]First line
[00:15.00]Second line
[00:18.25]Third line
"""


def test_parse_lrc_produces_ordered_lines_with_derived_ends():
    lines = parse_lrc(SYNCED, total_ms=200_000)

    assert [line.text for line in lines] == ["First line", "Second line", "Third line"]
    assert [line.start_ms for line in lines] == [12_500, 15_000, 18_250]
    assert lines[0].end_ms == 15_000
    assert lines[1].end_ms == 18_250
    # The closing line runs to the end of the track when its length is known.
    assert lines[2].end_ms == 200_000


def test_parse_lrc_repeats_text_for_every_timestamp_on_a_line():
    lines = parse_lrc("[00:10.00][01:30.00]Chorus line", total_ms=120_000)

    assert [line.start_ms for line in lines] == [10_000, 90_000]
    assert {line.text for line in lines} == {"Chorus line"}


def test_parse_lrc_applies_the_offset_tag_once():
    lines = parse_lrc("[offset:-500]\n[00:10.00]Shifted", total_ms=60_000)

    assert parse_offset("[offset:-500]\n[00:10.00]Shifted") == -500
    assert lines[0].start_ms == 9_500


def test_parse_lrc_drops_timestamps_with_no_text():
    lines = parse_lrc("[00:05.00]\n[00:09.00]Real line", total_ms=60_000)

    assert [line.text for line in lines] == ["Real line"]


def test_parse_lrc_strips_enhanced_word_timings_from_the_text():
    lines = parse_lrc("[00:10.00]<00:10.00>Hello <00:10.60>world", total_ms=60_000)

    assert lines[0].text == "Hello world"


def test_plain_text_never_becomes_timestamped_lines():
    assert parse_lrc("Just a line\nAnd another") == []


def test_lrclib_payload_without_synced_lyrics_stays_plain():
    candidate = _candidate(
        {
            "id": 41,
            "trackName": "A Song",
            "artistName": "An Artist",
            "albumName": "An Album",
            "duration": 201.0,
            "plainLyrics": "Line one\nLine two",
            "syncedLyrics": None,
        }
    )

    assert candidate is not None
    assert candidate.sync_type == LyricsSyncType.PLAIN
    assert candidate.lines == []
    assert candidate.duration_ms == 201_000


def test_lrclib_payload_with_synced_lyrics_becomes_line_synced():
    candidate = _candidate(
        {
            "id": 42,
            "trackName": "A Song",
            "artistName": "An Artist",
            "duration": 200.0,
            "syncedLyrics": SYNCED,
        }
    )

    assert candidate is not None
    assert candidate.sync_type == LyricsSyncType.LINE
    assert len(candidate.lines) == 3
    # The offset is already folded into the line times.
    assert candidate.offset_ms == 0


def _service(providers, *, song=None, cached=None):
    music = AsyncMock()
    music.name = "gaana"
    music.get_song.return_value = song or {}
    cache = AsyncMock()
    cache.get.return_value = cached
    return LyricsService(music, providers, cache, LyricsMatcher()), music, cache


def _provider(name, candidates=None, *, verifiable=True, error=False):
    provider = AsyncMock()
    provider.name = name
    provider.configured = True
    provider.verifiable = verifiable
    if error:
        provider.search.side_effect = LyricsProviderTemporaryError("down")
    else:
        provider.search.return_value = candidates or []
    return provider


def _synced_candidate(provider="lrclib"):
    return ProviderLyricsCandidate(
        provider=provider,
        title="A Song",
        primary_artist="An Artist",
        album="An Album",
        duration_ms=200_000,
        sync_type=LyricsSyncType.LINE,
        lines=parse_lrc(SYNCED, total_ms=200_000),
    )


@pytest.mark.asyncio
async def test_a_complete_hint_skips_the_catalogue_lookup():
    provider = _provider("lrclib", [_synced_candidate()])
    service, music, _ = _service([provider])

    result = await service.get(
        "song-1",
        LyricsRequestHint(
            title="A Song",
            artist="An Artist",
            album="An Album",
            duration_seconds=200,
        ),
    )

    music.get_song.assert_not_awaited()
    assert result.status == LyricsStatus.AVAILABLE
    assert result.sync_type == LyricsSyncType.LINE


@pytest.mark.asyncio
async def test_an_incomplete_hint_falls_back_to_the_catalogue():
    provider = _provider("lrclib", [_synced_candidate()])
    service, music, _ = _service(
        [provider],
        song={
            "title": "A Song",
            "artists": "An Artist",
            "album": "An Album",
            "duration": "200",
        },
    )

    result = await service.get("song-1", LyricsRequestHint(title="A Song"))

    music.get_song.assert_awaited_once()
    assert result.status == LyricsStatus.AVAILABLE


@pytest.mark.asyncio
async def test_a_temporary_provider_failure_does_not_hide_the_next_provider():
    failing = _provider("lrclib", error=True)
    working = _provider("licensed", [_synced_candidate("licensed")])
    service, _, _ = _service([failing, working])

    result = await service.get(
        "song-1",
        LyricsRequestHint(title="A Song", artist="An Artist", duration_seconds=200),
    )

    assert result.status == LyricsStatus.AVAILABLE
    assert result.provider == "licensed"


@pytest.mark.asyncio
async def test_a_temporary_failure_with_no_other_result_is_not_cached_as_missing():
    service, _, cache = _service([_provider("lrclib", error=True)])

    result = await service.get(
        "song-1",
        LyricsRequestHint(title="A Song", artist="An Artist"),
    )

    assert result.status == LyricsStatus.TEMPORARY_ERROR
    cache.put.assert_awaited_once()


@pytest.mark.asyncio
async def test_an_unverifiable_provider_can_only_produce_plain_lyrics():
    # lyrics.ovh echoes the request back and may carry timings from nowhere;
    # neither may be presented as a synchronised match.
    fallback = _provider(
        "lyrics_ovh",
        [
            ProviderLyricsCandidate(
                provider="lyrics_ovh",
                title="A Song",
                primary_artist="An Artist",
                sync_type=LyricsSyncType.LINE,
                lines=parse_lrc(SYNCED, total_ms=200_000),
                plain_text="Line one\nLine two",
            )
        ],
        verifiable=False,
    )
    service, _, _ = _service([fallback])

    result = await service.get(
        "song-1",
        LyricsRequestHint(title="A Song", artist="An Artist", duration_seconds=200),
    )

    assert result.status == LyricsStatus.PLAIN_ONLY
    assert result.sync_type == LyricsSyncType.PLAIN
    assert result.lines == []
    assert result.confidence is None


@pytest.mark.asyncio
async def test_a_verified_synced_match_is_preferred_over_the_plain_fallback():
    lrclib = _provider("lrclib", [_synced_candidate()])
    fallback = _provider(
        "lyrics_ovh",
        [
            ProviderLyricsCandidate(
                provider="lyrics_ovh",
                title="A Song",
                primary_artist="An Artist",
                plain_text="Some other words",
            )
        ],
        verifiable=False,
    )
    service, _, _ = _service([lrclib, fallback])

    result = await service.get(
        "song-1",
        LyricsRequestHint(title="A Song", artist="An Artist", duration_seconds=200),
    )

    assert result.provider == "lrclib"
    assert result.status == LyricsStatus.AVAILABLE
    fallback.search.assert_not_awaited()


@pytest.mark.asyncio
async def test_a_cache_hit_skips_the_catalogue_and_every_provider():
    from music_hub.lyrics import LyricsDocument

    cached = LyricsDocument(song_id="song-1", status=LyricsStatus.PLAIN_ONLY)
    provider = _provider("lrclib", [_synced_candidate()])
    service, music, _ = _service([provider], cached=cached)

    result = await service.get(
        "song-1",
        LyricsRequestHint(title="A Song", artist="An Artist", duration_seconds=200),
    )

    assert result is cached
    music.get_song.assert_not_awaited()
    provider.search.assert_not_awaited()


class _Response:
    def __init__(self, status, payload=None, headers=None):
        self.status = status
        self._payload = payload
        self.headers = headers or {}

    async def json(self, content_type=None):
        return self._payload

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False


class _Session:
    def __init__(self, responses):
        self._responses = list(responses)
        self.requests = []
        self.closed = False

    def get(self, url, params=None):
        self.requests.append((url, params or {}))
        return self._responses.pop(0)

    async def close(self):
        self.closed = True


@pytest.mark.asyncio
async def test_exact_lookup_sends_duration_and_skips_search_when_it_hits():
    from music_hub.lyrics import SongIdentity

    provider = LrclibLyricsProvider()
    provider._session = _Session(
        [
            _Response(
                200,
                {
                    "id": 7,
                    "trackName": "A Song",
                    "artistName": "An Artist",
                    "duration": 200.0,
                    "syncedLyrics": SYNCED,
                },
            )
        ]
    )

    candidates = await provider.search(
        SongIdentity(
            song_id="song-1",
            provider="gaana",
            title="A Song",
            primary_artist="An Artist",
            album="An Album",
            duration_ms=200_400,
        )
    )

    url, params = provider._session.requests[0]
    assert url.endswith("/get")
    assert params["duration"] == "200"
    assert params["album_name"] == "An Album"
    assert len(candidates) == 1
    assert len(provider._session.requests) == 1


@pytest.mark.asyncio
async def test_exact_miss_falls_back_to_search():
    from music_hub.lyrics import SongIdentity

    provider = LrclibLyricsProvider()
    provider._session = _Session(
        [
            _Response(404),
            _Response(
                200,
                [
                    {
                        "id": 8,
                        "trackName": "A Song",
                        "artistName": "An Artist",
                        "duration": 200.0,
                        "plainLyrics": "Words",
                    }
                ],
            ),
        ]
    )

    candidates = await provider.search(
        SongIdentity(
            song_id="song-1",
            provider="gaana",
            title="A Song",
            primary_artist="An Artist",
            duration_ms=200_000,
        )
    )

    assert [request[0].rsplit("/", 1)[-1] for request in provider._session.requests] == [
        "get",
        "search",
    ]
    assert len(candidates) == 1


@pytest.mark.asyncio
async def test_rate_limited_lrclib_raises_a_temporary_error():
    from music_hub.lyrics import SongIdentity

    provider = LrclibLyricsProvider()
    provider._session = _Session([_Response(429, headers={"Retry-After": "0"})])

    with pytest.raises(LyricsProviderTemporaryError):
        await provider.search(
            SongIdentity(
                song_id="song-1",
                provider="gaana",
                title="A Song",
                primary_artist="An Artist",
            )
        )
