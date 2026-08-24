from uuid import UUID

from music_hub.cache import RedisCache
from music_hub.repositories.library import LibraryRepository
from music_hub.schemas.library import FollowedArtistCreate, LikedSongCreate


class LibraryService:
    def __init__(
        self,
        repository: LibraryRepository,
        cache: RedisCache | None = None,
    ) -> None:
        self.repository = repository
        self.cache = cache

    async def like(self, user_id: UUID, payload: LikedSongCreate) -> dict:
        result = await self.repository.like_song(user_id, payload)
        await self._invalidate_recommendations(user_id)
        return result

    async def unlike(self, user_id: UUID, provider: str, song_id: str) -> None:
        await self.repository.unlike_song(user_id, provider, song_id)
        await self._invalidate_recommendations(user_id)

    async def liked(self, user_id: UUID, limit: int) -> list[dict]:
        return await self.repository.liked_songs(user_id, limit)

    async def follow(self, user_id: UUID, payload: FollowedArtistCreate) -> dict:
        result = await self.repository.follow_artist(user_id, payload)
        await self._invalidate_recommendations(user_id)
        return result

    async def unfollow(self, user_id: UUID, provider: str, artist_id: str) -> None:
        await self.repository.unfollow_artist(user_id, provider, artist_id)
        await self._invalidate_recommendations(user_id)

    async def followed(self, user_id: UUID, limit: int) -> list[dict]:
        return await self.repository.followed_artists(user_id, limit)

    async def _invalidate_recommendations(self, user_id: UUID) -> None:
        if self.cache is not None:
            await self.cache.delete_pattern(f"recommendations:{user_id}:*")
