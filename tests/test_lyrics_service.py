from unittest.mock import AsyncMock

import pytest

from music_hub.cache.lyrics_cache import LyricsCache
from music_hub.errors import ProviderUnavailable
from music_hub.lyrics.matcher import best_match, duration_score, score_candidate
from music_hub.lyrics.models import LyricsCandidate, LyricsStatus, SongIdentity, SyncType
from music_hub.lyrics.normalizer import detect_script, normalize_text, parse_lrc
from music_hub.lyrics.validator import validate_timeline
from music_hub.services.lyrics_service import LyricsService, _identity_from_song


SYNCED = """[ar:Test Artist]
[00:12.12]First line
[00:16.40]Second line
[00:20.00]Third line
[00:24.50]Fourth line
"""


def make_service(minimum_confidence: float = 0.62):
    provider = AsyncMock()
    provider.name = "test"
    music = AsyncMock()
    cache = AsyncMock()
    cache.get_json.return_value = None
    service = LyricsService(provider, music, LyricsCache(cache), minimum_confidence)
    return service, provider, music, cache


def identity(**overrides) -> SongIdentity:
    base = {
        "song_id": "song-1",
        "title": "Test Song",
        "artist": "Test Artist",
        "album": "Test Album",
        "duration_ms": 240_000,
    }
    return SongIdentity(**{**base, **overrides})


def candidate(**overrides) -> LyricsCandidate:
    base = {
        "title": "Test Song",
        "artist": "Test Artist",
        "album": "Test Album",
        "duration_seconds": 240.0,
        "synced_text": SYNCED,
        "provider": "test",
        "version_id": "v1",
    }
    return LyricsCandidate(**{**base, **overrides})


# --- LRC parsing -----------------------------------------------------------


def test_parse_lrc_derives_end_from_next_line_start():
    lines, offset, _ = parse_lrc(SYNCED)
    assert offset == 0
    assert [line.start_ms for line in lines] == [12120, 16400, 20000, 24500]
    # A line ends exactly where the next begins, so gaps stay real gaps.
    assert lines[0].end_ms == 16400
    assert lines[1].end_ms == 20000


def test_parse_lrc_reads_global_offset_without_shifting_timestamps():
    lines, offset, _ = parse_lrc("[offset:-250]\n" + SYNCED)
    assert offset == -250
    # Offset is reported, never baked into the stamps.
    assert lines[0].start_ms == 12120


def test_parse_lrc_handles_millisecond_fractions():
    lines, _, _ = parse_lrc("[00:01.5]A\n[00:02.25]B\n[00:03.125]C\n")
    assert [line.start_ms for line in lines] == [1500, 2250, 3125]


def test_parse_lrc_ignores_blank_and_malformed_lines():
    lines, _, _ = parse_lrc("[00:01.00]A\nnot a lyric line\n[00:02.00]\n[00:03.00]C\n")
    assert [line.text for line in lines] == ["A", "C"]


# --- timeline validation ---------------------------------------------------


def test_validator_rejects_too_few_timed_lines():
    lines, _, _ = parse_lrc("[00:01.00]Only one\n[00:02.00]Two\n")
    assert validate_timeline(lines, 240_000).valid is False


def test_validator_rejects_lyrics_starting_after_track_end():
    lines, _, _ = parse_lrc(SYNCED)
    result = validate_timeline(lines, 5_000)
    assert result.valid is False
    assert "after track end" in result.reason


def test_validator_clamps_overlapping_ends():
    from music_hub.lyrics.models import LyricLine

    overlapping = [
        LyricLine(start_ms=0, end_ms=9_000, text="A"),
        LyricLine(start_ms=5_000, end_ms=12_000, text="B"),
        LyricLine(start_ms=10_000, end_ms=14_000, text="C"),
    ]
    result = validate_timeline(overlapping, 240_000)
    assert result.valid is True
    assert result.lines[0].end_ms == 5_000
    assert result.lines[1].end_ms == 10_000


# --- matching --------------------------------------------------------------


def test_exact_match_scores_high():
    assert score_candidate(identity(), candidate()).confidence > 0.95


def test_live_version_is_rejected_against_studio_original():
    result = score_candidate(identity(), candidate(title="Test Song (Live)"))
    assert result.accepted is False
    assert "version mismatch" in result.rejected_reason


