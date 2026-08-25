from music_hub.cache.redis import RedisCache
from music_hub.lyrics import LyricsDocument, LyricsStatus


# Bumped whenever the stored document shape or the matching rules change, so a
# deploy cannot serve documents produced by the previous algorithm.
CACHE_VERSION = "v3"


class LyricsCache:
    """Redis-backed lyrics store keyed on the catalogue's own song id.

    The key deliberately excludes the request metadata: the same track must hit
    the same entry whether the lookup was driven by a client hint or by a
    catalogue fetch, otherwise every playback path would miss the cache and
    re-query the provider.
    """

    def __init__(self, cache: RedisCache, ttl: int, negative_ttl: int) -> None:
        self.cache = cache
        self.ttl = ttl
        self.negative_ttl = negative_ttl

    async def get(self, song_id: str) -> LyricsDocument | None:
        value = await self.cache.get_json(self.key(song_id))
        if not isinstance(value, dict):
            return None
        return LyricsDocument.model_validate(value)

    async def put(self, song_id: str, document: LyricsDocument) -> None:
        stable = document.status in {
            LyricsStatus.AVAILABLE,
            LyricsStatus.PLAIN_ONLY,
            LyricsStatus.INSTRUMENTAL,
            LyricsStatus.UNSUPPORTED,
        }
        await self.cache.set_json(
            self.key(song_id),
            document.model_dump(mode="json"),
            self.ttl if stable else self.negative_ttl,
        )

    @staticmethod
    def key(song_id: str) -> str:
        return f"lyrics:{CACHE_VERSION}:{song_id}"
