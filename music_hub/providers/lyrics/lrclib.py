"""LRCLIB lyrics provider.

LRCLIB is a free, key-less service that returns both plain and timestamped
lyrics. Its ``/api/get`` endpoint matches on title, artist, album and duration
together, and it applies a tight duration tolerance so a remix or a live cut
does not answer for the original recording. That exact lookup is tried first;
the looser ``/api/search`` endpoint is only a fallback, and everything it
returns is still ranked by the shared matcher before it can be used.

LRCLIB asks clients to identify themselves with a descriptive User-Agent and to
respect ``Retry-After``, so both are honoured here and results are cached
upstream rather than re-requested per playback.
"""

from __future__ import annotations

import asyncio

import aiohttp

from music_hub.lyrics import LyricsSyncType, ProviderLyricsCandidate, SongIdentity
from music_hub.lyrics.lrc import parse_lrc

from .base import LyricsProvider, LyricsProviderTemporaryError


DEFAULT_BASE_URL = "https://lrclib.net/api"

# The search endpoint caps its own result set; ranking more than this adds
# latency without improving the match.
_MAX_SEARCH_CANDIDATES = 12
_MAX_RETRY_DELAY_SECONDS = 3.0


class LrclibLyricsProvider(LyricsProvider):
    name = "lrclib"
    configured = True
    verifiable = True

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        user_agent: str = "MusicHub/1.0",
        timeout_seconds: float = 8,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.user_agent = user_agent
        self.timeout = aiohttp.ClientTimeout(total=timeout_seconds, connect=3)
        self._session: aiohttp.ClientSession | None = None

    async def search(self, identity: SongIdentity) -> list[ProviderLyricsCandidate]:
        if not identity.title or not identity.primary_artist:
            return []

        exact = await self._exact(identity)
        if exact is not None:
            return [exact]
        return await self._fallback_search(identity)

    async def close(self) -> None:
        if self._session is not None:
            await self._session.close()
            self._session = None

    async def _exact(self, identity: SongIdentity) -> ProviderLyricsCandidate | None:
        params = {
            "track_name": identity.title,
            "artist_name": identity.primary_artist,
        }
        if identity.album:
            params["album_name"] = identity.album
        if identity.duration_ms:
            # LRCLIB expects whole seconds and matches them tightly.
            params["duration"] = str(round(identity.duration_ms / 1000))

        payload = await self._request("/get", params)
        if not isinstance(payload, dict):
            return None
        return _candidate(payload)

    async def _fallback_search(self, identity: SongIdentity) -> list[ProviderLyricsCandidate]:
        params = {
            "track_name": identity.title,
            "artist_name": identity.primary_artist,
        }
        if identity.album:
            params["album_name"] = identity.album

        payload = await self._request("/search", params)
        if not isinstance(payload, list):
            return []

        candidates: list[ProviderLyricsCandidate] = []
        for value in payload[:_MAX_SEARCH_CANDIDATES]:
            if not isinstance(value, dict):
                continue
            candidate = _candidate(value)
            if candidate is not None:
                candidates.append(candidate)
        return candidates

    async def _request(self, path: str, params: dict[str, str]) -> object | None:
        session = self._session
        if session is None or session.closed:
            session = aiohttp.ClientSession(
                timeout=self.timeout,
                headers={"User-Agent": self.user_agent, "Accept": "application/json"},
            )
            self._session = session

        try:
            async with session.get(f"{self.base_url}{path}", params=params) as response:
                if response.status == 404:
                    return None
                if response.status == 429:
                    await asyncio.sleep(_retry_delay(response.headers.get("Retry-After")))
                    raise LyricsProviderTemporaryError("LRCLIB rate limit reached")
                if response.status >= 500:
                    raise LyricsProviderTemporaryError(
                        f"LRCLIB returned HTTP {response.status}"
                    )
                if response.status >= 400:
                    return None
                return await response.json(content_type=None)
        except LyricsProviderTemporaryError:
            raise
        except (aiohttp.ClientError, TimeoutError, ValueError) as exc:
            raise LyricsProviderTemporaryError("LRCLIB request failed") from exc


def _candidate(payload: dict) -> ProviderLyricsCandidate | None:
    title = _text(payload.get("trackName"))
    artist = _text(payload.get("artistName"))
    if not title or not artist:
        return None

    duration_ms = _duration_ms(payload.get("duration"))
    synced = _text(payload.get("syncedLyrics"))
    plain = _text(payload.get("plainLyrics"))
    lines = parse_lrc(synced, total_ms=duration_ms) if synced else []

    return ProviderLyricsCandidate(
        provider=LrclibLyricsProvider.name,
        lyrics_id=_text(payload.get("id")),
        title=title,
        primary_artist=artist,
        album=_text(payload.get("albumName")),
        duration_ms=duration_ms,
        sync_type=LyricsSyncType.LINE if lines else LyricsSyncType.PLAIN,
        # parse_lrc has already folded any [offset:] tag into the line times,
        # so the document must not ask the client to apply it a second time.
        offset_ms=0,
        lines=lines,
        plain_text=plain,
        instrumental=bool(payload.get("instrumental")),
        lyrics_version=_text(payload.get("id")),
    )


def _retry_delay(header: str | None) -> float:
    try:
        return min(max(float(header or "1"), 0.0), _MAX_RETRY_DELAY_SECONDS)
    except ValueError:
        return 1.0


def _duration_ms(value: object) -> int | None:
    try:
        seconds = float(str(value))
    except (TypeError, ValueError):
        return None
    return round(seconds * 1000) if seconds > 0 else None


def _text(value: object) -> str | None:
    text = str(value).strip() if value is not None else ""
    return text or None
