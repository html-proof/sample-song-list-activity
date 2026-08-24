import logging
from datetime import datetime, timezone

from music_hub.cache.lyrics_cache import LyricsCache
from music_hub.errors import ProviderUnavailable
from music_hub.lyrics.matcher import DEFAULT_MIN_CONFIDENCE, MatchResult, best_match
from music_hub.lyrics.models import (
    LyricsCandidate,
    LyricsDocument,
    LyricsStatus,
    SongIdentity,
    SyncType,
)
from music_hub.lyrics.normalizer import (
    clamp_tail,
    clean_plain_text,
    detect_script,
    parse_lrc,
)
from music_hub.lyrics.validator import validate_timeline, validate_words
from music_hub.providers.lyrics.base import LyricsProvider
from music_hub.services.music import MusicService


logger = logging.getLogger("music_hub.lyrics")


class LyricsService:
    """Resolves lyrics for a song id, verifying they match the recording.

    Every failure path returns a document with an explicit status. The caller
    never sees an exception for "no lyrics", because a lyrics failure must
    never be reported as a playback failure.
    """

    def __init__(
        self,
        provider: LyricsProvider,
        music: MusicService,
        cache: LyricsCache,
        minimum_confidence: float = DEFAULT_MIN_CONFIDENCE,
    ) -> None:
        self._provider = provider
        self._music = music
        self._cache = cache
        self._minimum_confidence = minimum_confidence

    async def for_song(self, song_id: str) -> LyricsDocument:
        try:
            identity = await self._identify(song_id)
        except ProviderUnavailable:
            return LyricsDocument.unavailable(song_id, LyricsStatus.TEMPORARY_ERROR)
        except Exception:
            logger.exception("Could not resolve song metadata for lyrics", extra={"song_id": song_id})
            return LyricsDocument.unavailable(song_id, LyricsStatus.NOT_FOUND)

        cached = await self._cache.get(identity)
        if cached is not None:
            return cached

        try:
            candidates = await self._provider.search(identity)
        except ProviderUnavailable:
            # Retryable: do not cache, do not poison the song as "not found".
            return LyricsDocument.unavailable(
                song_id,
                LyricsStatus.TEMPORARY_ERROR,
                identity_hash=identity.identity_hash(),
                provider=self._provider.name,
            )
        except Exception:
            logger.exception("Lyrics provider failed", extra={"song_id": song_id})
            return LyricsDocument.unavailable(
                song_id,
                LyricsStatus.TEMPORARY_ERROR,
                identity_hash=identity.identity_hash(),
                provider=self._provider.name,
            )

        document = self._build(identity, candidates)
        await self._cache.put(identity, document)
        return document

    async def prefetch(self, song_id: str) -> None:
        """Warm the cache for an upcoming track. Never raises."""
        try:
            await self.for_song(song_id)
        except Exception:
            logger.debug("Lyrics prefetch failed", extra={"song_id": song_id}, exc_info=True)

    async def _identify(self, song_id: str) -> SongIdentity:
        song = await self._music.song(song_id)
        if not isinstance(song, dict):
            return SongIdentity(song_id=song_id, title="")
        return _identity_from_song(song_id, song)

    def _build(self, identity: SongIdentity, candidates: list[LyricsCandidate]) -> LyricsDocument:
        if not candidates:
            return LyricsDocument.unavailable(
                identity.song_id,
                LyricsStatus.NOT_FOUND,
                identity_hash=identity.identity_hash(),
                provider=self._provider.name,
            )

        match = best_match(identity, candidates, self._minimum_confidence)
        if match is None:
            # A low-confidence winner is discarded on purpose: wrong lyrics are
            # a worse experience than no lyrics.
            return LyricsDocument.unavailable(
                identity.song_id,
                LyricsStatus.NOT_FOUND,
                identity_hash=identity.identity_hash(),
                provider=self._provider.name,
            )

        return self._document(identity, match)

    def _document(self, identity: SongIdentity, match: MatchResult) -> LyricsDocument:
        candidate = match.candidate
        now = datetime.now(timezone.utc)
        base = {
            "song_id": identity.song_id,
            "confidence": match.confidence,
            "provider": candidate.provider or self._provider.name,
            "lyrics_version": candidate.version_id,
            "fetched_at": now,
            "song_identity_hash": identity.identity_hash(),
        }

        if candidate.instrumental:
            return LyricsDocument(status=LyricsStatus.INSTRUMENTAL, **base)

        plain = clean_plain_text(candidate.plain_text)

        if candidate.synced_text:
            lines, offset_ms, file_language = parse_lrc(candidate.synced_text)
            validation = validate_timeline(lines, identity.duration_ms)
            if validation.valid:
                timed = clamp_tail(validation.lines, identity.duration_ms)
                language = (
                    identity.language
                    or file_language
                    or candidate.language
                    or detect_script("\n".join(line.text for line in timed[:20]))
                )
                return LyricsDocument(
                    status=LyricsStatus.AVAILABLE,
                    sync_type=SyncType.WORD if validate_words(timed) else SyncType.LINE,
                    language=language,
                    offset_ms=offset_ms,
                    lines=timed,
                    plain_text=plain or "\n".join(line.text for line in timed),
                    **base,
                )
            logger.info(
                "Rejected synced lyrics timeline",
                extra={"song_id": identity.song_id, "reason": validation.reason},
            )
            # Fall through to plain: never ship half-valid synchronization.

        if plain:
            return LyricsDocument(
                status=LyricsStatus.PLAIN_ONLY,
                sync_type=SyncType.PLAIN,
                language=identity.language or candidate.language or detect_script(plain[:400]),
                plain_text=plain,
                **base,
            )

        return LyricsDocument(status=LyricsStatus.NOT_FOUND, **base)


def _first(song: dict, *keys: str) -> str:
    for key in keys:
        value = song.get(key)
        if isinstance(value, list):
            value = _join_names(value)
        if value not in (None, ""):
            return str(value).strip()
    return ""


def _join_names(values: list) -> str:
    names: list[str] = []
    for value in values:
        if isinstance(value, dict):
            name = value.get("name") or value.get("artist_name") or value.get("title")
            if name:
                names.append(str(name))
        elif value not in (None, ""):
            names.append(str(value))
    return ", ".join(names)


def _duration_ms(song: dict) -> int | None:
    for key in ("duration_ms", "durationMs"):
        raw = song.get(key)
        if raw not in (None, ""):
            try:
                return int(float(raw))
            except (TypeError, ValueError):
                continue
    for key in ("duration", "track_duration", "length"):
        raw = song.get(key)
        if raw in (None, ""):
            continue
        try:
            return int(float(raw) * 1000)
        except (TypeError, ValueError):
            # Providers sometimes send "3:45" instead of a number.
            parts = str(raw).split(":")
            if all(part.strip().isdigit() for part in parts) and 1 < len(parts) <= 3:
                seconds = 0
                for part in parts:
                    seconds = seconds * 60 + int(part)
                return seconds * 1000
    return None


def _identity_from_song(song_id: str, song: dict) -> SongIdentity:
    return SongIdentity(
        song_id=song_id,
        title=_first(song, "track_title", "title", "name", "song_title"),
        artist=_first(song, "artist", "artists", "artist_name", "primary_artists", "singers"),
        album=_first(song, "album_title", "album", "album_name"),
        duration_ms=_duration_ms(song),
        language=_first(song, "language", "lang").casefold()[:2],
        isrc=_first(song, "isrc"),
        provider=_first(song, "provider"),
        provider_id=_first(song, "provider_id", "track_id", "seokey"),
    )
