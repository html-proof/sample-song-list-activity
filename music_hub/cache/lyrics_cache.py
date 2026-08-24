from music_hub.cache.redis import RedisCache
from music_hub.lyrics import LyricsDocument, LyricsStatus, SongIdentity


class LyricsCache:
    def __init__(self, cache: RedisCache, ttl: int, negative_ttl: int) -> None:
        self.cache = cache
        self.ttl = ttl
        self.negative_ttl = negative_ttl

    async def get(self, identity: SongIdentity) -> LyricsDocument | None:
        value = await self.cache.get_json(self._key(identity))
        if not isinstance(value, dict):
            return None
        return LyricsDocument.model_validate(value)

    async def put(self, identity: SongIdentity, document: LyricsDocument) -> None:
        stable = document.status in {
            LyricsStatus.AVAILABLE,
            LyricsStatus.PLAIN_ONLY,
            LyricsStatus.INSTRUMENTAL,
            LyricsStatus.UNSUPPORTED,
        }
        await self.cache.set_json(
            self._key(identity),
            document.model_dump(mode="json"),
            self.ttl if stable else self.negative_ttl,
        )

    @staticmethod
    def _key(identity: SongIdentity) -> str:
        return f"lyrics:{identity.identity_hash}"
