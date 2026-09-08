import json
from uuid import UUID

from music_hub.database import Database
from music_hub.errors import ForbiddenOperation, ResourceNotFound
from music_hub.schemas.playlists import PlaylistCreate, PlaylistTrackCreate, PlaylistUpdate


class PlaylistRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def create(self, user_id: str, payload: PlaylistCreate) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO user_playlists (uid, name, description, is_public, tracks)
            VALUES ($1, $2, $3, $4, '[]'::jsonb) RETURNING *
            """,
            user_id,
            payload.name,
            payload.description,
            payload.is_public,
        )
        return dict(row) if row else {}

    async def list(self, user_id: str) -> list[dict]:
        rows = await self.database.fetch(
            "SELECT * FROM user_playlists WHERE uid = $1 ORDER BY updated_at DESC",
            user_id,
        )
        return [dict(row) for row in rows]

    async def get(self, user_id: str, playlist_id: UUID) -> dict:
        playlist = await self.database.fetchrow(
            """
            SELECT * FROM user_playlists
            WHERE id = $1 AND (uid = $2 OR is_public)
            """,
            playlist_id,
            user_id,
        )
        if not playlist:
            raise ResourceNotFound("Playlist was not found")
        return dict(playlist)

    async def update(self, user_id: str, playlist_id: UUID, payload: PlaylistUpdate) -> dict:
        await self._owned(user_id, playlist_id)
        values = payload.model_dump(exclude_unset=True)
        row = await self.database.fetchrow(
            """
            UPDATE user_playlists
            SET name        = COALESCE($3, name),
                description = COALESCE($4, description),
                is_public   = COALESCE($5, is_public),
                updated_at  = now()
            WHERE id = $1 AND uid = $2
            RETURNING *
            """,
            playlist_id,
            user_id,
            values.get("name"),
            values.get("description"),
            values.get("is_public"),
        )
        return dict(row) if row else {}

    async def delete(self, user_id: str, playlist_id: UUID) -> None:
        await self._owned(user_id, playlist_id)
        await self.database.execute(
            "DELETE FROM user_playlists WHERE id = $1 AND uid = $2",
            playlist_id,
            user_id,
        )

    async def add_track(self, user_id: str, playlist_id: UUID, item: PlaylistTrackCreate) -> dict:
        await self._owned(user_id, playlist_id)
        track = {
            "song_id":     item.song_id,
            "provider":    item.provider,
            "song_name":   item.song_name,
            "artist_name": item.artist_name,
            "album_name":  item.album_name,
            "artwork_url": item.artwork_url,
            "duration_ms": item.duration_ms,
        }
        row = await self.database.fetchrow(
            """
            UPDATE user_playlists
            SET tracks     = tracks || $3::jsonb,
                updated_at = now()
            WHERE id = $1 AND uid = $2
            RETURNING *
            """,
            playlist_id,
            user_id,
            json.dumps(track),
        )
        return dict(row) if row else {}

    async def remove_track(self, user_id: str, playlist_id: UUID, track_id: str) -> None:
        await self._owned(user_id, playlist_id)
        # Remove track by song_id from the JSONB array
        await self.database.execute(
            """
            UPDATE user_playlists
            SET tracks = (
                SELECT jsonb_agg(t)
                FROM jsonb_array_elements(tracks) AS t
                WHERE t->>'song_id' != $3
            ),
            updated_at = now()
            WHERE id = $1 AND uid = $2
            """,
            playlist_id,
            user_id,
            track_id,
        )

    async def _owned(self, user_id: str, playlist_id: UUID) -> dict:
        row = await self.database.fetchrow(
            "SELECT * FROM user_playlists WHERE id = $1", playlist_id
        )
        if not row:
            raise ResourceNotFound("Playlist was not found")
        if row["uid"] != user_id:
            raise ForbiddenOperation("You do not own this playlist")
        return dict(row)
