from uuid import UUID

from music_hub.database import Database
from music_hub.errors import ForbiddenOperation, ResourceNotFound
from music_hub.schemas.playlists import PlaylistCreate, PlaylistTrackCreate, PlaylistUpdate


class PlaylistRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def create(self, user_id: UUID, payload: PlaylistCreate) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO playlists (user_id, name, description, is_public)
            VALUES ($1, $2, $3, $4) RETURNING *, 0::bigint AS track_count
            """,
            user_id,
            payload.name,
            payload.description,
            payload.is_public,
        )
        return dict(row) if row else {}

    async def list(self, user_id: UUID) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT p.*, COUNT(pt.id) AS track_count
            FROM playlists p
            LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
            WHERE p.user_id = $1
            GROUP BY p.id
            ORDER BY p.updated_at DESC
            """,
            user_id,
        )
        return [dict(row) for row in rows]

    async def get(self, user_id: UUID, playlist_id: UUID) -> dict:
        playlist = await self.database.fetchrow(
            """
            SELECT p.*, COUNT(pt.id) AS track_count
            FROM playlists p
            LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
            WHERE p.id = $1 AND (p.user_id = $2 OR p.is_public)
            GROUP BY p.id
            """,
            playlist_id,
            user_id,
        )
        if not playlist:
            raise ResourceNotFound("Playlist was not found")
        tracks = await self.database.fetch(
            """
            SELECT id, playlist_id, provider, song_id, song_name, artist_name,
                   album_name, artwork_url, duration_ms, position, added_at
            FROM playlist_tracks
            WHERE playlist_id = $1 AND user_id = $2
            ORDER BY position, added_at
            """,
            playlist_id,
            playlist["user_id"],
        )
        return {**dict(playlist), "tracks": [dict(row) for row in tracks]}

    async def update(self, user_id: UUID, playlist_id: UUID, payload: PlaylistUpdate) -> dict:
        current = await self._owned(user_id, playlist_id)
        values = payload.model_dump(exclude_unset=True)
        row = await self.database.fetchrow(
            """
            UPDATE playlists
            SET name = $3, description = $4, is_public = $5, updated_at = now()
            WHERE id = $1 AND user_id = $2
            RETURNING *, (SELECT COUNT(*) FROM playlist_tracks WHERE playlist_id = $1) AS track_count
            """,
            playlist_id,
            user_id,
            values.get("name", current["name"]),
            values.get("description", current["description"]),
            values.get("is_public", current["is_public"]),
        )
        return dict(row) if row else {}

    async def delete(self, user_id: UUID, playlist_id: UUID) -> None:
        await self._owned(user_id, playlist_id)
        await self.database.execute(
            "DELETE FROM playlists WHERE id = $1 AND user_id = $2",
            playlist_id,
            user_id,
        )

    async def add_track(self, user_id: UUID, playlist_id: UUID, item: PlaylistTrackCreate) -> dict:
        await self._owned(user_id, playlist_id)
        row = await self.database.fetchrow(
            """
            INSERT INTO playlist_tracks (
                playlist_id, user_id, provider, song_id, song_name, artist_name,
                album_name, artwork_url, duration_ms, position
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, $8, $9,
                COALESCE((SELECT MAX(position) + 1 FROM playlist_tracks WHERE playlist_id = $1), 0)
            )
            ON CONFLICT (playlist_id, provider, song_id) DO UPDATE
            SET song_name = EXCLUDED.song_name, artist_name = EXCLUDED.artist_name,
                album_name = EXCLUDED.album_name, artwork_url = EXCLUDED.artwork_url,
                duration_ms = EXCLUDED.duration_ms
            RETURNING *
            """,
            playlist_id,
            user_id,
            item.provider,
            item.song_id,
            item.song_name,
            item.artist_name,
            item.album_name,
            item.artwork_url,
            item.duration_ms,
        )
        await self.database.execute("UPDATE playlists SET updated_at = now() WHERE id = $1", playlist_id)
        return dict(row) if row else {}

    async def remove_track(self, user_id: UUID, playlist_id: UUID, track_id: UUID) -> None:
        await self._owned(user_id, playlist_id)
        await self.database.execute(
            """
            DELETE FROM playlist_tracks
            WHERE id = $1 AND playlist_id = $2 AND user_id = $3
            """,
            track_id,
            playlist_id,
            user_id,
        )
        await self.database.execute("UPDATE playlists SET updated_at = now() WHERE id = $1", playlist_id)

    async def _owned(self, user_id: UUID, playlist_id: UUID) -> dict:
        row = await self.database.fetchrow("SELECT * FROM playlists WHERE id = $1", playlist_id)
        if not row:
            raise ResourceNotFound("Playlist was not found")
        if row["user_id"] != user_id:
            raise ForbiddenOperation("You do not own this playlist")
        return dict(row)
