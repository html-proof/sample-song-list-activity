from uuid import UUID

from music_hub.cache import RedisCache
from music_hub.providers.base import MusicProvider
from music_hub.repositories.preferences import PreferenceRepository
from music_hub.schemas.users import (
    ArtistPreferencesUpdate,
    LanguagePreferencesUpdate,
    OnboardingRequest,
)


class OnboardingService:
    def __init__(
        self,
        preferences: PreferenceRepository,
        provider: MusicProvider,
        cache: RedisCache,
    ) -> None:
        self.preferences = preferences
        self.provider = provider
        self.cache = cache

    async def artists(self, query: str, limit: int) -> list[dict]:
        return await self.provider.search_artists(query, limit)

    async def suggested_artists(
        self,
        user_id: UUID,
        languages: list[str],
        limit: int = 20,
    ) -> list[dict]:
        """Artists to show before the user has searched for anything."""
        selected = [language.strip() for language in languages if language.strip()]
        if not selected:
            stored = await self.preferences.get_languages(user_id)
            selected = [str(item["language_code"]) for item in stored]
        key = f"suggested_artists:{','.join(sorted(selected)).casefold()}:{limit}"
        cached = await self.cache.get_json(key)
        if cached is not None:
            return cached
        result = await self.provider.suggested_artists(selected, limit)
        await self.cache.set_json(key, result, 900)
        return result

    async def complete(self, user_id: UUID, payload: OnboardingRequest) -> dict:
        await self.preferences.replace_onboarding(user_id, payload.languages, payload.artists)
        await self._invalidate(user_id)
        return await self.preferences.get_onboarding(user_id)

    async def update_languages(
        self,
        user_id: UUID,
        payload: LanguagePreferencesUpdate,
    ) -> dict:
        await self.preferences.replace_languages(user_id, payload.languages)
        await self._invalidate(user_id)
        return {"languages": await self.preferences.get_languages(user_id)}

    async def update_artists(
        self,
        user_id: UUID,
        payload: ArtistPreferencesUpdate,
    ) -> dict:
        await self.preferences.replace_artists(user_id, payload.artists)
        await self._invalidate(user_id)
        return {"artists": await self.preferences.get_artists(user_id)}

    async def _invalidate(self, user_id: UUID) -> None:
        await self.cache.delete_pattern(f"recommendations:{user_id}:*")
        await self.cache.delete(f"seen:{user_id}")
