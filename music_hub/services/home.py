import asyncio
from uuid import UUID

from music_hub.errors import MusicHubError
from music_hub.providers.base import MusicProvider
from music_hub.recommendations.engine import RecommendationEngine
from music_hub.repositories.history import HistoryRepository
from music_hub.repositories.preferences import PreferenceRepository
from music_hub.schemas.recommendations import HomeResponse
from music_hub.services.music import MusicService
from music_hub.services.settings import SettingsService


class HomeService:
    def __init__(
        self,
        provider: MusicProvider,
        music: MusicService,
        recommendations: RecommendationEngine,
        history: HistoryRepository,
        preferences: PreferenceRepository,
        settings: SettingsService | None = None,
    ) -> None:
        self.provider = provider
        self.music = music
        self.recommendations = recommendations
        self.history = history
        self.preferences = preferences
        self.settings = settings

    async def build(self, user_id: UUID, cursor: str | None = None) -> HomeResponse:
        languages = await self.preferences.get_languages(user_id)
        language_names = [item["language_code"] for item in languages[:3]] or ["Hindi"]
        artists = await self.preferences.get_artists(user_id)
        results = await asyncio.gather(
            self.recommendations.recommend(user_id, cursor, 25),
            self._safe_provider(self.music.trending(language_names, 20)),
            self._safe_provider(self.music.new_releases(language_names, 20)),
            self.history.recent(user_id, 20),
            self.history.continue_listening(user_id, 10),
            self._recommended_artists(artists),
        )
        recommendations, trending, new_releases, recent, continue_listening, similar_artists = results
        if self.settings is not None:
            playback = await self.settings.get_group(user_id, "playback")
            if not playback["explicit_content"]:
                recommendations.data = self._without_explicit(recommendations.data)
                trending = self._without_explicit(trending)
                new_releases = self._without_explicit(new_releases)
                recent = self._without_explicit(recent)
                continue_listening = self._without_explicit(continue_listening)
        preferred_languages = {name.casefold() for name in language_names}
        because_you_like = [
            item for item in recommendations.data
            if set(item.get("recommendation_reasons", []))
            & {"selected_artist", "followed_artist", "liked_song", "from_selected_artist"}
        ][:10]
        language_mix = [
            item for item in recommendations.data
            if str(item.get("language") or "").casefold() in preferred_languages
        ][:10]
        return HomeResponse(
            continue_listening=continue_listening,
            recommended_for_you=recommendations.data,
            because_you_like=because_you_like,
            new_releases=new_releases,
            trending=trending,
            language_mix=language_mix,
            recently_played=recent,
            recommended_artists=similar_artists or artists[:10],
            next_cursor=recommendations.next_cursor,
        )

    @staticmethod
    async def _safe_provider(awaitable) -> list[dict]:
        try:
            return await awaitable
        except MusicHubError:
            return []

    async def _recommended_artists(self, artists: list[dict]) -> list[dict]:
        requests = [
            self.provider.get_similar_artists(str(item["provider_artist_id"]), 8)
            for item in artists[:2]
            if item.get("provider_artist_id")
        ]
        if not requests:
            return []
        results = await asyncio.gather(*requests, return_exceptions=True)
        output: list[dict] = []
        seen: set[str] = set()
        for result in results:
            if isinstance(result, Exception):
                continue
            for item in result:
                identity = str(item.get("provider_id") or item.get("artist_id") or item.get("seokey"))
                if identity and identity not in seen:
                    seen.add(identity)
                    output.append(item)
        return output[:10]

    @staticmethod
    def _without_explicit(items: list[dict]) -> list[dict]:
        output: list[dict] = []
        for item in items:
            value = item.get(
                "explicit_content",
                item.get("is_explicit", item.get("explicit")),
            )
            explicit = value is True or str(value).casefold() in {
                "1",
                "true",
                "yes",
                "explicit",
            }
            if not explicit:
                output.append(item)
        return output
