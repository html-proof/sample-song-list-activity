import json

from music_hub.database import Database
from music_hub.schemas.history import ListeningHistoryCreate, MusicEventCreate


class HistoryRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def add_listen(self, user_id: str, payload: ListeningHistoryCreate) -> dict:
        completion = (
            min(payload.played_ms / payload.duration_ms, 1.0)
            if payload.duration_ms else None
        )
        event = {
            "seokey":      payload.seokey or payload.song_id,
            "track_id":    payload.song_id,
            "title":       payload.song_name,
            "artists":     [payload.artist_name] if payload.artist_name else [],
            "artist_ids":  [payload.artist_id] if payload.artist_id else [],
            "album":       payload.album_name,
            "album_id":    payload.album_id,
            "language":    payload.language,
            "images":      {"urls": {"large_artwork": payload.artwork_url}} if payload.artwork_url else {},
            "source":      payload.source or "app",
            "played_seconds": payload.played_ms // 1000 if payload.played_ms else 0,
            "duration":    payload.duration_ms // 1000 if payload.duration_ms else None,
            "completed":   (completion or 0) >= 0.9,
        }

        async with self.database.transaction() as conn:
            # Write to user_history (legacy JSONB event store)
            history_row = await conn.fetchrow(
                """
                INSERT INTO user_history (uid, event, played_at)
                VALUES ($1, $2::jsonb, COALESCE($3, now()))
                RETURNING *
                """,
                user_id,
                json.dumps(event),
                payload.started_at,
            )

            # Write to playback_history (structured analytics)
            await conn.execute(
                """
                INSERT INTO playback_history (
                    user_id, song_id, artist_id, album_id,
                    started_at, ended_at, duration_ms, position_ms,
                    completion_percentage, source, metadata
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb)
                """,
                user_id,
                payload.seokey or payload.song_id,
                payload.artist_id or "",
                payload.album_id or "",
                payload.started_at,
                payload.completed_at,
                payload.duration_ms or 0,
                payload.played_ms,
                (completion or 0) * 100,
                payload.source or "app",
                json.dumps(event),
            )

        return dict(history_row) if history_row else {}

    async def add_event(self, user_id: str, payload: MusicEventCreate) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO user_events (
                user_id, event_type, song_id, artist_id, album_id,
                position_ms, source, payload, created_at
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, now())
            RETURNING *
            """,
            user_id,
            payload.event_type.value,
            payload.song_id,
            payload.artist_id,
            payload.album_id,
            payload.position_ms,
            payload.source,
            json.dumps(payload.metadata),
        )
        return dict(row) if row else {}

    async def add_search(
        self,
        user_id: str,
        query: str,
        result_type: str | None = None,
        clicked_result_id: str | None = None,
    ) -> None:
        item = {"clicked_id": clicked_result_id} if clicked_result_id else {}
        await self.database.execute(
            """
            INSERT INTO recent_searches (uid, query, result_type, item)
            VALUES ($1, $2, $3, $4::jsonb)
            """,
            user_id,
            query,
            result_type,
            json.dumps(item),
        )

    async def recent(self, user_id: str, limit: int = 25) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT DISTINCT ON (event->>'seokey') *
            FROM user_history
            WHERE uid = $1
              AND event->>'seokey' IS NOT NULL
            ORDER BY event->>'seokey', played_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
        )
        return [dict(row) for row in rows]

    async def continue_listening(self, user_id: str, limit: int = 10) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT DISTINCT ON (song_id) *
            FROM playback_history
            WHERE user_id = $1
              AND position_ms > 0
              AND COALESCE(completion_percentage, 0) < 90
            ORDER BY song_id, started_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
        )
        return [dict(row) for row in rows]
