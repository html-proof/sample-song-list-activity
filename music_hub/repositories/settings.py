from music_hub.database import Database


# Maps logical setting group → (user_profiles columns, enabled_flag)
_PROFILE_SETTINGS = {
    "playback": {
        "streaming_quality_wifi": "high",
        "streaming_quality_mobile": "normal",
        "download_quality": "high",
        "data_saver_enabled": False,
        "autoplay_enabled": True,
        "equalizer_preset": "Default",
    },
    "notifications": {
        "push_notifications_enabled": True,
        "pulse_followed_releases_enabled": True,
        "pulse_selected_releases_enabled": True,
        "pulse_trending_enabled": True,
        "pulse_recommendations_enabled": True,
    },
    "privacy": {
        "explicit_content_enabled": False,
        "save_listening_history": True,
        "analytics_enabled": True,
    },
    "general": {
        "display_name": None,
    },
}

_ALL_DEFAULTS = {
    "streaming_quality_wifi": "high",
    "streaming_quality_mobile": "normal",
    "download_quality": "high",
    "data_saver_enabled": False,
    "autoplay_enabled": True,
    "equalizer_preset": "Default",
    "push_notifications_enabled": True,
    "pulse_followed_releases_enabled": True,
    "pulse_selected_releases_enabled": True,
    "pulse_trending_enabled": True,
    "pulse_recommendations_enabled": True,
    "explicit_content_enabled": False,
    "save_listening_history": True,
    "analytics_enabled": True,
}


class SettingsRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def _get_profile(self, user_id: str) -> dict:
        row = await self.database.fetchrow(
            "SELECT * FROM user_profiles WHERE uid = $1", user_id
        )
        return dict(row) if row else {}

    async def _ensure_profile(self, user_id: str) -> None:
        await self.database.execute(
            "INSERT INTO user_profiles (uid) VALUES ($1) ON CONFLICT (uid) DO NOTHING",
            user_id,
        )

    async def get_all(self, user_id: str) -> dict:
        profile = await self._get_profile(user_id)
        return {
            group: self._extract_group(profile, group)
            for group in _PROFILE_SETTINGS
        }

    async def get_group(self, user_id: str, group: str) -> dict:
        profile = await self._get_profile(user_id)
        return self._extract_group(profile, group)

    def _extract_group(self, profile: dict, group: str) -> dict:
        defaults = _PROFILE_SETTINGS.get(group, {})
        return {col: profile.get(col, default) for col, default in defaults.items()}

    async def update_group(self, user_id: str, group: str, values: dict) -> dict:
        allowed = set(_PROFILE_SETTINGS.get(group, {}).keys())
        invalid = set(values) - allowed
        if invalid:
            raise ValueError(f"Unsupported {group} settings: {', '.join(sorted(invalid))}")
        if not values:
            return await self.get_group(user_id, group)

        await self._ensure_profile(user_id)
        columns = list(values)
        set_clauses = ", ".join(f"{col} = ${i+2}" for i, col in enumerate(columns))
        await self.database.execute(
            f"UPDATE user_profiles SET {set_clauses}, updated_at = now() WHERE uid = $1",
            user_id,
            *(values[col] for col in columns),
        )
        return await self.get_group(user_id, group)

    async def reset(self, user_id: str) -> None:
        columns = [col for group in _PROFILE_SETTINGS.values() for col in group if col in _ALL_DEFAULTS]
        if not columns:
            return
        set_clauses = ", ".join(
            f"{col} = {repr(_ALL_DEFAULTS[col])}" if isinstance(_ALL_DEFAULTS[col], str)
            else f"{col} = {str(_ALL_DEFAULTS[col]).lower()}"
            for col in columns
        )
        await self.database.execute(
            f"UPDATE user_profiles SET {set_clauses}, updated_at = now() WHERE uid = $1",
            user_id,
        )

    async def clear_history(self, user_id: str, kind: str) -> None:
        async with self.database.transaction() as connection:
            if kind == "listening":
                await connection.execute("DELETE FROM user_history WHERE uid = $1", user_id)
                await connection.execute("DELETE FROM playback_history WHERE user_id = $1", user_id)
                await connection.execute("DELETE FROM user_events WHERE user_id = $1", user_id)
            else:
                await connection.execute("DELETE FROM recent_searches WHERE uid = $1", user_id)

    async def reset_recommendations(self, user_id: str) -> None:
        await self.database.execute(
            """
            INSERT INTO user_taste_profiles (user_id, languages, artists, genres, algorithm_version, updated_at)
            VALUES ($1, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '1.0', now())
            ON CONFLICT (user_id) DO UPDATE
            SET languages = '[]'::jsonb, artists = '[]'::jsonb, genres = '[]'::jsonb, updated_at = now()
            """,
            user_id,
        )

    async def set_device_notifications(self, user_id: str, enabled: bool) -> None:
        await self.database.execute(
            "UPDATE device_tokens SET last_seen_at = now() WHERE uid = $1",
            user_id,
        )
