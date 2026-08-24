from __future__ import annotations

import aiohttp
from pydantic import ValidationError

from music_hub.lyrics import ProviderLyricsCandidate, SongIdentity

from .base import LyricsProvider, LyricsProviderTemporaryError


class UnsupportedLyricsProvider(LyricsProvider):
    name = "unconfigured"
    configured = False

    async def search(self, identity: SongIdentity) -> list[ProviderLyricsCandidate]:
        return []

    async def close(self) -> None:
        return None


class LicensedHttpLyricsProvider(LyricsProvider):
    """Adapter for a licensed lyrics gateway using the documented JSON contract."""

    name = "licensed_http"

    def __init__(self, base_url: str, token: str, timeout_seconds: float = 8) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = aiohttp.ClientTimeout(total=timeout_seconds)
        self._session: aiohttp.ClientSession | None = None

    async def search(self, identity: SongIdentity) -> list[ProviderLyricsCandidate]:
        session = self._session
        if session is None:
            session = aiohttp.ClientSession(timeout=self.timeout)
            self._session = session
        params = {
            "provider": identity.provider,
            "provider_song_id": identity.provider_song_id,
            "isrc": identity.isrc,
            "title": identity.title,
            "artist": identity.primary_artist,
            "album": identity.album,
            "duration_ms": identity.duration_ms,
            "language": identity.language,
        }
        headers = {"Authorization": f"Bearer {self.token}", "Accept": "application/json"}
        try:
            async with session.get(
                f"{self.base_url}/lyrics",
                params={key: value for key, value in params.items() if value not in (None, "")},
                headers=headers,
            ) as response:
                if response.status == 404:
                    return []
                if response.status == 429 or response.status >= 500:
                    raise LyricsProviderTemporaryError(
                        f"Lyrics provider returned HTTP {response.status}"
                    )
                if response.status >= 400:
                    return []
                payload = await response.json(content_type=None)
        except LyricsProviderTemporaryError:
            raise
        except (aiohttp.ClientError, TimeoutError, ValueError) as exc:
            raise LyricsProviderTemporaryError("Lyrics provider request failed") from exc

        raw_candidates = payload.get("candidates", []) if isinstance(payload, dict) else payload
        if isinstance(raw_candidates, dict):
            raw_candidates = [raw_candidates]
        if not isinstance(raw_candidates, list):
            raise LyricsProviderTemporaryError("Lyrics provider returned invalid JSON")
        candidates: list[ProviderLyricsCandidate] = []
        for value in raw_candidates:
            if not isinstance(value, dict):
                continue
            value.setdefault("provider", self.name)
            try:
                candidates.append(ProviderLyricsCandidate.model_validate(value))
            except ValidationError:
                continue
        return candidates

    async def close(self) -> None:
        if self._session is not None:
            await self._session.close()
            self._session = None
