from typing import Any
from uuid import UUID

from music_hub.database import Database
from music_hub.schemas.settings import (
    AppSettings,
    DownloadSettings,
    GeneralSettings,
    NotificationSettings,
    PlaybackSettings,
    PrivacySettings,
    RecommendationSettings,
)


_GROUPS = {
    "general": ("general_settings", GeneralSettings),
    "playback": ("playback_settings", PlaybackSettings),
    "downloads": ("download_settings", DownloadSettings),
    "recommendations": ("recommendation_settings", RecommendationSettings),
    "notifications": ("notification_settings", NotificationSettings),
    "privacy": ("privacy_settings", PrivacySettings),
}


class SettingsRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def get_all(self, user_id: UUID) -> AppSettings:
        values = {
            group: await self.get_group(user_id, group)
            for group in _GROUPS
        }
        return AppSettings(**values)

    async def get_group(self, user_id: UUID, group: str) -> dict[str, Any]:
        table, model = _GROUPS[group]
        row = await self.database.fetchrow(
            f"SELECT * FROM {table} WHERE user_id = $1",
            user_id,
        )
        if row is None:
            await self.database.execute(
                f"INSERT INTO {table} (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING",
                user_id,
            )
            return model().model_dump()
        return model.model_validate(dict(row)).model_dump()

    async def update_group(
        self,
        user_id: UUID,
        group: str,
        values: dict[str, Any],
    ) -> dict[str, Any]:
        if not values:
            return await self.get_group(user_id, group)
        table, model = _GROUPS[group]
        allowed = set(model.model_fields)
        invalid = set(values) - allowed
        if invalid:
            raise ValueError(f"Unsupported {group} settings: {', '.join(sorted(invalid))}")
        columns = list(values)
        insert_columns = ", ".join(["user_id", *columns])
        placeholders = ", ".join(f"${index}" for index in range(1, len(columns) + 2))
        assignments = ", ".join(f"{column} = EXCLUDED.{column}" for column in columns)
        row = await self.database.fetchrow(
            f"""
            INSERT INTO {table} ({insert_columns}) VALUES ({placeholders})
            ON CONFLICT (user_id) DO UPDATE
            SET {assignments}, updated_at = now()
            RETURNING *
            """,
            user_id,
            *(values[column] for column in columns),
        )
        return model.model_validate(dict(row)).model_dump() if row else model().model_dump()

    async def reset(self, user_id: UUID) -> None:
        async with self.database.transaction() as connection:
            for table, _ in _GROUPS.values():
                await connection.execute(f"DELETE FROM {table} WHERE user_id = $1", user_id)

    async def clear_history(self, user_id: UUID, kind: str) -> None:
        table = "listening_history" if kind == "listening" else "search_history"
        await self.database.execute(f"DELETE FROM {table} WHERE user_id = $1", user_id)

    async def reset_recommendations(self, user_id: UUID) -> None:
        await self.database.execute(
            "DELETE FROM recommendation_profiles WHERE user_id = $1",
            user_id,
        )

    async def set_device_notifications(self, user_id: UUID, enabled: bool) -> None:
        await self.database.execute(
            """
            UPDATE user_devices
            SET notifications_enabled = $2, last_active_at = now()
            WHERE user_id = $1
            """,
            user_id,
            enabled,
        )
