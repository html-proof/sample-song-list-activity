import asyncio
import hashlib
import re
from uuid import UUID

from music_hub.cache import RedisCache
from music_hub.config import Settings
from music_hub.providers.base import MusicProvider
from music_hub.repositories.history import HistoryRepository
from music_hub.search import (
    deduplicate,
    detect_intent,
    mark_requested_album_track,
    normalize,
    rank_albums,
    rank_artists,
    rank_songs,
)
from music_hub.services.settings import SettingsService


_SOUNDTRACK_HINTS = frozenset({"album", "film", "movie", "ost", "soundtrack"})
_TOKEN_PATTERN = re.compile(r"[\w]+", re.UNICODE)

#: Providers are asked for more rows than the caller wants so that ranking has
#: something to choose from. Trusting the provider's own top-N would let the
#: exact match fall outside the window before it is ever scored.
_OVERFETCH_FACTOR = 3
_MAX_OVERFETCH = 60


class SearchService:
    """Answers what the user typed.

    Deliberately independent of the recommendation engine: no listening
    history, affinity, or ML score takes part in search ranking. Search
    ordering is a pure function of the query and the provider metadata.
    """

    def __init__(
        self,
        provider: MusicProvider,
        history: HistoryRepository,
        cache: RedisCache,
        settings: Settings,
        settings_repository: SettingsService | None = None,
        providers: list[MusicProvider] | None = None,
    ) -> None:
        self.provider = provider
        #: Every provider queried in parallel and merged. Adding a second
        #: catalogue (JioSaavn) means appending its adapter here.
        self.providers = providers or [provider]
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

    # -- fan-out ----------------------------------------------------------

    @staticmethod
    def _merge(responses: list) -> list[dict]:
        merged: list[dict] = []
        for response in responses:
            if isinstance(response, Exception) or not isinstance(response, list):
                continue
            merged.extend(item for item in response if isinstance(item, dict))
        return merged

    def _fetch_limit(self, limit: int) -> int:
        return min(max(limit * _OVERFETCH_FACTOR, 30), _MAX_OVERFETCH)

    async def _fetch(self, method: str, query: str, limit: int) -> list[dict]:
        responses = await asyncio.gather(
            *[getattr(provider, method)(query, limit) for provider in self.providers],
            return_exceptions=True,
        )
        return self._merge(list(responses))

    # -- search -----------------------------------------------------------

    async def search(self, user_id: UUID, query: str, result_type: str, limit: int) -> dict:
        normalized = normalize(query)
        digest = hashlib.sha256(f"{result_type}:{normalized}:{limit}".encode()).hexdigest()
        cache_key = f"search:{digest}"
        cached = await self.cache.get_json(cache_key)
        if cached is not None:
            if await self._save_history(user_id):
                await self.history.add_search(user_id, query, result_type)
                await self._invalidate_recommendations(user_id)
            return await self._apply_content_settings(user_id, cached)

        result = await self._build(query, result_type, limit)

        await self.cache.set_json(cache_key, result, self._cache_ttl())
        if await self._save_history(user_id):
            await self.history.add_search(user_id, query, result_type)
            await self._invalidate_recommendations(user_id)
        return await self._apply_content_settings(user_id, result)

    async def _build(self, query: str, result_type: str, limit: int) -> dict:
        detected = detect_intent(query)
        song_limit = self._fetch_limit(limit)

        if result_type == "songs":
            songs = await self._fetch("search_songs", query, song_limit)
            if self._has_soundtrack_intent(query):
                try:
                    albums = await self.provider.search_albums(query, limit)
                except Exception:
                    albums = []
                songs = await self._promote_soundtrack_tracks(query, songs, albums, song_limit)
            return {"songs": rank_songs(deduplicate(songs), query, detected, limit)}

        if result_type == "albums":
            albums = await self._fetch("search_albums", query, limit)
            return {"albums": rank_albums(deduplicate(albums, _album_identity), query, limit)}

        if result_type == "artists":
            artists = await self._fetch("search_artists", query, limit)
            return {"artists": rank_artists(deduplicate(artists, _artist_identity), query, limit)}

        songs, albums, artists = await asyncio.gather(
            self._fetch("search_songs", query, song_limit),
            self._fetch("search_albums", query, limit),
            self._fetch("search_artists", query, limit),
        )
        songs = await self._promote_soundtrack_tracks(query, songs, albums, song_limit)
        # Songs are ranked on their own so that an artist or album match can
        # never push the exact song the user asked for further down the list.
        return {
            "songs": rank_songs(deduplicate(songs), query, detected, limit),
            "albums": rank_albums(deduplicate(albums, _album_identity), query, limit),
            "artists": rank_artists(deduplicate(artists, _artist_identity), query, limit),
        }

    def _cache_ttl(self) -> int:
        """Search responses are cached only long enough to absorb keystrokes."""
        return max(30, min(self.settings.search_cache_ttl, 60))

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

        # Tracks of the album the query named are the answer to that query, so
        # they are flagged for the ranker instead of relying on title text.
        promoted = [
            mark_requested_album_track(track)
            for track in tracks
            if isinstance(track, dict)
        ]

        output: list[dict] = []
        seen: set[str] = set()
        for item in [*promoted, *songs]:
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


def _album_identity(album: dict) -> tuple[str, str, str]:
    return (normalize(album.get("title")), normalize(album.get("artists")), "")


def _artist_identity(artist: dict) -> tuple[str, str, str]:
    return (normalize(artist.get("name")), "", "")
