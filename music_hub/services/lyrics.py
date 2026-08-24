from datetime import UTC, datetime

from music_hub.cache.lyrics_cache import LyricsCache
from music_hub.lyrics import (
    LyricsDocument,
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
    def __init__(
        self,
        music_provider: MusicProvider,
        lyrics_provider: LyricsProvider,
        cache: LyricsCache,
        matcher: LyricsMatcher,
    ) -> None:
        self.music_provider = music_provider
        self.lyrics_provider = lyrics_provider
        self.cache = cache
        self.matcher = matcher

    async def get(self, song_id: str) -> LyricsDocument:
        song = await self.music_provider.get_song(song_id)
        identity = _song_identity(song_id, song, self.music_provider.name)
        cached = await self.cache.get(identity)
        if cached is not None:
            return cached

        if not self.lyrics_provider.configured:
            return await self._store(
                identity,
                LyricsDocument(song_id=song_id, status=LyricsStatus.UNSUPPORTED),
            )

        try:
            candidates = await self.lyrics_provider.search(identity)
        except LyricsProviderTemporaryError:
            return await self._store(
                identity,
                LyricsDocument(song_id=song_id, status=LyricsStatus.TEMPORARY_ERROR),
            )

        match = self.matcher.best(identity, candidates)
        if match is None:
            confidence = max(
                (self.matcher.score(identity, candidate) for candidate in candidates),
                default=None,
            )
            return await self._store(
                identity,
                LyricsDocument(
                    song_id=song_id,
                    status=LyricsStatus.NOT_FOUND,
                    confidence=confidence,
                ),
            )

        return await self._store(identity, _document(identity, match.candidate, match.confidence))

    async def _store(
        self,
        identity: SongIdentity,
        document: LyricsDocument,
    ) -> LyricsDocument:
        enriched = document.model_copy(
            update={
                "fetched_at": datetime.now(UTC).isoformat(),
                "song_identity_hash": identity.identity_hash,
            }
        )
        await self.cache.put(identity, enriched)
        return enriched


def _song_identity(song_id: str, song: dict, provider: str) -> SongIdentity:
    duration = _integer(song.get("duration"))
    artists = song.get("artists") or song.get("artist_name") or song.get("artist") or ""
    if isinstance(artists, list):
        artists = ", ".join(
            str(item.get("name") or item.get("title") or "") if isinstance(item, dict) else str(item)
            for item in artists
        )
    return SongIdentity(
        song_id=song_id,
        provider=str(song.get("provider") or provider),
        provider_song_id=_string(song.get("provider_id") or song.get("track_id")),
        isrc=_string(song.get("isrc") or song.get("ISRC")),
        title=str(song.get("title") or song.get("track_title") or ""),
        primary_artist=str(artists).split(",", 1)[0].strip(),
        album=_string(song.get("album") or song.get("album_title")),
        duration_ms=duration * 1000 if duration is not None else None,
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


def _integer(value: object) -> int | None:
    try:
        return int(float(str(value))) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


def _string(value: object) -> str | None:
    text = str(value).strip() if value is not None else ""
    return text or None
