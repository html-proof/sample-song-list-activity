from music_hub.database import Database
from music_hub.schemas.devices import DeviceRegistration


class DeviceRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def register(self, user_id: str, payload: DeviceRegistration) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO device_tokens (uid, token, platform, device_name, last_seen_at)
            VALUES ($1, $2, $3, $4, now())
            ON CONFLICT (token) DO UPDATE
            SET uid          = EXCLUDED.uid,
                platform     = EXCLUDED.platform,
                device_name  = EXCLUDED.device_name,
                last_seen_at = now()
            RETURNING *
            """,
            user_id,
            payload.fcm_token or payload.device_id,
            payload.platform,
            payload.device_name,
        )
        return dict(row) if row else {}

    async def remove(self, user_id: str, device_id: str) -> None:
        await self.database.execute(
            "DELETE FROM device_tokens WHERE uid = $1 AND (token = $2 OR id::text = $2)",
            user_id,
            device_id,
        )
