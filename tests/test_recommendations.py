import base64

import pytest

from music_hub.recommendations.cursor import CursorCodec, InvalidCursor
from music_hub.recommendations.diversity import diversify
from music_hub.recommendations.scoring import RecommendationSignals, WeightedScorer


def song(song_id="song-1", artist_id="artist-1", language="Malayalam"):
    return {
        "provider_id": song_id,
        "track_id": song_id,
        "title": "Test Song",
        "artist_ids": artist_id,
        "artists": "Test Artist",
        "language": language,
    }


def test_cursor_round_trip_and_tamper_protection():
    codec = CursorCodec("test-secret")
    cursor = codec.encode("feed-seed", 25)

    assert codec.decode(cursor) == ("feed-seed", 25)
    with pytest.raises(InvalidCursor):
        codec.decode(cursor[:-1] + ("A" if cursor[-1] != "A" else "B"))


def test_cursor_signature_may_contain_separator_byte(monkeypatch):
    monkeypatch.setattr(
        "music_hub.recommendations.cursor.time.time",
        lambda: 1787598130,
    )
    codec = CursorCodec("test-secret")
    cursor = codec.encode("feed-seed", 25)
    token = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4))

    assert b"." in token[-32:]
    assert codec.decode(cursor) == ("feed-seed", 25)


def test_weighted_score_rewards_strong_positive_signals():
    scorer = WeightedScorer()
    signals = RecommendationSignals(
        languages={"malayalam": 5},
        selected_artists={"artist-1": 1.0},
        followed_artists={"artist-1"},
        liked_songs={"song-1"},
        completed_songs={"song-1"},
        playlist_songs={"song-1"},
        play_counts={"song-1": 3},
    )

    score, reasons = scorer.score(song(), signals, "seed")

    assert score > 200
    assert "preferred_language" in reasons
    assert "followed_artist" in reasons
    assert "repeated_play" in reasons


def test_weighted_score_penalizes_repeated_skips():
    scorer = WeightedScorer()
    positive, _ = scorer.score(song(), RecommendationSignals(), "seed")
    negative, reasons = scorer.score(
        song(),
        RecommendationSignals(
            skipped_songs={"song-1": 2},
            skipped_artists={"artist-1": 3},
            skipped_languages={"malayalam": 4},
        ),
        "seed",
    )

    assert negative < positive - 100
    assert "skipped_song" in reasons
    assert "frequently_skipped_artist" in reasons


def test_diversity_deduplicates_and_caps_artist_dominance():
    candidates = [song(f"song-{index}", "same-artist") for index in range(6)]
    candidates.append(song("different-song", "different-artist", "Tamil"))
    candidates.append(candidates[0])

    result = diversify(candidates, max_per_artist=2, max_per_language=10)

    assert [item["provider_id"] for item in result] == [
        "song-0",
        "song-1",
        "different-song",
    ]
