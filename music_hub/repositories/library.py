import json

from music_hub.database import Database
from music_hub.schemas.library import FollowedArtistCreate, LikedSongCreate


class LibraryRepository:
    def __init__(self, database: Database) -> None:
        self.database = database

    async def like_song(self, user_id: str, item: LikedSongCreate) -> dict:
        seokey = item.seokey or item.song_id
        track = {
            "seokey":      seokey,
            "track_id":    item.song_id,
            "title":       item.song_name,
            "artist":      item.artist_name,
            "artists":     [item.artist_name] if item.artist_name else [],
            "artist_ids":  [item.artist_id] if item.artist_id else [],
            "album_id":    item.album_id,
            "language":    item.language,
            "images":      {"urls": {"large_artwork": item.artwork_url}} if item.artwork_url else {},
            "image_url":   item.artwork_url,
            "imageUrl":    item.artwork_url,
        }

        async with self.database.transaction() as conn:
            row = await conn.fetchrow(
                """
                INSERT INTO user_favorites (uid, seokey, track, favorited_at)
                VALUES ($1, $2, $3::jsonb, now())
                ON CONFLICT (uid, seokey) DO UPDATE
                SET track = EXCLUDED.track, favorited_at = now()
                RETURNING *
                """,
                user_id,
                seokey,
                json.dumps(track),
            )
            # Mirror to user_liked_songs
            await conn.execute(
                """
                INSERT INTO user_liked_songs (user_id, song_id, song, created_at)
                VALUES ($1, $2, $3::jsonb, now())
                ON CONFLICT (user_id, song_id) DO UPDATE SET song = EXCLUDED.song
                """,
                user_id,
                seokey,
                json.dumps(track),
            )

        return dict(row) if row else {}

    async def unlike_song(self, user_id: str, provider: str, song_id: str) -> None:
        async with self.database.transaction() as conn:
            await conn.execute(
                "DELETE FROM user_favorites WHERE uid = $1 AND seokey = $2",
                user_id,
                song_id,
            )
            await conn.execute(
                "DELETE FROM user_liked_songs WHERE user_id = $1 AND song_id = $2",
                user_id,
                song_id,
            )

    async def liked_songs(self, user_id: str, limit: int = 100) -> list[dict]:
        rows = await self.database.fetch(
            "SELECT * FROM user_favorites WHERE uid = $1 ORDER BY favorited_at DESC LIMIT $2",
            user_id,
            limit,
        )
        return [dict(row) for row in rows]

    async def follow_artist(self, user_id: str, item: FollowedArtistCreate) -> dict:
        seokey = item.artist_id
        artist = {
            "seokey":     seokey,
            "name":       item.artist_name,
            "image_url":  item.artwork_url,
            "imageUrl":   item.artwork_url,
        }
        row = await self.database.fetchrow(
            """
            INSERT INTO user_followed_artists (uid, seokey, artist, followed_at)
            VALUES ($1, $2, $3::jsonb, now())
            ON CONFLICT (uid, seokey) DO UPDATE
            SET artist = EXCLUDED.artist, followed_at = now()
            RETURNING *
            """,
            user_id,
            seokey,
            json.dumps(artist),
        )
        return dict(row) if row else {}

    async def unfollow_artist(self, user_id: str, provider: str, artist_id: str) -> None:
        await self.database.execute(
            "DELETE FROM user_followed_artists WHERE uid = $1 AND seokey = $2",
            user_id,
            artist_id,
        )

    async def followed_artists(self, user_id: str, limit: int = 100) -> list[dict]:
        rows = await self.database.fetch(
            "SELECT * FROM user_followed_artists WHERE uid = $1 ORDER BY followed_at DESC LIMIT $2",
            user_id,
            limit,
        )
        return [dict(row) for row in rows]
