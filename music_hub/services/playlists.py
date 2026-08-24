from uuid import UUID

from music_hub.repositories.playlists import PlaylistRepository
from music_hub.schemas.playlists import PlaylistCreate, PlaylistTrackCreate, PlaylistUpdate


class PlaylistService:
    def __init__(self, repository: PlaylistRepository) -> None:
        self.repository = repository

    async def create(self, user_id: UUID, payload: PlaylistCreate) -> dict:
        return await self.repository.create(user_id, payload)

    async def list(self, user_id: UUID) -> list[dict]:
        return await self.repository.list(user_id)

    async def get(self, user_id: UUID, playlist_id: UUID) -> dict:
        return await self.repository.get(user_id, playlist_id)

    async def update(self, user_id: UUID, playlist_id: UUID, payload: PlaylistUpdate) -> dict:
        return await self.repository.update(user_id, playlist_id, payload)

    async def delete(self, user_id: UUID, playlist_id: UUID) -> None:
        await self.repository.delete(user_id, playlist_id)

    async def add_track(self, user_id: UUID, playlist_id: UUID, payload: PlaylistTrackCreate) -> dict:
        return await self.repository.add_track(user_id, playlist_id, payload)

    async def remove_track(self, user_id: UUID, playlist_id: UUID, track_id: UUID) -> None:
        await self.repository.remove_track(user_id, playlist_id, track_id)
