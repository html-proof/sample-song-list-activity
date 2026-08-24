from uuid import UUID

from music_hub.database import Database
from music_hub.schemas.library import FollowedArtistCreate, LikedSongCreate


class LibraryRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def like_song(self, user_id: UUID, item: LikedSongCreate) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO liked_songs
                (user_id, provider, song_id, seokey, song_name, artist_id, artist_name,
                 album_id, language, artwork_url)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            ON CONFLICT (user_id, provider, song_id) DO UPDATE
            SET seokey = EXCLUDED.seokey, song_name = EXCLUDED.song_name,
                artist_id = EXCLUDED.artist_id,
                artist_name = EXCLUDED.artist_name, album_id = EXCLUDED.album_id,
                language = EXCLUDED.language, artwork_url = EXCLUDED.artwork_url
            RETURNING *
            """,
            user_id,
            item.provider,
            item.song_id,
            item.seokey,
            item.song_name,
            item.artist_id,
            item.artist_name,
            item.album_id,
            item.language,
            item.artwork_url,
        )
        return dict(row) if row else {}

    async def unlike_song(self, user_id: UUID, provider: str, song_id: str) -> None:
        await self.database.execute(
            "DELETE FROM liked_songs WHERE user_id = $1 AND provider = $2 AND song_id = $3",
            user_id,
            provider,
            song_id,
        )

    async def liked_songs(self, user_id: UUID, limit: int = 100) -> list[dict]:
        rows = await self.database.fetch(
            "SELECT * FROM liked_songs WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
            user_id,
            limit,
        )
        return [dict(row) for row in rows]

    async def follow_artist(self, user_id: UUID, item: FollowedArtistCreate) -> dict:
        row = await self.database.fetchrow(
            """
            INSERT INTO followed_artists
                (user_id, provider, artist_id, artist_name, artwork_url, notifications_enabled)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (user_id, provider, artist_id) DO UPDATE
            SET artist_name = EXCLUDED.artist_name, artwork_url = EXCLUDED.artwork_url,
                notifications_enabled = EXCLUDED.notifications_enabled
            RETURNING *
            """,
            user_id,
            item.provider,
            item.artist_id,
            item.artist_name,
            item.artwork_url,
            item.notifications_enabled,
        )
        return dict(row) if row else {}

    async def unfollow_artist(self, user_id: UUID, provider: str, artist_id: str) -> None:
        await self.database.execute(
            "DELETE FROM followed_artists WHERE user_id = $1 AND provider = $2 AND artist_id = $3",
            user_id,
            provider,
            artist_id,
        )

    async def followed_artists(self, user_id: UUID, limit: int = 100) -> list[dict]:
        rows = await self.database.fetch(
            "SELECT * FROM followed_artists WHERE user_id = $1 ORDER BY followed_at DESC LIMIT $2",
            user_id,
            limit,
        )
        return [dict(row) for row in rows]
