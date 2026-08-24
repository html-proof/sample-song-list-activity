from uuid import UUID

from music_hub.database import Database
from music_hub.schemas.history import ListeningHistoryCreate, MusicEventCreate


class HistoryRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def add_listen(self, user_id: UUID, payload: ListeningHistoryCreate) -> dict:
        completion = (
            min(payload.played_ms / payload.duration_ms, 1.0)
            if payload.duration_ms else None
        )
        row = await self.database.fetchrow(
            """
            INSERT INTO listening_history (
                user_id, provider, song_id, seokey, song_name, artist_id, artist_name,
                album_id, album_name, language, artwork_url, duration_ms, played_ms,
                completion_percentage, source, started_at, completed_at, session_id
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                $14, $15, $16, $17, $18
            ) RETURNING *
            """,
            user_id,
            payload.provider,
            payload.song_id,
            payload.seokey,
            payload.song_name,
            payload.artist_id,
            payload.artist_name,
            payload.album_id,
            payload.album_name,
            payload.language,
            payload.artwork_url,
            payload.duration_ms,
            payload.played_ms,
            completion,
            payload.source,
            payload.started_at,
            payload.completed_at,
            payload.session_id,
        )
        return dict(row) if row else {}

    async def add_event(self, user_id: UUID, payload: MusicEventCreate) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO music_events (
                user_id, event_type, provider, song_id, artist_id, album_id,
                language, source, position_ms, session_id, idempotency_key, metadata
            ) VALUES ($1, $2::music_event_type, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::jsonb)
            ON CONFLICT (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL
            DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
            RETURNING *
            """,
            user_id,
            payload.event_type.value,
            payload.provider,
            payload.song_id,
            payload.artist_id,
            payload.album_id,
            payload.language,
            payload.source,
            payload.position_ms,
            payload.session_id,
            payload.idempotency_key,
            payload.metadata,
        )
        return dict(row) if row else {}

    async def add_search(
        self,
        user_id: UUID,
        query: str,
        result_type: str | None = None,
        clicked_result_id: str | None = None,
    ) -> None:
        normalized = " ".join(query.casefold().split())
        await self.database.execute(
            """
            INSERT INTO search_history
                (user_id, query, normalized_query, result_type, clicked_result_id)
            VALUES ($1, $2, $3, $4, $5)
            """,
            user_id,
            query,
            normalized,
            result_type,
            clicked_result_id,
        )

    async def recent(self, user_id: UUID, limit: int = 25) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT * FROM (
                SELECT DISTINCT ON (provider, song_id) *
                FROM listening_history
                WHERE user_id = $1
                ORDER BY provider, song_id, created_at DESC
            ) latest
            ORDER BY created_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
        )
        return [dict(row) for row in rows]

    async def continue_listening(self, user_id: UUID, limit: int = 10) -> list[dict]:
        rows = await self.database.fetch(
            """
            SELECT * FROM (
                SELECT DISTINCT ON (provider, song_id) *
                FROM listening_history
                WHERE user_id = $1
                  AND played_ms > 0
                  AND COALESCE(completion_percentage, 0) < 0.9
                ORDER BY provider, song_id, created_at DESC
            ) latest
            ORDER BY created_at DESC
            LIMIT $2
            """,
            user_id,
            limit,
        )
        return [dict(row) for row in rows]
