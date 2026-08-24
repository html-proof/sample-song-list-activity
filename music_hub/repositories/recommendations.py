from collections import Counter
from uuid import UUID

from music_hub.database import Database
from music_hub.schemas.settings import PrivacySettings, RecommendationSettings


class RecommendationRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def signals(self, user_id: UUID) -> dict:
        recommendation_row = await self.database.fetchrow(
            "SELECT * FROM recommendation_settings WHERE user_id = $1",
            user_id,
        )
        privacy_row = await self.database.fetchrow(
            "SELECT * FROM privacy_settings WHERE user_id = $1",
            user_id,
        )
        playback_row = await self.database.fetchrow(
            "SELECT explicit_content FROM playback_settings WHERE user_id = $1",
            user_id,
        )
        profile_row = await self.database.fetchrow(
            """
            SELECT learning_reset_at
            FROM recommendation_profiles
            WHERE user_id = $1
            """,
            user_id,
        )
        learning_reset_at = (
            profile_row["learning_reset_at"] if profile_row else None
        )
        recommendation_settings = RecommendationSettings.model_validate(
            dict(recommendation_row) if recommendation_row else {}
        )
        privacy_settings = PrivacySettings.model_validate(
            dict(privacy_row) if privacy_row else {}
        )
        personalized = (
            recommendation_settings.enabled
            and privacy_settings.personalized_recommendations
        )
        languages = []
        selected_artists = []
        followed = []
        interest_rows = []
        if personalized:
            languages = await self.database.fetch(
                """
                SELECT language_code, priority
                FROM user_languages
                WHERE user_id = $1
                ORDER BY priority DESC
                """,
                user_id,
            )
            selected_artists = await self.database.fetch(
                """
                SELECT provider_artist_id, artist_name, preference_score
                FROM user_artists
                WHERE user_id = $1 AND provider = 'gaana'
                ORDER BY preference_score DESC
                """,
                user_id,
            )
            followed = await self.database.fetch(
                """
                SELECT artist_id
                FROM followed_artists
                WHERE user_id = $1 AND provider = 'gaana'
                """,
                user_id,
            )
            interest_rows = await self.database.fetch(
                """
                SELECT entity_type, entity_id, SUM(score) AS score,
                       SUM(occurrences) AS occurrences,
                       MAX(last_seen_at) AS last_seen_at
                FROM user_interest_signals
                WHERE user_id = $1
                  AND provider IN ('all', 'gaana')
                  AND ($2::boolean OR source <> 'liked_song')
                  AND ($3::boolean OR source <> 'listening_history')
                  AND ($4::boolean OR source <> 'music_event')
                  AND ($5::boolean OR source NOT IN ('search_history', 'search_click'))
                GROUP BY entity_type, entity_id
                HAVING SUM(score) <> 0
                ORDER BY entity_type, score DESC, last_seen_at DESC
                """,
                user_id,
                recommendation_settings.use_likes,
                (
                    recommendation_settings.use_listening_history
                    and privacy_settings.save_listening_history
                ),
                privacy_settings.analytics_enabled,
                (
                    recommendation_settings.use_search_history
                    and privacy_settings.save_search_history
                ),
            )
        liked = []
        if personalized and recommendation_settings.use_likes:
            liked = await self.database.fetch(
                """
                SELECT song_id, artist_id, language
                FROM liked_songs
                WHERE user_id = $1 AND provider = 'gaana'
                """,
                user_id,
            )
        history = []
        if (
            personalized
            and recommendation_settings.use_listening_history
            and privacy_settings.save_listening_history
        ):
            history = await self.database.fetch(
                """
                SELECT song_id, artist_id, language, completion_percentage, played_ms
                FROM listening_history
                WHERE user_id = $1 AND provider = 'gaana'
                  AND created_at > now() - interval '90 days'
                  AND created_at > COALESCE($2::timestamptz, '-infinity'::timestamptz)
                ORDER BY created_at DESC LIMIT 1000
                """,
                user_id,
                learning_reset_at,
            )
        events = []
        if personalized and privacy_settings.analytics_enabled:
            events = await self.database.fetch(
                """
                SELECT event_type::text, song_id, artist_id, language
                FROM music_events
                WHERE user_id = $1 AND provider = 'gaana'
                  AND created_at > now() - interval '90 days'
                  AND created_at > COALESCE($2::timestamptz, '-infinity'::timestamptz)
                ORDER BY created_at DESC LIMIT 2000
                """,
                user_id,
                learning_reset_at,
            )
        searches = []
        if (
            personalized
            and recommendation_settings.use_search_history
            and privacy_settings.save_search_history
        ):
            searches = await self.database.fetch(
                """
                SELECT normalized_query FROM search_history
                WHERE user_id = $1 AND created_at > now() - interval '30 days'
                  AND created_at > COALESCE($2::timestamptz, '-infinity'::timestamptz)
                ORDER BY created_at DESC LIMIT 100
                """,
                user_id,
                learning_reset_at,
            )
        playlist_songs = []
        if personalized:
            playlist_songs = await self.database.fetch(
                """
                SELECT pt.song_id
                FROM playlist_tracks pt JOIN playlists p ON p.id = pt.playlist_id
                WHERE p.user_id = $1 AND pt.provider = 'gaana'
                """,
                user_id,
            )

        play_counts = Counter(str(row["song_id"]) for row in history if row["song_id"])
        skipped_songs = Counter(
            str(row["song_id"])
            for row in events
            if row["event_type"] == "skip" and row["song_id"]
        )
        skipped_artists = Counter(
            str(row["artist_id"])
            for row in events
            if row["event_type"] == "skip" and row["artist_id"]
        )
        skipped_languages = Counter(
            str(row["language"]).casefold()
            for row in events
            if row["event_type"] == "skip" and row["language"]
        )
        completed = {
            str(row["song_id"])
            for row in history
            if row["song_id"] and (row["completion_percentage"] or 0) >= 0.9
        }
        song_affinity: dict[str, float] = {}
        artist_affinity: dict[str, float] = {}
        language_affinity: dict[str, float] = {}
        learned_searches: list[str] = []
        for row in interest_rows:
            entity_id = str(row["entity_id"])
            score = float(row["score"])
            match str(row["entity_type"]):
                case "song":
                    song_affinity[entity_id] = score
                case "artist":
                    artist_affinity[entity_id] = score
                case "language":
                    language_affinity[entity_id.casefold()] = score
                case "search":
                    if score > 0:
                        learned_searches.append(entity_id)

        # Explicit preferences remain strong even before a newly-created
        # interest profile receives its first trigger-driven update.
        for row in selected_artists:
            artist_id = str(row["provider_artist_id"])
            artist_affinity[artist_id] = max(
                artist_affinity.get(artist_id, 0),
                float(row["preference_score"]) * 10,
            )
        for row in followed:
            artist_id = str(row["artist_id"])
            artist_affinity[artist_id] = max(
                artist_affinity.get(artist_id, 0),
                14,
            )
        for row in languages:
            language = str(row["language_code"]).casefold()
            language_affinity[language] = max(
                language_affinity.get(language, 0),
                float(row["priority"]),
            )

        interest_artists = [
            artist_id
            for artist_id, score in sorted(
                artist_affinity.items(),
                key=lambda item: item[1],
                reverse=True,
            )
            if score > 0
        ][:12]
        return {
            "allow_explicit_content": bool(
                playback_row is None or playback_row["explicit_content"]
            ),
            "recommendation_settings": recommendation_settings.model_dump(),
            "exploration_level": recommendation_settings.exploration_level,
            "privacy_settings": privacy_settings.model_dump(),
            "personalized": personalized,
            "languages": {
                str(row["language_code"]).casefold(): int(row["priority"])
                for row in languages
            },
            "language_affinity": language_affinity,
            "selected_artists": {
                str(row["provider_artist_id"]): float(row["preference_score"])
                for row in selected_artists
            },
            "selected_artist_records": [dict(row) for row in selected_artists],
            "interest_artists": interest_artists,
            "artist_affinity": artist_affinity,
            "song_affinity": song_affinity,
            "liked_songs": {str(row["song_id"]) for row in liked if row["song_id"]},
            "followed_artists": {str(row["artist_id"]) for row in followed if row["artist_id"]},
            "completed_songs": completed,
            "play_counts": dict(play_counts),
            "skipped_songs": dict(skipped_songs),
            "skipped_artists": dict(skipped_artists),
            "skipped_languages": dict(skipped_languages),
            "playlist_songs": {str(row["song_id"]) for row in playlist_songs},
            "search_terms": list(
                dict.fromkeys(
                    [
                        str(row["normalized_query"])
                        for row in searches
                        if row["normalized_query"]
                    ]
                    + learned_searches
                )
            ),
        }
