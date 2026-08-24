from uuid import UUID

from music_hub.database import Database
from music_hub.schemas.devices import DeviceRegistration


class DeviceRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def register(self, user_id: UUID, payload: DeviceRegistration) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO user_devices
                (user_id, device_id, platform, device_name, fcm_token,
                 app_version, notifications_enabled, last_active_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, now())
            ON CONFLICT (user_id, device_id) DO UPDATE
            SET platform = EXCLUDED.platform,
                device_name = EXCLUDED.device_name,
                fcm_token = EXCLUDED.fcm_token,
                app_version = EXCLUDED.app_version,
                notifications_enabled = EXCLUDED.notifications_enabled,
                last_active_at = now()
            RETURNING *
            """,
            user_id,
            payload.device_id,
            payload.platform,
            payload.device_name,
            payload.fcm_token,
            payload.app_version,
            payload.notifications_enabled,
        )
        return dict(row) if row else {}

    async def remove(self, user_id: UUID, device_id: str) -> None:
        await self.database.execute(
            "DELETE FROM user_devices WHERE user_id = $1 AND device_id = $2",
            user_id,
            device_id,
        )
