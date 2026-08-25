from collections.abc import Sequence
from datetime import datetime, timezone

from music_hub.cache.lyrics_cache import LyricsCache
from music_hub.lyrics import (
    LyricsDocument,
    LyricsRequestHint,
    LyricsStatus,
    LyricsSyncType,
    ProviderLyricsCandidate,
    SongIdentity,
)
from music_hub.lyrics.matcher import LyricsMatcher
from music_hub.lyrics.validator import validated_lines
from music_hub.providers.base import MusicProvider
from music_hub.providers.lyrics import LyricsProvider, LyricsProviderTemporaryError


class LyricsService:
    """Resolves lyrics for a track through an ordered list of providers.

    The lookup order is deliberate: cache, then providers that return their own
    catalogue metadata (so a match can actually be verified against the
    requested recording), then unverifiable plain-text sources. The first
    provider that produces an accepted match wins, which keeps a synchronised
    LRCLIB result ahead of a plain-text fallback.
    """

    def __init__(
        self,
        music_provider: MusicProvider,
        lyrics_providers: Sequence[LyricsProvider] | LyricsProvider,
        cache: LyricsCache,
        matcher: LyricsMatcher,
    ) -> None:
        self.music_provider = music_provider
        # A single provider is accepted as a convenience so callers that only
        # have one do not have to wrap it.
        self.lyrics_providers = (
            list(lyrics_providers)
            if isinstance(lyrics_providers, (list, tuple))
            else [lyrics_providers]
        )
        self.cache = cache
        self.matcher = matcher

    async def get(
        self,
        song_id: str,
        hint: LyricsRequestHint | None = None,
    ) -> LyricsDocument:
        cached = await self.cache.get(song_id)
        if cached is not None:
            return cached

        identity = await self._identity(song_id, hint)
        active = [provider for provider in self.lyrics_providers if provider.configured]
        if not active:
            return await self._store(
                song_id,
                identity,
                LyricsDocument(song_id=song_id, status=LyricsStatus.UNSUPPORTED),
            )

        best_confidence: float | None = None
        temporary_failure = False

        for provider in active:
            try:
                candidates = await provider.search(identity)
            except LyricsProviderTemporaryError:
                # Do not let one flaky provider hide a healthy one behind it,
                # but remember the failure so a miss is not cached as final.
                temporary_failure = True
                continue

            if not candidates:
                continue

            if not provider.verifiable:
                document = _unverified_document(identity, candidates[0])
                if document is not None:
                    return await self._store(song_id, identity, document)
                continue

            match = self.matcher.best(identity, candidates)
            if match is None:
                scores = [self.matcher.score(identity, candidate) for candidate in candidates]
                best_confidence = max(scores + ([best_confidence] if best_confidence else []))
                continue

            return await self._store(
                song_id,
                identity,
                _document(identity, match.candidate, match.confidence),
            )

        if temporary_failure:
            return await self._store(
                song_id,
                identity,
                LyricsDocument(song_id=song_id, status=LyricsStatus.TEMPORARY_ERROR),
            )

        return await self._store(
            song_id,
            identity,
            LyricsDocument(
                song_id=song_id,
                status=LyricsStatus.NOT_FOUND,
                confidence=best_confidence,
            ),
        )

    async def _identity(
        self,
        song_id: str,
        hint: LyricsRequestHint | None,
    ) -> SongIdentity:
        # A complete hint means the client already knows everything a lyrics
        # provider needs, so the catalogue round-trip is skipped entirely.
        if hint is not None and hint.sufficient:
            return _hint_identity(song_id, hint, self.music_provider.name)
        song = await self.music_provider.get_song(song_id)
        return _song_identity(song_id, song, self.music_provider.name, hint)

    async def _store(
        self,
        song_id: str,
        identity: SongIdentity,
        document: LyricsDocument,
    ) -> LyricsDocument:
        enriched = document.model_copy(
            update={
                "fetched_at": datetime.now(timezone.utc).isoformat(),
                "song_identity_hash": identity.identity_hash,
            }
        )
        await self.cache.put(song_id, enriched)
        return enriched