def test_remix_is_rejected_even_with_identical_artist_and_album():
    result = score_candidate(identity(), candidate(title="Test Song - Remix"))
    assert result.accepted is False


def test_matching_live_recording_to_live_lyrics_is_allowed():
    result = score_candidate(
        identity(title="Test Song (Live)"),
        candidate(title="Test Song (Live)"),
    )
    assert result.accepted is True


def test_duration_far_outside_tolerance_is_rejected():
    result = score_candidate(identity(), candidate(duration_seconds=300.0))
    assert result.accepted is False
    assert "duration" in result.rejected_reason


def test_small_duration_drift_is_tolerated():
    assert score_candidate(identity(), candidate(duration_seconds=242.0)).accepted is True


def test_a_snippet_is_still_rejected():
    # Half-length preview uploads are common and must never match.
    assert score_candidate(identity(), candidate(duration_seconds=114.0)).accepted is False


def test_radio_edit_of_a_long_track_is_still_rejected():
    # 354s original vs 317s edit: 37s apart, past the proportional limit.
    long_song = identity(duration_ms=354_000)
    result = score_candidate(long_song, candidate(duration_seconds=317.0))
    assert result.accepted is False


def test_duration_tolerance_scales_with_track_length():
    # The same 10s drift is noise on a ten-minute track...
    long_song = identity(duration_ms=600_000)
    assert duration_score(long_song, candidate(duration_seconds=610.0)) == 1.0
    # ...but meaningful on a four-minute one.
    assert duration_score(identity(), candidate(duration_seconds=250.0)) < 0.6
    # Short tracks keep the absolute floor, so tolerance never collapses to zero.
    short_song = identity(duration_ms=90_000)
    assert duration_score(short_song, candidate(duration_seconds=92.0)) == 1.0


def test_long_track_rejection_also_scales():
    # 10% of a ten-minute track is a minute; 45s of drift stays a candidate.
    long_song = identity(duration_ms=600_000)
    assert score_candidate(long_song, candidate(duration_seconds=645.0)).accepted is True
    # Two minutes apart is a different recording.
    assert score_candidate(long_song, candidate(duration_seconds=720.0)).accepted is False


def test_mildly_wrong_duration_is_never_worse_than_no_duration():
    """Regression: degrading metadata must not improve matching.

    Provider durations disagree routinely, so a track whose title, artist and
    album all agree perfectly must not fail purely because the catalog reported
    a length 16s off — while a missing duration succeeds.
    """
    known_good = candidate(duration_seconds=228.0)

    unknown = best_match(identity(duration_ms=None), [known_good])
    slightly_wrong = best_match(identity(duration_ms=244_000), [known_good])

    assert unknown is not None
    assert slightly_wrong is not None, "wrong duration must not beat unknown duration"


def test_exact_duration_still_outranks_a_drifting_one():
    exact = candidate(version_id="exact", duration_seconds=240.0)
    drifting = candidate(version_id="drifting", duration_seconds=249.0)
    winner = best_match(identity(), [drifting, exact])
    assert winner is not None
    assert winner.candidate.version_id == "exact"


def test_uncorroborated_duration_stops_deciding_between_candidates():
    """A catalog duration nothing agrees with must not pick the winner.

    With a wrong 244s, ranking on duration picks the 256s upload purely because
    it sits nearest a bad number, over the 228s version every other source
    agrees on. An unusable duration is ignored rather than trusted.
    """
    pool = [
        candidate(version_id="256", duration_seconds=256.0),
        candidate(version_id="228a", duration_seconds=228.0),
        candidate(version_id="228b", duration_seconds=228.0),
    ]

    winner = best_match(identity(duration_ms=244_000), pool)

    assert winner is not None
    assert winner.candidate.duration_seconds == 228.0


def test_consensus_needs_more_than_one_agreeing_source():
    # A single candidate agrees with nothing and cannot establish a consensus.
    from music_hub.lyrics.matcher import consensus_duration_ms

    assert consensus_duration_ms([candidate(duration_seconds=228.0)]) is None
    assert (
        consensus_duration_ms(
            [candidate(duration_seconds=228.0), candidate(duration_seconds=228.4)]
        )
        == 228_000
    )


