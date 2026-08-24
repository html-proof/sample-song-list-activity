import logging

from music_hub.cache.redis import RedisCache
from music_hub.lyrics.models import LyricsDocument, LyricsStatus, SongIdentity


logger = logging.getLogger("music_hub.lyrics")

# Bump when the document shape or parsing rules change, so stale payloads from
# an older build are never deserialized into the new contract.
CACHE_SCHEMA_VERSION = "1"


class LyricsCache:
    """Two-tier TTL cache keyed by song id *and* recording identity.

    Successful lookups are cheap to keep for a long time; misses are retried
    sooner because a lyrics database gains entries over time.
    """

    def __init__(
        self,
        cache: RedisCache,
        content_ttl: int = 604_800,
        negative_ttl: int = 3_600,
    ) -> None:
        self._cache = cache
        self._content_ttl = content_ttl
        self._negative_ttl = negative_ttl

    @staticmethod
    def key(identity: SongIdentity) -> str:
        # The identity hash is part of the key, so a song id that starts
        # pointing at a different recording misses instead of serving the old
        # lyrics.
        return f"lyrics:v{CACHE_SCHEMA_VERSION}:{identity.song_id}:{identity.identity_hash()}"

    async def get(self, identity: SongIdentity) -> LyricsDocument | None:
        try:
            payload = await self._cache.get_json(self.key(identity))
        except Exception:
            logger.warning("Lyrics cache read failed", exc_info=True)
            return None
        if not isinstance(payload, dict):
            return None
        try:
            document = LyricsDocument.from_dict(payload)
        except (ValueError, TypeError):
            logger.warning("Discarding unreadable cached lyrics payload")
            return None
        # Defensive: never serve a cached document that belongs elsewhere.
        if document.song_identity_hash and document.song_identity_hash != identity.identity_hash():
            return None
        return document

    async def put(self, identity: SongIdentity, document: LyricsDocument) -> None:
        # Transient failures must not be cached, or a blip becomes an hour of
        # missing lyrics.
        if document.status is LyricsStatus.TEMPORARY_ERROR:
            return
        stable = document.status in (
            LyricsStatus.AVAILABLE,
            LyricsStatus.PLAIN_ONLY,
            LyricsStatus.INSTRUMENTAL,
        )
        ttl = self._content_ttl if stable else self._negative_ttl
        try:
            await self._cache.set_json(self.key(identity), document.to_dict(), ttl)
        except Exception:
            logger.warning("Lyrics cache write failed", exc_info=True)

    async def invalidate(self, identity: SongIdentity) -> None:
        try:
            await self._cache.delete(self.key(identity))
        except Exception:
            logger.warning("Lyrics cache invalidation failed", exc_info=True)
