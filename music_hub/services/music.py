from music_hub.cache import RedisCache
from music_hub.config import Settings
from music_hub.providers.base import MusicProvider


class MusicService:
    def __init__(self, provider: MusicProvider, cache: RedisCache, settings: Settings) -> None:
        self.provider = provider
        self.cache = cache
        self.settings = settings

    async def song(self, seokey: str) -> dict:
        key = f"song:{self.provider.name}:{seokey}"
        cached = await self.cache.get_json(key)
        if cached is not None:
            return cached
        result = await self.provider.get_song(seokey)
        # Playback URLs are tokenized, so song objects are intentionally short lived.
        await self.cache.set_json(key, result, 60)
        return result

    async def album(self, seokey: str) -> dict:
        key = f"album:{self.provider.name}:{seokey}"
        cached = await self.cache.get_json(key)
        if cached is not None:
            return cached
        result = await self.provider.get_album(seokey)
        # The rich album payload includes tokenized track playback URLs.
        await self.cache.set_json(key, result, min(self.settings.album_cache_ttl, 60))
        return result

    async def artist(self, seokey: str, limit: int, page: int) -> dict:
        key = f"artist:{self.provider.name}:{seokey}:{limit}:{page}"
        cached = await self.cache.get_json(key)
        if cached is not None:
            return cached
        result = await self.provider.get_artist(seokey, limit, page)
        # Artist profiles include top tracks and therefore tokenized playback URLs.
        await self.cache.set_json(key, result, min(self.settings.artist_cache_ttl, 60))
        return result

    async def artist_tracks(self, artist_id: str, limit: int, page: int) -> dict:
        return await self.provider.get_artist_tracks(artist_id, limit, page)

    async def similar_artists(self, artist_id: str, limit: int) -> list[dict]:
        return await self.provider.get_similar_artists(artist_id, limit)

    async def similar_albums(self, album_id: str, limit: int) -> list[dict]:
        return await self.provider.get_similar_albums(album_id, limit)

    async def charts(self, limit: int) -> list[dict]:
        key = f"charts:{self.provider.name}:{limit}"
        cached = await self.cache.get_json(key)
        if cached is not None:
            return cached
        result = await self.provider.charts(limit)
        await self.cache.set_json(key, result, self.settings.trending_cache_ttl)
        return result

    async def trending(self, languages: list[str], limit: int) -> list[dict]:
        names = ",".join(sorted(language.casefold() for language in languages))
        key = f"trending:{self.provider.name}:{names}:{limit}"
        cached = await self.cache.get_json(key)
        if cached is not None:
            return cached
        result = await self.provider.trending(languages, limit)
        await self.cache.set_json(key, result, self.settings.trending_cache_ttl)
        return result

    async def new_releases(self, languages: list[str], limit: int) -> list[dict]:
        names = ",".join(sorted(language.casefold() for language in languages))
        key = f"new-releases:{self.provider.name}:{names}:{limit}"
        cached = await self.cache.get_json(key)
        if cached is not None:
            return cached
        result = await self.provider.new_releases(languages, limit)
        await self.cache.set_json(key, result, self.settings.new_releases_cache_ttl)
        return result

    async def provider_playlist(self, seokey: str) -> list[dict]:
        return await self.provider.get_provider_playlist(seokey)
