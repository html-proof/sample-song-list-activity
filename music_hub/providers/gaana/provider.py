import asyncio

from api.gaanapy import GaanaPy
from music_hub.errors import ProviderUnavailable, ResourceNotFound
from music_hub.providers.base import MusicProvider


class GaanaProvider(MusicProvider):
    """Compatibility adapter that keeps the legacy GaanaPy code provider-only."""

    name = "gaana"

    def __init__(self) -> None:
        self.client = GaanaPy()

    async def close(self) -> None:
        await self.client.aiohttp.close()

    @staticmethod
    def _list(result: object, resource: str) -> list[dict]:
        if isinstance(result, dict) and "error" in result:
            raise ResourceNotFound(f"No {resource} results were found")
        if not isinstance(result, list):
            raise ProviderUnavailable(f"Gaana returned an invalid {resource} response")
        return [item for item in result if isinstance(item, dict) and "error" not in item]

    @classmethod
    def _one(cls, result: object, resource: str) -> dict:
        items = cls._list(result, resource)
        if not items:
            raise ResourceNotFound(f"The requested {resource} was not found")
        return items[0]

    @staticmethod
    def _identity(item: dict) -> str:
        return str(
            item.get("track_id")
            or item.get("artist_id")
            or item.get("album_id")
            or item.get("playlist_id")
            or item.get("seokey")
            or ""
        )

    @classmethod
    def _decorate(cls, item: dict, kind: str | None = None) -> dict:
        decorated = dict(item)
        decorated.setdefault("provider", "gaana")
        decorated.setdefault("provider_id", cls._identity(item))
        # The content type is stamped at the boundary where it is still known
        # for certain. Everything downstream reads this field instead of
        # guessing from which keys happen to be present -- albums and songs
        # both carry an artist, playlists and albums both carry a track count.
        if kind is not None:
            decorated["type"] = kind
        return decorated

    @classmethod
    def _deduplicate(cls, items: list[dict], limit: int, kind: str | None = None) -> list[dict]:
        output: list[dict] = []
        seen: set[str] = set()
        for item in items:
            decorated = cls._decorate(item, kind)
            identity = decorated.get("provider_id") or decorated.get("seokey")
            if not identity or identity in seen:
                continue
            seen.add(str(identity))
            output.append(decorated)
            if len(output) >= limit:
                break
        return output

    async def search_songs(self, query: str, limit: int = 10) -> list[dict]:
        result = await self.client.search_songs(query, limit)
        return self._deduplicate(self._list(result, "song"), limit, "song")

    async def search_albums(self, query: str, limit: int = 10) -> list[dict]:
        result = await self.client.search_albums(query, limit)
        return self._deduplicate(self._list(result, "album"), limit, "album")

    async def search_artists(self, query: str, limit: int = 10) -> list[dict]:
        result = await self.client.search_artists(query, limit)
        return self._deduplicate(self._list(result, "artist"), limit, "artist")

    async def search_playlists(self, query: str, limit: int = 10) -> list[dict]:
        result = await self.client.search_playlists(query, limit)
        return self._deduplicate(self._list(result, "playlist"), limit, "playlist")

    async def get_song(self, seokey: str) -> dict:
        return self._decorate(self._one(await self.client.get_track_info([seokey]), "song"), "song")

    async def get_album(self, seokey: str) -> dict:
        album = self._one(await self.client.get_album_info([seokey], True), "album")
        return self._decorate(album, "album")

    async def get_artist(self, seokey: str, limit: int = 10, page: int = 1) -> dict:
        result = await self.client.get_artist_info([seokey], True, limit, page)
        return self._decorate(self._one(result, "artist"), "artist")

    async def get_artist_tracks(self, artist_id: str, limit: int = 25, page: int = 1) -> dict:
        result = await self.client.get_artist_tracks(artist_id, limit, page)
        if isinstance(result, dict) and "error" in result:
            raise ResourceNotFound("No artist tracks were found")
        if not isinstance(result, dict):
            raise ProviderUnavailable("Gaana returned an invalid artist-track response")
        tracks = result.get("tracks") or []
        return {
            "tracks": self._deduplicate(
                [item for item in tracks if isinstance(item, dict)], limit, "song"
            ),
            "total": int(result.get("total") or len(tracks)),
        }

    async def get_similar_artists(self, artist_id: str, limit: int = 10) -> list[dict]:
        result = await self.client.get_similar_artists(artist_id, limit)
        return self._deduplicate(self._list(result, "similar artist"), limit, "artist")

    async def get_similar_albums(self, album_id: str, limit: int = 10) -> list[dict]:
        result = await self.client.get_similar_albums(album_id, limit)
        return self._deduplicate(self._list(result, "similar album"), limit, "album")

    async def trending(self, languages: list[str], limit: int = 25) -> list[dict]:
        requested = languages or ["Hindi"]
        results = await asyncio.gather(
            *[self.client.get_trending(language, limit) for language in requested],
            return_exceptions=True,
        )
        items: list[dict] = []
        for result in results:
            if isinstance(result, list):
                items.extend(item for item in result if isinstance(item, dict))
        if not items:
            raise ResourceNotFound("No trending songs were found")
        return self._deduplicate(items, limit)

    async def new_releases(self, languages: list[str], limit: int = 25) -> list[dict]:
        requested = languages or ["Hindi"]
        results = await asyncio.gather(
            *[self.client.get_new_releases(language, limit) for language in requested],
            return_exceptions=True,
        )
        items: list[dict] = []
        for result in results:
            if not isinstance(result, dict) or "error" in result:
                continue
            for group in ("tracks", "albums"):
                values = result.get(group)
                if isinstance(values, list):
                    items.extend(item for item in values if isinstance(item, dict))
        if not items:
            raise ResourceNotFound("No new releases were found")
        return self._deduplicate(items, limit)

    async def charts(self, limit: int = 10) -> list[dict]:
        return self._deduplicate(self._list(await self.client.get_charts(limit), "chart"), limit)

    async def get_provider_playlist(self, seokey: str) -> list[dict]:
        result = await self.client.get_playlist_info(seokey)
        # The rows are the playlist's tracks, not playlists.
        return self._deduplicate(self._list(result, "playlist"), 500, "song")