def test_uncorroborated_duration_matches_the_unknown_duration_choice():
    # Ignoring a useless duration must land on the same answer as never having
    # had one, so the two paths cannot disagree.
    pool = [
        candidate(version_id="256", duration_seconds=256.0),
        candidate(version_id="228a", duration_seconds=228.0),
        candidate(version_id="228b", duration_seconds=228.0),
    ]
    unknown = best_match(identity(duration_ms=None), pool)
    uncorroborated = best_match(identity(duration_ms=244_000), pool)

    assert unknown is not None and uncorroborated is not None
    assert unknown.candidate.version_id == uncorroborated.candidate.version_id


def test_corroborated_duration_is_still_trusted():
    # When one candidate does agree, duration keeps its full discriminating power.
    exact = candidate(version_id="exact", duration_seconds=240.0)
    other = candidate(version_id="other", duration_seconds=249.0)
    winner = best_match(identity(duration_ms=240_000), [other, exact])
    assert winner is not None
    assert winner.candidate.version_id == "exact"


def test_snippets_are_rejected_even_when_duration_is_uncorroborated():
    # Distrusting the duration must not disable the outright rejection.
    snippet = candidate(version_id="snippet", duration_seconds=60.0)
    winner = best_match(identity(duration_ms=244_000), [snippet])
    assert winner is None


def test_low_confidence_match_is_discarded_rather_than_shown():
    wrong = candidate(title="Something Else Entirely", artist="Another Artist", album="Other")
    assert best_match(identity(), [wrong]) is None


def test_best_match_prefers_synced_over_plain_when_confidence_ties():
    plain_only = candidate(version_id="plain", synced_text="", plain_text="words")
    synced = candidate(version_id="synced")
    winner = best_match(identity(), [plain_only, synced])
    assert winner is not None
    assert winner.candidate.version_id == "synced"


def test_featuring_credits_do_not_break_artist_match():
    result = score_candidate(
        identity(artist="Test Artist, Second Singer"),
        candidate(artist="Test Artist feat. Second Singer"),
    )
    assert result.accepted is True
    assert result.confidence > 0.9


# --- Indian-script safety --------------------------------------------------


@pytest.mark.parametrize(
    "text,expected",
    [
        ("മലയാളം പാട്ട്", "ml"),
        ("தமிழ் பாடல்", "ta"),
        ("हिंदी गाना", "hi"),
        ("తెలుగు పాట", "te"),
        ("ಕನ್ನಡ ಹಾಡು", "kn"),
    ],
)
def test_script_detection_covers_indian_languages(text, expected):
    assert detect_script(text) == expected


def test_normalize_preserves_indic_characters():
    # The Latin-only validation bug must not reappear here: normalization
    # strips punctuation but never the script itself.
    assert normalize_text("മലയാളം, പാട്ട്!") == "മലയാളം പാട്ട്"
    assert normalize_text("हिंदी गाना") == "हिंदी गाना"


def test_malayalam_title_matches_itself():
    result = score_candidate(
        identity(title="ദേവദൂതർ പാടി", artist="കെ ജെ യേശുദാസ്", language="ml"),
        candidate(title="ദേവദൂതർ പാടി", artist="കെ ജെ യേശുദാസ്", language="ml"),
    )
    assert result.accepted is True
    assert result.confidence > 0.9


# --- service behaviour -----------------------------------------------------


@pytest.mark.asyncio
async def test_synced_lyrics_are_returned_as_available():
    service, provider, music, _ = make_service()
    music.song.return_value = {
        "title": "Test Song",
        "artist": "Test Artist",
        "album_title": "Test Album",
        "duration": 240,
    }
    provider.search.return_value = [candidate()]

    document = await service.for_song("song-1")

    assert document.status is LyricsStatus.AVAILABLE
    assert document.sync_type is SyncType.LINE
    assert len(document.lines) == 4
    assert document.confidence > 0.9


@pytest.mark.asyncio
async def test_broken_timestamps_fall_back_to_plain_not_fake_sync():
    service, provider, music, _ = make_service()
    music.song.return_value = {"title": "Test Song", "artist": "Test Artist", "duration": 240}
    provider.search.return_value = [
        candidate(synced_text="[00:01.00]Only one line", plain_text="Full lyrics here")
    ]

    document = await service.for_song("song-1")

    assert document.status is LyricsStatus.PLAIN_ONLY
    assert document.lines == []
    assert document.plain_text == "Full lyrics here"


