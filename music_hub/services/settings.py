from typing import Any
from uuid import UUID

from pydantic import BaseModel

from music_hub.cache import RedisCache
from music_hub.repositories.settings import SettingsRepository
from music_hub.schemas.settings import AppSettings


class SettingsService:
    cache_ttl = 300

    def __init__(self, repository: SettingsRepository, cache: RedisCache) -> None:
        self.repository = repository
        self.cache = cache

    def _key(self, user_id: UUID) -> str:
        return f"settings:{user_id}"

    async def get_all(self, user_id: UUID) -> AppSettings:
        cached = await self.cache.get_json(self._key(user_id))
        if isinstance(cached, dict):
            return AppSettings.model_validate(cached)
        settings = await self.repository.get_all(user_id)
        await self.cache.set_json(self._key(user_id), settings.model_dump(), self.cache_ttl)
        return settings

    async def get_group(self, user_id: UUID, group: str) -> dict[str, Any]:
        settings = await self.get_all(user_id)
        value = getattr(settings, group)
        return value.model_dump()

    async def update(self, user_id: UUID, group: str, payload: BaseModel) -> dict[str, Any]:
        values = payload.model_dump(exclude_unset=True)
        updated = await self.repository.update_group(user_id, group, values)
        if group == "notifications" and "enabled" in values:
            await self.repository.set_device_notifications(
                user_id,
                bool(values["enabled"]),
            )
        await self.cache.delete(self._key(user_id))
        if group in {"general", "recommendations", "privacy"}:
            await self.invalidate_recommendations(user_id)
        return updated

    async def reset(self, user_id: UUID) -> AppSettings:
        await self.repository.reset(user_id)
        await self.cache.delete(self._key(user_id))
        await self.invalidate_recommendations(user_id)
        return await self.get_all(user_id)

    async def clear_history(self, user_id: UUID, kind: str) -> None:
        await self.repository.clear_history(user_id, kind)
        await self.invalidate_recommendations(user_id)

    async def reset_recommendations(self, user_id: UUID) -> None:
        await self.repository.reset_recommendations(user_id)
        await self.invalidate_recommendations(user_id)

    async def invalidate_recommendations(self, user_id: UUID) -> None:
        await self.cache.delete_pattern(f"recommendations:{user_id}:*")
        await self.cache.delete(f"seen:{user_id}")
