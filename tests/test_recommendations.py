import base64
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from music_hub.recommendations.candidate_generator import CandidateGenerator
from music_hub.recommendations.cursor import CursorCodec, InvalidCursor
from music_hub.recommendations.diversity import diversify
from music_hub.recommendations.scoring import RecommendationSignals, WeightedScorer
from music_hub.repositories.recommendations import RecommendationRepository


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


def test_weighted_score_uses_learned_user_affinity():
    scorer = WeightedScorer()
    baseline, _ = scorer.score(song(), RecommendationSignals(), "seed")
    personalized, reasons = scorer.score(
        song(),
        RecommendationSignals(
            artist_affinity={"artist-1": 16},
            language_affinity={"malayalam": 8},
            song_affinity={"song-1": 12},
        ),
        "seed",
    )

    assert personalized > baseline + 80
    assert "learned_artist_interest" in reasons
    assert "learned_language_interest" in reasons
    assert "learned_song_interest" in reasons


@pytest.mark.asyncio
async def test_candidate_generation_uses_each_users_interest_artists():
    provider = AsyncMock()
    provider.trending.return_value = []
    provider.new_releases.return_value = []
    provider.get_artist_tracks.side_effect = lambda artist_id, **_: {
        "tracks": [song(f"song-for-{artist_id}", artist_id)]
    }
    generator = CandidateGenerator(provider)

    result = await generator.generate(
        {
            "personalized": True,
            "languages": {"malayalam": 10},
            "interest_artists": ["artist-a", "artist-b"],
            "selected_artist_records": [
                {"provider_artist_id": "artist-a"},
            ],
            "recommendation_settings": {
                "enabled": True,
                "cross_language_discovery": False,
                "discover_new_artists": True,
            },
        }
    )

    assert provider.get_artist_tracks.await_count == 2
    assert {item["provider_id"] for item in result} == {
        "song-for-artist-a",
        "song-for-artist-b",
    }
    assert {item["recommendation_source"] for item in result} == {
        "selected_artist",
        "interest_artist",
    }


class _UserScopedRecommendationDatabase:
    def __init__(self, profiles):
        self.profiles = profiles
        self.calls = []

    async def fetchrow(self, query, *args):
        self.calls.append((query, args))
        assert args and args[0] in self.profiles
        return None

    async def fetch(self, query, *args):
        self.calls.append((query, args))
        user_id = args[0]
        assert user_id in self.profiles
        profile = self.profiles[user_id]
        if "FROM user_languages" in query:
            return [{"language_code": profile["language"], "priority": 10}]
        if "FROM user_artists" in query:
            return [
                {
                    "provider_artist_id": profile["artist"],
                    "artist_name": profile["artist"],
                    "preference_score": 1.0,
                }
            ]
        if "FROM user_interest_signals" in query:
            return [
                {
                    "entity_type": "artist",
                    "entity_id": profile["artist"],
                    "score": 10.0,
                    "occurrences": 1,
                    "last_seen_at": None,
                }
            ]
        return []


@pytest.mark.asyncio
async def test_recommendation_repository_never_mixes_user_signals():
    first_user = uuid4()
    second_user = uuid4()
    database = _UserScopedRecommendationDatabase(
        {
            first_user: {"language": "Malayalam", "artist": "artist-one"},
            second_user: {"language": "Tamil", "artist": "artist-two"},
        }
    )
    repository = RecommendationRepository(database)

    first = await repository.signals(first_user)
    second = await repository.signals(second_user)

    assert first["languages"] == {"malayalam": 10}
    assert second["languages"] == {"tamil": 10}
    assert first["interest_artists"] == ["artist-one"]
    assert second["interest_artists"] == ["artist-two"]
    assert "artist-two" not in first["artist_affinity"]
    assert "artist-one" not in second["artist_affinity"]
    assert all(args[0] in {first_user, second_user} for _, args in database.calls)
