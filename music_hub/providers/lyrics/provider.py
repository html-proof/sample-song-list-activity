import asyncio
import logging

import aiohttp

from music_hub.errors import ProviderUnavailable
from music_hub.lyrics.models import LyricsCandidate, SongIdentity
from music_hub.lyrics.normalizer import primary_artist, strip_noise
from music_hub.providers.lyrics.base import LyricsProvider


logger = logging.getLogger("music_hub.lyrics")

_BASE_URL = "https://lrclib.net/api"
_TIMEOUT = aiohttp.ClientTimeout(total=6, connect=3)
_SEARCH_LIMIT = 12


class LrclibProvider(LyricsProvider):
    """Community lyrics database with line-level LRC synchronization.

    Chosen over scraping lyric sites: it exposes a documented API, requires no
    key, and is intended for exactly this use. Swap this class for a licensed
    commercial provider without touching the service or matcher.
    """

    name = "lrclib"

    def __init__(self, user_agent: str = "MusicHub/1.0", timeout: float | None = None) -> None:
        self._user_agent = user_agent
        self._timeout = aiohttp.ClientTimeout(total=timeout, connect=3) if timeout else _TIMEOUT
        self._session: aiohttp.ClientSession | None = None
        self._lock = asyncio.Lock()

    async def _client(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            async with self._lock:
                if self._session is None or self._session.closed:
                    self._session = aiohttp.ClientSession(
                        timeout=self._timeout,
                        headers={"User-Agent": self._user_agent, "Accept": "application/json"},
                    )
        return self._session

    async def close(self) -> None:
        if self._session is not None and not self._session.closed:
            await self._session.close()
        self._session = None

    async def search(self, identity: SongIdentity) -> list[LyricsCandidate]:
        title = strip_noise(identity.title) or identity.title
        artist = primary_artist(identity.artist)
        if not title:
            return []

        # The signature endpoint is exact-match and returns the best possible
        # result when duration is known; the search endpoint is the fallback.
        candidates: list[LyricsCandidate] = []
        exact = await self._get("/get", self._signature_params(title, artist, identity))
        if isinstance(exact, dict):
            candidate = self._to_candidate(exact)
            if candidate is not None:
                candidates.append(candidate)

        results = await self._get("/search", {"track_name": title, "artist_name": artist} if artist else {"q": title})
        if isinstance(results, list):
            for entry in results[:_SEARCH_LIMIT]:
                candidate = self._to_candidate(entry)
                if candidate is not None:
                    candidates.append(candidate)

        return self._deduplicate(candidates)

    @staticmethod
    def _signature_params(title: str, artist: str, identity: SongIdentity) -> dict:
        params = {"track_name": title, "artist_name": artist or ""}
        if identity.album:
            params["album_name"] = strip_noise(identity.album)
        if identity.duration_ms:
            params["duration"] = str(round(identity.duration_ms / 1000))
        return {key: value for key, value in params.items() if value}

    async def _get(self, path: str, params: dict) -> object | None:
        if not params:
            return None
        try:
            session = await self._client()
            async with session.get(f"{_BASE_URL}{path}", params=params) as response:
                if response.status == 404:
                    # A miss is a legitimate answer, not a provider failure.
                    return None
                if response.status >= 500:
                    raise ProviderUnavailable("The lyrics provider is unavailable")
                if response.status >= 400:
                    return None
                return await response.json(content_type=None)
        except ProviderUnavailable:
            raise
        except (aiohttp.ClientError, asyncio.TimeoutError) as error:
            raise ProviderUnavailable("The lyrics provider could not be reached") from error
        except ValueError:
            # Malformed JSON is treated as a miss rather than an outage.
            return None

    @staticmethod
    def _to_candidate(entry: object) -> LyricsCandidate | None:
        if not isinstance(entry, dict):
            return None
        title = str(entry.get("trackName") or "").strip()
        if not title:
            return None
        duration = entry.get("duration")
        try:
            duration_seconds = float(duration) if duration is not None else None
        except (TypeError, ValueError):
            duration_seconds = None
        return LyricsCandidate(
            title=title,
            artist=str(entry.get("artistName") or "").strip(),
            album=str(entry.get("albumName") or "").strip(),
            duration_seconds=duration_seconds,
            synced_text=str(entry.get("syncedLyrics") or ""),
            plain_text=str(entry.get("plainLyrics") or ""),
            instrumental=bool(entry.get("instrumental")),
            provider=LrclibProvider.name,
            version_id=str(entry.get("id") or ""),
        )

    @staticmethod
    def _deduplicate(candidates: list[LyricsCandidate]) -> list[LyricsCandidate]:
        seen: set[str] = set()
        unique: list[LyricsCandidate] = []
        for candidate in candidates:
            key = candidate.version_id or f"{candidate.title}|{candidate.artist}|{candidate.duration_seconds}"
            if key in seen:
                continue
            seen.add(key)
            unique.append(candidate)
        return unique