@pytest.mark.asyncio
async def test_instrumental_track_reports_instrumental_status():
    service, provider, music, _ = make_service()
    music.song.return_value = {"title": "Test Song", "artist": "Test Artist", "duration": 240}
    provider.search.return_value = [candidate(instrumental=True, synced_text="")]

    document = await service.for_song("song-1")

    assert document.status is LyricsStatus.INSTRUMENTAL
    assert document.lines == []


@pytest.mark.asyncio
async def test_no_candidates_reports_not_found():
    service, provider, music, _ = make_service()
    music.song.return_value = {"title": "Test Song", "artist": "Test Artist", "duration": 240}
    provider.search.return_value = []

    document = await service.for_song("song-1")

    assert document.status is LyricsStatus.NOT_FOUND


@pytest.mark.asyncio
async def test_provider_outage_is_temporary_error_and_is_not_cached():
    service, provider, music, cache = make_service()
    music.song.return_value = {"title": "Test Song", "artist": "Test Artist", "duration": 240}
    provider.search.side_effect = ProviderUnavailable("down")

    document = await service.for_song("song-1")

    assert document.status is LyricsStatus.TEMPORARY_ERROR
    # A blip must not become an hour of "no lyrics".
    cache.set_json.assert_not_called()


@pytest.mark.asyncio
async def test_wrong_version_lyrics_are_never_served():
    service, provider, music, _ = make_service()
    music.song.return_value = {
        "title": "Test Song",
        "artist": "Test Artist",
        "album_title": "Test Album",
        "duration": 240,
    }
    provider.search.return_value = [candidate(title="Test Song (Live at Wembley)")]

    document = await service.for_song("song-1")

    assert document.status is LyricsStatus.NOT_FOUND
    assert document.lines == []


@pytest.mark.asyncio
async def test_cached_document_short_circuits_the_provider():
    service, provider, music, cache = make_service()
    music.song.return_value = {"title": "Test Song", "artist": "Test Artist", "duration": 240}
    cached = {
        "song_id": "song-1",
        "status": "available",
        "sync_type": "line",
        "offset_ms": 0,
        "lines": [{"start_ms": 0, "end_ms": 1000, "text": "cached"}],
        "song_identity_hash": _identity_from_song(
            "song-1", {"title": "Test Song", "artist": "Test Artist", "duration": 240}
        ).identity_hash(),
    }
    cache.get_json.return_value = cached

    document = await service.for_song("song-1")

    assert document.lines[0].text == "cached"
    provider.search.assert_not_called()


@pytest.mark.asyncio
async def test_cache_entry_for_a_different_recording_is_ignored():
    service, provider, music, cache = make_service()
    music.song.return_value = {"title": "Test Song", "artist": "Test Artist", "duration": 240}
    cache.get_json.return_value = {
        "song_id": "song-1",
        "status": "available",
        "lines": [{"start_ms": 0, "end_ms": 1000, "text": "stale"}],
        "song_identity_hash": "deadbeefdeadbeef",
    }
    provider.search.return_value = []

    document = await service.for_song("song-1")

    assert document.status is LyricsStatus.NOT_FOUND
    provider.search.assert_called_once()


@pytest.mark.asyncio
async def test_song_lookup_failure_never_raises():
    service, _, music, _ = make_service()
    music.song.side_effect = RuntimeError("catalog exploded")

    document = await service.for_song("song-1")

    # A lyrics failure must never surface as a playback failure.
    assert document.status is LyricsStatus.NOT_FOUND


# --- metadata extraction ---------------------------------------------------


def test_identity_parses_mm_ss_duration():
    parsed = _identity_from_song("s", {"title": "T", "artist": "A", "duration": "3:45"})
    assert parsed.duration_ms == 225_000


def test_identity_joins_structured_artist_lists():
    parsed = _identity_from_song(
        "s", {"title": "T", "artists": [{"name": "First"}, {"name": "Second"}]}
    )
    assert parsed.artist == "First, Second"


def test_identity_hash_changes_when_recording_changes():
    first = _identity_from_song("s", {"title": "T", "artist": "A", "duration": 240})
    second = _identity_from_song("s", {"title": "T", "artist": "A", "duration": 300})
    assert first.identity_hash() != second.identity_hash()
