from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum


class LyricsStatus(str, Enum):
    AVAILABLE = "available"
    PLAIN_ONLY = "plain_only"
    INSTRUMENTAL = "instrumental"
    NOT_FOUND = "not_found"
    UNSUPPORTED = "unsupported"
    TEMPORARY_ERROR = "temporary_error"


class SyncType(str, Enum):
    WORD = "word"
    LINE = "line"
    PLAIN = "plain"


@dataclass(frozen=True, slots=True)
class SongIdentity:
    """Everything known about the recording we need lyrics for.

    Matching never relies on the title alone: a live, remix, or cover version
    carries the same title as the original but different lyrics timing.
    """

    song_id: str
    title: str
    artist: str = ""
    album: str = ""
    duration_ms: int | None = None
    language: str = ""
    isrc: str = ""
    provider: str = ""
    provider_id: str = ""

    @property
    def duration_seconds(self) -> float | None:
        return None if self.duration_ms is None else self.duration_ms / 1000

    def identity_hash(self) -> str:
        """Stable fingerprint used to invalidate cached lyrics when the
        recording's identity changes underneath a reused song id."""
        from hashlib import blake2s

        parts = "\x1f".join(
            (
                self.provider,
                self.provider_id,
                self.isrc,
                self.song_id,
                self.title.casefold(),
                self.artist.casefold(),
                self.album.casefold(),
                str(self.duration_ms or ""),
            )
        )
        return blake2s(parts.encode("utf-8"), digest_size=8).hexdigest()


@dataclass(frozen=True, slots=True)
class LyricWord:
    text: str
    start_ms: int
    end_ms: int

    def to_dict(self) -> dict:
        return {"text": self.text, "start_ms": self.start_ms, "end_ms": self.end_ms}


@dataclass(frozen=True, slots=True)
class LyricLine:
    start_ms: int
    end_ms: int
    text: str
    words: list[LyricWord] = field(default_factory=list)

    def to_dict(self) -> dict:
        payload = {"start_ms": self.start_ms, "end_ms": self.end_ms, "text": self.text}
        if self.words:
            payload["words"] = [word.to_dict() for word in self.words]
        return payload


@dataclass(frozen=True, slots=True)
class LyricsDocument:
    """The response contract shared with the Flutter client.

    `status` always explains *why* lyrics are missing so the client can render
    the right message instead of a generic null.
    """

    song_id: str
    status: LyricsStatus
    sync_type: SyncType | None = None
    language: str = ""
    offset_ms: int = 0
    confidence: float | None = None
    lines: list[LyricLine] = field(default_factory=list)
    plain_text: str = ""
    provider: str = ""
    lyrics_version: str = ""
    fetched_at: datetime | None = None
    song_identity_hash: str = ""

    @classmethod
    def unavailable(
        cls,
        song_id: str,
        status: LyricsStatus,
        *,
        identity_hash: str = "",
        confidence: float | None = None,
        provider: str = "",
    ) -> "LyricsDocument":
        return cls(
            song_id=song_id,
            status=status,
            confidence=confidence,
            provider=provider,
            fetched_at=datetime.now(timezone.utc),
            song_identity_hash=identity_hash,
        )

    def to_dict(self) -> dict:
        payload: dict = {
            "song_id": self.song_id,
            "status": self.status.value,
            "offset_ms": self.offset_ms,
            "lines": [line.to_dict() for line in self.lines],
        }
        if self.sync_type is not None:
            payload["sync_type"] = self.sync_type.value
        if self.language:
            payload["language"] = self.language
        if self.confidence is not None:
            payload["confidence"] = round(self.confidence, 4)
        if self.plain_text:
            payload["plain_text"] = self.plain_text
        if self.provider:
            payload["provider"] = self.provider
        if self.lyrics_version:
            payload["lyrics_version"] = self.lyrics_version
        if self.fetched_at is not None:
            payload["fetched_at"] = self.fetched_at.isoformat()
        if self.song_identity_hash:
            payload["song_identity_hash"] = self.song_identity_hash
        return payload

    @classmethod
    def from_dict(cls, payload: dict) -> "LyricsDocument":
        fetched_raw = payload.get("fetched_at")
        try:
            fetched_at = datetime.fromisoformat(fetched_raw) if fetched_raw else None
        except (TypeError, ValueError):
            fetched_at = None
        sync_raw = payload.get("sync_type")
        return cls(
            song_id=str(payload.get("song_id", "")),
            status=LyricsStatus(payload.get("status", LyricsStatus.NOT_FOUND.value)),
            sync_type=SyncType(sync_raw) if sync_raw else None,
            language=str(payload.get("language", "")),
            offset_ms=int(payload.get("offset_ms", 0) or 0),
            confidence=payload.get("confidence"),
            lines=[
                LyricLine(
                    start_ms=int(line.get("start_ms", 0) or 0),
                    end_ms=int(line.get("end_ms", 0) or 0),
                    text=str(line.get("text", "")),
                    words=[
                        LyricWord(
                            text=str(word.get("text", "")),
                            start_ms=int(word.get("start_ms", 0) or 0),
                            end_ms=int(word.get("end_ms", 0) or 0),
                        )
                        for word in line.get("words", [])
                        if isinstance(word, dict)
                    ],
                )
                for line in payload.get("lines", [])
                if isinstance(line, dict)
            ],
            plain_text=str(payload.get("plain_text", "")),
            provider=str(payload.get("provider", "")),
            lyrics_version=str(payload.get("lyrics_version", "")),
            fetched_at=fetched_at,
            song_identity_hash=str(payload.get("song_identity_hash", "")),
        )


@dataclass(frozen=True, slots=True)
class LyricsCandidate:
    """A raw result from a lyrics provider, before match verification."""

    title: str
    artist: str
    album: str = ""
    duration_seconds: float | None = None
    synced_text: str = ""
    plain_text: str = ""
    instrumental: bool = False
    provider: str = ""
    version_id: str = ""
    language: str = ""
