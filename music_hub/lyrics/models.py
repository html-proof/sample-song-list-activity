from __future__ import annotations

from enum import Enum
from hashlib import sha256

from pydantic import BaseModel, ConfigDict, Field


class LyricsStatus(str, Enum):
    AVAILABLE = "available"
    PLAIN_ONLY = "plain_only"
    INSTRUMENTAL = "instrumental"
    NOT_FOUND = "not_found"
    UNSUPPORTED = "unsupported"
    TEMPORARY_ERROR = "temporary_error"


class LyricsSyncType(str, Enum):
    WORD = "word"
    LINE = "line"
    PLAIN = "plain"


class LyricWord(BaseModel):
    model_config = ConfigDict(extra="ignore")

    text: str = Field(min_length=1)
    start_ms: int = Field(ge=0)
    end_ms: int = Field(gt=0)


class LyricLine(BaseModel):
    model_config = ConfigDict(extra="ignore")

    text: str = Field(min_length=1)
    start_ms: int | None = Field(default=None, ge=0)
    end_ms: int | None = Field(default=None, gt=0)
    words: list[LyricWord] = Field(default_factory=list)


class SongIdentity(BaseModel):
    model_config = ConfigDict(extra="ignore", frozen=True)

    song_id: str
    provider: str
    provider_song_id: str | None = None
    isrc: str | None = None
    title: str
    primary_artist: str
    album: str | None = None
    duration_ms: int | None = Field(default=None, ge=0)
    language: str | None = None

    @property
    def identity_hash(self) -> str:
        values = (
            self.provider,
            self.provider_song_id or "",
            self.isrc or "",
            self.title,
            self.primary_artist,
            self.album or "",
            str(self.duration_ms or ""),
            self.language or "",
        )
        return sha256("\x1f".join(values).casefold().encode("utf-8")).hexdigest()


class LyricsRequestHint(BaseModel):
    """Metadata the client already holds for the track it just selected.

    The player knows the title, artist, album and duration the moment a song is
    tapped. Passing them in lets the lookup start immediately instead of
    waiting on a catalogue round-trip, which is what keeps lyrics ready before
    the lyrics screen is opened.
    """

    model_config = ConfigDict(extra="ignore", frozen=True)

    title: str | None = None
    artist: str | None = None
    album: str | None = None
    duration_seconds: int | None = Field(default=None, ge=1, le=3600)

    @property
    def sufficient(self) -> bool:
        """Whether the hint alone can identify the recording to a provider."""
        return bool((self.title or "").strip() and (self.artist or "").strip())


class ProviderLyricsCandidate(BaseModel):
    model_config = ConfigDict(extra="ignore")

    provider: str
    lyrics_id: str | None = None
    provider_song_id: str | None = None
    isrc: str | None = None
    title: str
    primary_artist: str
    album: str | None = None
    duration_ms: int | None = Field(default=None, ge=0)
    language: str | None = None
    sync_type: LyricsSyncType = LyricsSyncType.PLAIN
    offset_ms: int = 0
    lines: list[LyricLine] = Field(default_factory=list)
    plain_text: str | None = None
    instrumental: bool = False
    lyrics_version: str | None = None


class LyricsDocument(BaseModel):
    model_config = ConfigDict(extra="ignore")

    song_id: str
    status: LyricsStatus
    sync_type: LyricsSyncType | None = None
    language: str | None = None
    offset_ms: int = 0
    confidence: float | None = Field(default=None, ge=0, le=1)
    lines: list[LyricLine] = Field(default_factory=list)
    plain_text: str | None = None
    provider: str | None = None
    lyrics_version: str | None = None
    fetched_at: str | None = None
    song_identity_hash: str | None = None
