import json

from music_hub.database import Database
from music_hub.schemas.users import ArtistPreference, LanguagePreference, UserPreferencesUpdate


class PreferenceRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def replace_onboarding(
        self,
        user_id: str,
        languages: list[LanguagePreference],
        artists: list[ArtistPreference],
    ) -> None:
        language_ids = [lang.language_code.lower() for lang in languages]
        artist_ids = [a.provider_artist_id for a in artists]

        async with self.database.transaction() as connection:
            # Update user_profiles with selected languages and artists
            await connection.execute(
                """
                INSERT INTO user_profiles (uid, language_ids, favorite_artist_ids, onboarding_completed, onboarding_step)
                VALUES ($1, $2, $3, TRUE, 'done')
                ON CONFLICT (uid) DO UPDATE
                SET language_ids          = EXCLUDED.language_ids,
                    favorite_artist_ids   = EXCLUDED.favorite_artist_ids,
                    onboarding_completed  = TRUE,
                    onboarding_step       = 'done',
                    updated_at            = now()
                """,
                user_id,
                language_ids,
                artist_ids,
            )
            # Mark user as onboarding-complete
            await connection.execute(
                """
                UPDATE users
                SET onboarding_completed = TRUE, onboarding_completed_at = now(), updated_at = now()
                WHERE uid = $1
                """,
                user_id,
            )
            # Sync user_languages rows
            await connection.execute("DELETE FROM user_languages WHERE user_id = $1", user_id)
            if language_ids:
                await connection.executemany(
                    """
                    INSERT INTO user_languages (user_id, language_id, weight, created_at, updated_at)
                    VALUES ($1, $2, $3, now(), now())
                    ON CONFLICT (user_id, language_id) DO UPDATE SET weight = EXCLUDED.weight, updated_at = now()
                    """,
                    [
                        (user_id, lang.language_code.lower(), float(lang.priority))
                        for lang in languages
                    ],
                )
            # Sync user_selected_artists rows
            await connection.execute(
                "DELETE FROM user_selected_artists WHERE user_id = $1", user_id
            )
            if artists:
                await connection.executemany(
                    """
                    INSERT INTO user_selected_artists (user_id, artist_id, source, created_at)
                    VALUES ($1, $2, 'onboarding', now())
                    ON CONFLICT DO NOTHING
                    """,
                    [(user_id, a.provider_artist_id) for a in artists],
                )
            # Update taste profile
            await connection.execute(
                """
                INSERT INTO user_taste_profiles (user_id, languages, artists, genres, algorithm_version, updated_at)
                VALUES ($1, $2::jsonb, $3::jsonb, '[]'::jsonb, '1.0', now())
                ON CONFLICT (user_id) DO UPDATE
                SET languages = EXCLUDED.languages, artists = EXCLUDED.artists, updated_at = now()
                """,
                user_id,
                json.dumps(language_ids),
                json.dumps(artist_ids),
            )

    async def replace_languages(
        self,
        user_id: str,
        languages: list[LanguagePreference],
    ) -> None:
        language_ids = [lang.language_code.lower() for lang in languages]
        async with self.database.transaction() as connection:
            await connection.execute(
                """
                UPDATE user_profiles SET language_ids = $2, updated_at = now() WHERE uid = $1
                """,
                user_id,
                language_ids,
            )
            await connection.execute("DELETE FROM user_languages WHERE user_id = $1", user_id)
            await connection.executemany(
                """
                INSERT INTO user_languages (user_id, language_id, weight, created_at, updated_at)
                VALUES ($1, $2, $3, now(), now())
                ON CONFLICT (user_id, language_id) DO UPDATE SET weight = EXCLUDED.weight, updated_at = now()
                """,
                [(user_id, lang.language_code.lower(), float(lang.priority)) for lang in languages],
            )

    async def replace_artists(
        self,
        user_id: str,
        artists: list[ArtistPreference],
    ) -> None:
        artist_ids = [a.provider_artist_id for a in artists]
        async with self.database.transaction() as connection:
            await connection.execute(
                """
                UPDATE user_profiles SET favorite_artist_ids = $2, updated_at = now() WHERE uid = $1
                """,
                user_id,
                artist_ids,
            )
            await connection.execute(
                "DELETE FROM user_selected_artists WHERE user_id = $1", user_id
            )
            if artists:
                await connection.executemany(
                    """
                    INSERT INTO user_selected_artists (user_id, artist_id, source, created_at)
                    VALUES ($1, $2, 'preference', now())
                    ON CONFLICT DO NOTHING
                    """,
                    [(user_id, a.provider_artist_id) for a in artists],
                )

    async def get_languages(self, user_id: str) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT language_id AS language_code, CAST(weight AS int) AS priority
            FROM user_languages
            WHERE user_id = $1
            ORDER BY weight DESC, created_at
            """,
            user_id,
        )
        return [dict(row) for row in rows]

    async def get_artists(self, user_id: str) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT artist_id AS provider_artist_id, 'gaana' AS provider,
                   artist_id AS artist_name, NULL AS artist_image, 1.0 AS preference_score
            FROM user_selected_artists
            WHERE user_id = $1
            ORDER BY created_at
            """,
            user_id,
        )
        return [dict(row) for row in rows]

    async def get_onboarding(self, user_id: str) -> dict:
        user = await self.database.fetchrow(
            "SELECT onboarding_completed FROM users WHERE uid = $1",
            user_id,
        )
        return {
            "onboarding_completed": bool(user and user["onboarding_completed"]),
            "languages": await self.get_languages(user_id),
            "artists": await self.get_artists(user_id),
        }

    async def update_preferences(self, user_id: str, update: UserPreferencesUpdate) -> dict:
        values = update.model_dump(exclude_none=True)
        settings = values.pop("settings", {})

        col_map = {
            "explicit_content": "explicit_content_enabled",
            "autoplay": "autoplay_enabled",
            "audio_quality": "streaming_quality_wifi",
        }

        updates = {col_map.get(k, k): v for k, v in values.items()}
        if "streaming_quality_wifi" in updates:
            updates["streaming_quality_mobile"] = updates["streaming_quality_wifi"]

        if not updates:
            row = await self.database.fetchrow(
                "SELECT * FROM user_profiles WHERE uid = $1", user_id
            )
            return dict(row) if row else {}

        set_clauses = ", ".join(f"{col} = ${i+2}" for i, col in enumerate(updates))
        row = await self.database.fetchrow(
            f"""
            INSERT INTO user_profiles (uid) VALUES ($1)
            ON CONFLICT (uid) DO UPDATE
            SET {set_clauses}, updated_at = now()
            RETURNING *
            """,
            user_id,
            *updates.values(),
        )
        return dict(row) if row else {}

    async def get_preferences(self, user_id: str) -> dict:
        row = await self.database.fetchrow(
            "SELECT * FROM user_profiles WHERE uid = $1",
            user_id,
        )
        if not row:
            return {
                "uid": user_id,
                "explicit_content_enabled": False,
                "autoplay_enabled": True,
                "streaming_quality_wifi": "high",
                "streaming_quality_mobile": "normal",
                "push_notifications_enabled": True,
            }
        return dict(row)
