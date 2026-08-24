from uuid import UUID

from music_hub.database import Database
from music_hub.schemas.users import ArtistPreference, LanguagePreference, UserPreferencesUpdate


class PreferenceRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def replace_onboarding(
        self,
        user_id: UUID,
        languages: list[LanguagePreference],
        artists: list[ArtistPreference],
    ) -> None:
        async with self.database.transaction() as connection:
            await connection.execute("DELETE FROM user_languages WHERE user_id = $1", user_id)
            await connection.execute("DELETE FROM user_artists WHERE user_id = $1", user_id)
            await connection.executemany(
                "INSERT INTO user_languages (user_id, language_code, priority) VALUES ($1, $2, $3)",
                [(user_id, item.language_code, item.priority) for item in languages],
            )
            if artists:
                await connection.executemany(
                    """
                    INSERT INTO user_artists
                        (user_id, provider, provider_artist_id, artist_name, artist_image, preference_score)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    """,
                    [
                        (
                            user_id,
                            item.provider,
                            item.provider_artist_id,
                            item.artist_name,
                            item.artist_image,
                            item.preference_score,
                        )
                        for item in artists
                    ],
                )
            await connection.execute(
                "UPDATE users SET onboarding_completed = TRUE, updated_at = now() WHERE id = $1",
                user_id,
            )

    async def replace_languages(
        self,
        user_id: UUID,
        languages: list[LanguagePreference],
    ) -> None:
        async with self.database.transaction() as connection:
            await connection.execute(
                "DELETE FROM user_languages WHERE user_id = $1",
                user_id,
            )
            await connection.executemany(
                "INSERT INTO user_languages (user_id, language_code, priority) VALUES ($1, $2, $3)",
                [(user_id, item.language_code, item.priority) for item in languages],
            )

    async def replace_artists(
        self,
        user_id: UUID,
        artists: list[ArtistPreference],
    ) -> None:
        async with self.database.transaction() as connection:
            await connection.execute(
                "DELETE FROM user_artists WHERE user_id = $1",
                user_id,
            )
            if artists:
                await connection.executemany(
                    """
                    INSERT INTO user_artists
                        (user_id, provider, provider_artist_id, artist_name, artist_image, preference_score)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    """,
                    [
                        (
                            user_id,
                            item.provider,
                            item.provider_artist_id,
                            item.artist_name,
                            item.artist_image,
                            item.preference_score,
                        )
                        for item in artists
                    ],
                )

    async def get_languages(self, user_id: UUID) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT language_code, priority
            FROM user_languages
            WHERE user_id = $1
            ORDER BY priority DESC, created_at
            """,
            user_id,
        )
        return [dict(row) for row in rows]

    async def get_artists(self, user_id: UUID) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT provider, provider_artist_id, artist_name, artist_image, preference_score
            FROM user_artists
            WHERE user_id = $1
            ORDER BY preference_score DESC, created_at
            """,
            user_id,
        )
        return [dict(row) for row in rows]

    async def get_onboarding(self, user_id: UUID) -> dict:
        user = await self.database.fetchrow(
            "SELECT onboarding_completed FROM users WHERE id = $1",
            user_id,
        )
        return {
            "onboarding_completed": bool(user and user["onboarding_completed"]),
            "languages": await self.get_languages(user_id),
            "artists": await self.get_artists(user_id),
        }

    async def update_preferences(self, user_id: UUID, update: UserPreferencesUpdate) -> dict:
        values = update.model_dump(exclude_none=True)
        settings = values.pop("settings", {})
        row = await self.database.fetchrow(
            """
            INSERT INTO user_preferences (user_id, explicit_content, autoplay, audio_quality, settings)
            VALUES ($1, COALESCE($2, TRUE), COALESCE($3, TRUE), COALESCE($4, 'high'), $5::jsonb)
            ON CONFLICT (user_id) DO UPDATE
            SET explicit_content = COALESCE(EXCLUDED.explicit_content, user_preferences.explicit_content),
                autoplay = COALESCE(EXCLUDED.autoplay, user_preferences.autoplay),
                audio_quality = COALESCE(EXCLUDED.audio_quality, user_preferences.audio_quality),
                settings = user_preferences.settings || EXCLUDED.settings,
                updated_at = now()
            RETURNING *
            """,
            user_id,
            values.get("explicit_content"),
            values.get("autoplay"),
            values.get("audio_quality"),
            settings,
        )
        return dict(row) if row else {}

    async def get_preferences(self, user_id: UUID) -> dict:
        row = await self.database.fetchrow(
            "SELECT * FROM user_preferences WHERE user_id = $1",
            user_id,
        )
        return dict(row) if row else {
            "user_id": user_id,
            "explicit_content": True,
            "autoplay": True,
            "audio_quality": "high",
            "settings": {},
        }