def _hint_identity(song_id: str, hint: LyricsRequestHint, provider: str) -> SongIdentity:
    return SongIdentity(
        song_id=song_id,
        provider=provider,
        title=(hint.title or "").strip(),
        primary_artist=_primary_artist(hint.artist or ""),
        album=_string(hint.album),
        duration_ms=hint.duration_seconds * 1000 if hint.duration_seconds else None,
    )


def _song_identity(
    song_id: str,
    song: dict,
    provider: str,
    hint: LyricsRequestHint | None = None,
) -> SongIdentity:
    duration = _integer(song.get("duration"))
    artists = song.get("artists") or song.get("artist_name") or song.get("artist") or ""
    if isinstance(artists, list):
        artists = ", ".join(
            str(item.get("name") or item.get("title") or "") if isinstance(item, dict) else str(item)
            for item in artists
        )
    duration_ms = duration * 1000 if duration is not None else None
    if duration_ms is None and hint is not None and hint.duration_seconds:
        duration_ms = hint.duration_seconds * 1000
    return SongIdentity(
        song_id=song_id,
        provider=str(song.get("provider") or provider),
        provider_song_id=_string(song.get("provider_id") or song.get("track_id")),
        isrc=_string(song.get("isrc") or song.get("ISRC")),
        title=str(song.get("title") or song.get("track_title") or (hint.title if hint else "") or ""),
        primary_artist=_primary_artist(str(artists) or (hint.artist if hint else "") or ""),
        album=_string(song.get("album") or song.get("album_title") or (hint.album if hint else None)),
        duration_ms=duration_ms,
        language=_string(song.get("language")),
    )


def _document(
    identity: SongIdentity,
    candidate: ProviderLyricsCandidate,
    confidence: float,
) -> LyricsDocument:
    common = {
        "song_id": identity.song_id,
        "language": candidate.language or identity.language,
        "offset_ms": candidate.offset_ms,
        "confidence": confidence,
        "provider": candidate.provider,
        "lyrics_version": candidate.lyrics_version,
    }
    if candidate.instrumental:
        return LyricsDocument(status=LyricsStatus.INSTRUMENTAL, **common)

    lines = validated_lines(candidate.lines, identity.duration_ms)
    if lines:
        sync_type = (
            LyricsSyncType.WORD
            if candidate.sync_type == LyricsSyncType.WORD
            and any(line.words for line in lines)
            else LyricsSyncType.LINE
        )
        return LyricsDocument(
            status=LyricsStatus.AVAILABLE,
            sync_type=sync_type,
            lines=lines,
            **common,
        )

    plain_text = (candidate.plain_text or "\n".join(line.text for line in candidate.lines)).strip()
    if plain_text:
        return LyricsDocument(
            status=LyricsStatus.PLAIN_ONLY,
            sync_type=LyricsSyncType.PLAIN,
            plain_text=plain_text,
            **common,
        )

    return LyricsDocument(status=LyricsStatus.NOT_FOUND, **common)


def _unverified_document(
    identity: SongIdentity,
    candidate: ProviderLyricsCandidate,
) -> LyricsDocument | None:
    """Wrap a fallback candidate that carries no metadata to verify against.

    Such a source can only ever yield unsynchronised text. Any timings it
    happens to include are discarded rather than presented as synchronised
    lyrics, and no confidence is claimed because none was measured.
    """
    plain_text = (candidate.plain_text or "").strip()
    if not plain_text:
        return None
    return LyricsDocument(
        song_id=identity.song_id,
        status=LyricsStatus.PLAIN_ONLY,
        sync_type=LyricsSyncType.PLAIN,
        plain_text=plain_text,
        confidence=None,
        provider=candidate.provider,
        language=identity.language,
    )


def _primary_artist(value: str) -> str:
    for separator in (",", "&", " feat.", " ft.", ";"):
        if separator in value:
            value = value.split(separator, 1)[0]
    return value.strip()


def _integer(value: object) -> int | None:
    try:
        return int(float(str(value))) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


def _string(value: object) -> str | None:
    text = str(value).strip() if value is not None else ""
    return text or None
