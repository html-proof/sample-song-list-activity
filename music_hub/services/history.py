from uuid import UUID

from music_hub.repositories.history import HistoryRepository
from music_hub.schemas.history import ListeningHistoryCreate, MusicEventCreate
from music_hub.services.settings import SettingsService


class HistoryService:
    def __init__(
        self,
        repository: HistoryRepository,
        settings: SettingsService | None = None,
    ) -> None:
        self.repository = repository
        self.settings = settings

    async def record_listen(self, user_id: UUID, payload: ListeningHistoryCreate) -> dict:
        if self.settings is not None:
            privacy = await self.settings.get_group(user_id, "privacy")
            if not privacy["save_listening_history"]:
                return {"stored": False, "reason": "listening_history_disabled"}
        return await self.repository.add_listen(user_id, payload)

    async def record_event(self, user_id: UUID, payload: MusicEventCreate) -> dict:
        if self.settings is not None:
            privacy = await self.settings.get_group(user_id, "privacy")
            if not privacy["analytics_enabled"]:
                return {"stored": False, "reason": "analytics_disabled"}
        return await self.repository.add_event(user_id, payload)

    async def recent(self, user_id: UUID, limit: int) -> list[dict]:
        return await self.repository.recent(user_id, limit)

    async def continue_listening(self, user_id: UUID, limit: int) -> list[dict]:
        return await self.repository.continue_listening(user_id, limit)
