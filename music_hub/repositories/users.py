from uuid import UUID

from music_hub.auth.firebase import FirebaseIdentity
from music_hub.database import Database
from music_hub.errors import ResourceNotFound


class UserRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def resolve_identity(self, identity: FirebaseIdentity) -> dict:
        existing = await self.database.fetchrow(
            "SELECT * FROM users WHERE firebase_uid = $1",
            identity.uid,
        )
        if existing:
            return dict(existing)
        row = await self.database.fetchrow(
            """
            INSERT INTO users (firebase_uid, display_name, email, photo_url, last_login_at)
            VALUES ($1, $2, $3, $4, now())
            ON CONFLICT (firebase_uid) DO UPDATE
            SET display_name = COALESCE(EXCLUDED.display_name, users.display_name),
                email = COALESCE(EXCLUDED.email, users.email),
                photo_url = COALESCE(EXCLUDED.photo_url, users.photo_url)
            RETURNING *
            """,
            identity.uid,
            identity.display_name,
            identity.email,
            identity.photo_url,
        )
        if not row:
            raise ResourceNotFound("User could not be resolved")
        return dict(row)

    async def sync_login(self, user_id: UUID, identity: FirebaseIdentity) -> dict:
        row = await self.database.fetchrow(
            """
            UPDATE users
            SET display_name = COALESCE($2, display_name),
                email = COALESCE($3, email),
                photo_url = COALESCE($4, photo_url),
                last_login_at = now(),
                updated_at = now()
            WHERE id = $1
            RETURNING *
            """,
            user_id,
            identity.display_name,
            identity.email,
            identity.photo_url,
        )
        if not row:
            raise ResourceNotFound("User was not found")
        return dict(row)

    async def get(self, user_id: UUID) -> dict:
        row = await self.database.fetchrow("SELECT * FROM users WHERE id = $1", user_id)
        if not row:
            raise ResourceNotFound("User was not found")
        return dict(row)

    async def delete(self, user_id: UUID) -> None:
        result = await self.database.execute(
            "DELETE FROM users WHERE id = $1",
            user_id,
        )
        if result == "DELETE 0":
            raise ResourceNotFound("User was not found")
