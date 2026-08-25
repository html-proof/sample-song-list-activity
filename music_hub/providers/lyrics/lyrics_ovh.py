"""lyrics.ovh plain-text fallback provider.

This service answers a direct ``artist/title`` lookup and returns nothing else:
no album, no duration, no timestamps. That makes its results impossible to
verify against the requested recording, so the provider is marked
``verifiable = False`` and the service only ever accepts it as unsynchronised
text of last resort. It must never produce a synchronised document.
"""

from __future__ import annotations

from urllib.parse import quote

import aiohttp

from music_hub.lyrics import LyricsSyncType, ProviderLyricsCandidate, SongIdentity

from .base import LyricsProvider, LyricsProviderTemporaryError


DEFAULT_BASE_URL = "https://api.lyrics.ovh/v1"

_MAX_CHARACTERS = 20_000


class LyricsOvhProvider(LyricsProvider):
    name = "lyrics_ovh"
    configured = True
    verifiable = False

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        timeout_seconds: float = 8,
        user_agent: str = "MusicHub/1.0",
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.user_agent = user_agent
        self.timeout = aiohttp.ClientTimeout(total=timeout_seconds, connect=3)
        self._session: aiohttp.ClientSession | None = None

    async def search(self, identity: SongIdentity) -> list[ProviderLyricsCandidate]:
        if not identity.title or not identity.primary_artist:
            return []

        session = self._session
        if session is None or session.closed:
            session = aiohttp.ClientSession(
                timeout=self.timeout,
                headers={"User-Agent": self.user_agent, "Accept": "application/json"},
            )
            self._session = session

        url = (
            f"{self.base_url}/{quote(identity.primary_artist, safe='')}"
            f"/{quote(identity.title, safe='')}"
        )
        try:
            async with session.get(url) as response:
                if response.status == 404:
                    return []
                if response.status == 429 or response.status >= 500:
                    raise LyricsProviderTemporaryError(
                        f"lyrics.ovh returned HTTP {response.status}"
                    )
                if response.status >= 400:
                    return []
                payload = await response.json(content_type=None)
        except LyricsProviderTemporaryError:
            raise
        except (aiohttp.ClientError, TimeoutError, ValueError) as exc:
            raise LyricsProviderTemporaryError("lyrics.ovh request failed") from exc

        if not isinstance(payload, dict):
            return []
        text = str(payload.get("lyrics") or "").strip()
        if not text or len(text) > _MAX_CHARACTERS:
            return []

        return [
            ProviderLyricsCandidate(
                provider=self.name,
                # The response echoes nothing back, so the request metadata is
                # all this candidate can carry. The service knows not to treat
                # that as evidence of a match.
                title=identity.title,
                primary_artist=identity.primary_artist,
                sync_type=LyricsSyncType.PLAIN,
                plain_text=text,
            )
        ]

    async def close(self) -> None:
        if self._session is not None:
            await self._session.close()
            self._session = None
