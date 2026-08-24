from uuid import UUID

from music_hub.cache import RedisCache
from music_hub.repositories.history import HistoryRepository
from music_hub.schemas.history import ListeningHistoryCreate, MusicEventCreate
from music_hub.services.settings import SettingsService


class HistoryService:
    def __init__(
        self,
        repository: HistoryRepository,
        settings: SettingsService | None = None,
        cache: RedisCache | None = None,
    ) -> None:
        self.repository = repository
        self.settings = settings
        self.cache = cache

    async def record_listen(self, user_id: UUID, payload: ListeningHistoryCreate) -> dict:
        if self.settings is not None:
            privacy = await self.settings.get_group(user_id, "privacy")
            if not privacy["save_listening_history"]:
                return {"stored": False, "reason": "listening_history_disabled"}
        result = await self.repository.add_listen(user_id, payload)
        await self._invalidate_recommendations(user_id)
        return result

    async def record_event(self, user_id: UUID, payload: MusicEventCreate) -> dict:
        if self.settings is not None:
            privacy = await self.settings.get_group(user_id, "privacy")
            if not privacy["analytics_enabled"]:
                return {"stored": False, "reason": "analytics_disabled"}
        result = await self.repository.add_event(user_id, payload)
        await self._invalidate_recommendations(user_id)
        return result

    async def recent(self, user_id: UUID, limit: int) -> list[dict]:
        return await self.repository.recent(user_id, limit)

    async def continue_listening(self, user_id: UUID, limit: int) -> list[dict]:
        return await self.repository.continue_listening(user_id, limit)

    async def _invalidate_recommendations(self, user_id: UUID) -> None:
        if self.cache is not None:
            await self.cache.delete_pattern(f"recommendations:{user_id}:*")
