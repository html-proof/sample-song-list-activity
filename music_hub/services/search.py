import asyncio
import hashlib
import re
from uuid import UUID

from music_hub.cache import RedisCache
from music_hub.config import Settings
from music_hub.providers.base import MusicProvider
from music_hub.repositories.history import HistoryRepository
from music_hub.services.settings import SettingsService


_SOUNDTRACK_HINTS = frozenset({"album", "film", "movie", "ost", "soundtrack"})
_TOKEN_PATTERN = re.compile(r"[\w]+", re.UNICODE)


class SearchService:
    def __init__(
        self,
        provider: MusicProvider,
        history: HistoryRepository,
        cache: RedisCache,
        settings: Settings,
        settings_repository: SettingsService | None = None,
    ) -> None:
        self.provider = provider
        self.history = history
        self.cache = cache
        self.settings = settings
        self.settings_repository = settings_repository

    async def _save_history(self, user_id: UUID) -> bool:
        if self.settings_repository is None:
            return True
        privacy = await self.settings_repository.get_group(user_id, "privacy")
        return bool(privacy["save_search_history"])

    async def record_event(
        self,
        user_id: UUID,
        query: str,
        result_type: str | None,
        clicked_result_id: str | None,
    ) -> bool:
        if not await self._save_history(user_id):
            return False
        await self.history.add_search(user_id, query, result_type, clicked_result_id)
        await self._invalidate_recommendations(user_id)
        return True

    async def search(self, user_id: UUID, query: str, result_type: str, limit: int) -> dict:
        normalized = " ".join(query.casefold().split())
        digest = hashlib.sha256(f"{result_type}:{normalized}:{limit}".encode()).hexdigest()
        cache_key = f"search:{digest}"
        cached = await self.cache.get_json(cache_key)
        if cached is not None:
            if await self._save_history(user_id):
                await self.history.add_search(user_id, query, result_type)
                await self._invalidate_recommendations(user_id)
            return await self._apply_content_settings(user_id, cached)

        if result_type == "songs":
            songs = await self.provider.search_songs(query, limit)
            if self._has_soundtrack_intent(query):
                try:
                    albums = await self.provider.search_albums(query, limit)
                except Exception:
                    albums = []
                songs = await self._promote_soundtrack_tracks(query, songs, albums, limit)
            result = {"songs": songs}
        elif result_type == "albums":
            result = {"albums": await self.provider.search_albums(query, limit)}
        elif result_type == "artists":
            result = {"artists": await self.provider.search_artists(query, limit)}
        else:
            responses = await asyncio.gather(
                self.provider.search_songs(query, limit),
                self.provider.search_albums(query, limit),
                self.provider.search_artists(query, limit),
                return_exceptions=True,
            )
            songs, albums, artists = [
                [] if isinstance(value, Exception) else value
                for value in responses
            ]
            songs = await self._promote_soundtrack_tracks(query, songs, albums, limit)
            result = {"songs": songs, "albums": albums, "artists": artists}

        cache_ttl = (
            min(self.settings.search_cache_ttl, 60)
            if result_type in {"all", "songs"}
            else self.settings.search_cache_ttl
        )
        await self.cache.set_json(cache_key, result, cache_ttl)
        if await self._save_history(user_id):
            await self.history.add_search(user_id, query, result_type)
            await self._invalidate_recommendations(user_id)
        return await self._apply_content_settings(user_id, result)

    async def _invalidate_recommendations(self, user_id: UUID) -> None:
        await self.cache.delete_pattern(f"recommendations:{user_id}:*")

    async def _apply_content_settings(self, user_id: UUID, result: dict) -> dict:
        if self.settings_repository is None:
            return result
        playback = await self.settings_repository.get_group(user_id, "playback")
        if playback["explicit_content"]:
            return result
        filtered: dict = {}
        for key, value in result.items():
            if isinstance(value, list):
                filtered[key] = [item for item in value if not self._is_explicit(item)]
            else:
                filtered[key] = value
        return filtered

    @staticmethod
    def _is_explicit(item: object) -> bool:
        if not isinstance(item, dict):
            return False
        value = item.get("explicit_content", item.get("is_explicit", item.get("explicit")))
        return value is True or str(value).casefold() in {"1", "true", "yes", "explicit"}

    @staticmethod
    def _tokens(value: object) -> set[str]:
        return {
            token.casefold()
            for token in _TOKEN_PATTERN.findall(str(value or ""))
        }

    @classmethod
    def _has_soundtrack_intent(cls, query: str) -> bool:
        return bool(cls._tokens(query) & _SOUNDTRACK_HINTS)

    @classmethod
    def _matching_album(cls, query: str, albums: list[dict]) -> dict | None:
        query_tokens = cls._tokens(query) - _SOUNDTRACK_HINTS
        if not query_tokens:
            return None

        for album in albums:
            searchable = " ".join(
                str(album.get(field) or "")
                for field in ("title", "album", "artists", "language")
            )
            if query_tokens <= cls._tokens(searchable) and album.get("seokey"):
                return album
        return None

    async def _promote_soundtrack_tracks(
        self,
        query: str,
        songs: list[dict],
        albums: list[dict],
        limit: int,
    ) -> list[dict]:
        if not self._has_soundtrack_intent(query):
            return songs

        album = self._matching_album(query, albums)
        if album is None:
            return songs

        try:
            details = await self.provider.get_album(str(album["seokey"]))
        except Exception:
            return songs
        tracks = details.get("tracks") if isinstance(details, dict) else None
        if not isinstance(tracks, list):
            return songs

        output: list[dict] = []
        seen: set[str] = set()
        for item in [*tracks, *songs]:
            if not isinstance(item, dict):
                continue
            identity = str(
                item.get("provider_id")
                or item.get("track_id")
                or item.get("song_id")
                or item.get("seokey")
                or ""
            )
            if not identity or identity in seen:
                continue
            seen.add(identity)
            output.append(item)
            if len(output) >= limit:
                break
        return output
