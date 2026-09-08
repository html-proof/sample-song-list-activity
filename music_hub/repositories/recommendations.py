from collections import Counter

from music_hub.database import Database
from music_hub.schemas.settings import PrivacySettings, RecommendationSettings


class RecommendationRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def signals(self, user_id: str) -> dict:
        profile_row = await self.database.fetchrow(
            "SELECT * FROM user_profiles WHERE uid = $1",
            user_id,
        )
        profile = dict(profile_row) if profile_row else {}

        recommendation_settings = RecommendationSettings()
        privacy_settings = PrivacySettings(
            save_listening_history=True,
            save_search_history=True,
            personalized_recommendations=True,
            analytics_enabled=True,
        )
        allow_explicit = profile.get("explicit_content_enabled", False)
        personalized = privacy_settings.personalized_recommendations

        languages = []
        selected_artists = []
        followed = []

        if personalized:
            languages = await self.database.fetch(
                """
                SELECT language_id AS language_code, CAST(weight AS int) AS priority
                FROM user_languages
                WHERE user_id = $1
                ORDER BY weight DESC
                """,
                user_id,
            )
            selected_artists = await self.database.fetch(
                """
                SELECT artist_id AS provider_artist_id, artist_id AS artist_name,
                       1.0 AS preference_score
                FROM user_selected_artists
                WHERE user_id = $1
                ORDER BY created_at
                """,
                user_id,
            )
            followed = await self.database.fetch(
                "SELECT seokey AS artist_id FROM user_followed_artists WHERE uid = $1",
                user_id,
            )

        liked = []
        if personalized and recommendation_settings.use_likes:
            liked = await self.database.fetch(
                """
                SELECT seokey AS song_id,
                       track->>'artist_ids'->>0 AS artist_id,
                       track->>'language' AS language
                FROM user_favorites
                WHERE uid = $1
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
                SELECT song_id,
                       artist_id,
                       metadata->>'language' AS language,
                       completion_percentage,
                       position_ms AS played_ms
                FROM playback_history
                WHERE user_id = $1
                  AND started_at > now() - interval '90 days'
                ORDER BY started_at DESC LIMIT 1000
                """,
                user_id,
            )

        events = []
        if personalized and privacy_settings.analytics_enabled:
            events = await self.database.fetch(
                """
                SELECT event_type, song_id, artist_id,
                       payload->>'language' AS language
                FROM user_events
                WHERE user_id = $1
                  AND created_at > now() - interval '90 days'
                ORDER BY created_at DESC LIMIT 2000
                """,
                user_id,
            )

        searches = []
        if (
            personalized
            and recommendation_settings.use_search_history
            and privacy_settings.save_search_history
        ):
            searches = await self.database.fetch(
                """
                SELECT query AS normalized_query FROM recent_searches
                WHERE uid = $1 AND searched_at > now() - interval '30 days'
                ORDER BY searched_at DESC LIMIT 100
                """,
                user_id,
            )

        playlist_songs = []
        if personalized:
            playlist_rows = await self.database.fetch(
                "SELECT tracks FROM user_playlists WHERE uid = $1",
                user_id,
            )
            for row in playlist_rows:
                tracks = row["tracks"] or []
                for t in tracks:
                    if isinstance(t, dict) and t.get("song_id"):
                        playlist_songs.append({"song_id": t["song_id"]})

        play_counts = Counter(str(row["song_id"]) for row in history if row["song_id"])
        skipped_songs = Counter(
            str(row["song_id"])
            for row in events
            if row["event_type"] in {"skip", "user_pressed_next"} and row["song_id"]
        )
        skipped_artists = Counter(
            str(row["artist_id"])
            for row in events
            if row["event_type"] in {"skip", "user_pressed_next"} and row["artist_id"]
        )
        skipped_languages = Counter(
            str(row["language"]).casefold()
            for row in events
            if row["event_type"] in {"skip", "user_pressed_next"} and row["language"]
        )
        completed = {
            str(row["song_id"])
            for row in history
            if row["song_id"] and (row["completion_percentage"] or 0) >= 90
        }

        artist_affinity: dict[str, float] = {}
        language_affinity: dict[str, float] = {}

        for row in selected_artists:
            artist_id = str(row["provider_artist_id"])
            artist_affinity[artist_id] = max(
                artist_affinity.get(artist_id, 0),
                float(row["preference_score"]) * 10,
            )
        for row in followed:
            artist_id = str(row["artist_id"])
            artist_affinity[artist_id] = max(artist_affinity.get(artist_id, 0), 14)
        for row in languages:
            language = str(row["language_code"]).casefold()
            language_affinity[language] = max(
                language_affinity.get(language, 0),
                float(row["priority"]),
            )

        interest_artists = [
            artist_id
            for artist_id, score in sorted(
                artist_affinity.items(), key=lambda item: item[1], reverse=True
            )
            if score > 0
        ][:12]

        return {
            "allow_explicit_content": allow_explicit,
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
            "song_affinity": {},
            "liked_songs": {str(row["song_id"]) for row in liked if row["song_id"]},
            "followed_artists": {str(row["artist_id"]) for row in followed if row["artist_id"]},
            "completed_songs": completed,
            "play_counts": dict(play_counts),
            "skipped_songs": dict(skipped_songs),
            "skipped_artists": dict(skipped_artists),
            "skipped_languages": dict(skipped_languages),
            "playlist_songs": {str(t["song_id"]) for t in playlist_songs},
            "search_terms": list(
                dict.fromkeys(
                    str(row["normalized_query"])
                    for row in searches
                    if row["normalized_query"]
                )
            ),
        }
