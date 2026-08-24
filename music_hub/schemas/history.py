from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class MusicEventType(str, Enum):
    impression = "impression"
    play = "play"
    pause = "pause"
    resume = "resume"
    skip = "skip"
    complete = "complete"
    like = "like"
    unlike = "unlike"
    repeat = "repeat"
    add_playlist = "add_playlist"
    remove_playlist = "remove_playlist"
    share = "share"
    download = "download"


class ListeningHistoryCreate(BaseModel):
    provider: str = "gaana"
    song_id: str = Field(min_length=1, max_length=200)
    seokey: str | None = Field(default=None, max_length=200, pattern=r"^[a-z0-9-]+$")
    song_name: str | None = Field(default=None, max_length=500)
    artist_id: str | None = Field(default=None, max_length=200)
    artist_name: str | None = Field(default=None, max_length=500)
    album_id: str | None = Field(default=None, max_length=200)
    album_name: str | None = Field(default=None, max_length=500)
    language: str | None = Field(default=None, max_length=50)
    artwork_url: str | None = Field(default=None, max_length=2000)
    duration_ms: int | None = Field(default=None, ge=0)
    played_ms: int = Field(default=0, ge=0)
    source: str | None = Field(default=None, max_length=50)
    started_at: datetime | None = None
    completed_at: datetime | None = None
    session_id: UUID | None = None

    @model_validator(mode="after")
    def validate_position(self) -> "ListeningHistoryCreate":
        if self.duration_ms and self.played_ms > self.duration_ms * 2:
            raise ValueError("played_ms is not plausible for duration_ms")
        return self


class MusicEventCreate(BaseModel):
    event_type: MusicEventType
    provider: str = "gaana"
    song_id: str | None = Field(default=None, max_length=200)
    artist_id: str | None = Field(default=None, max_length=200)
    album_id: str | None = Field(default=None, max_length=200)
    language: str | None = Field(default=None, max_length=50)
    source: str | None = Field(default=None, max_length=50)
    position_ms: int | None = Field(default=None, ge=0)
    session_id: UUID | None = None
    idempotency_key: str | None = Field(default=None, max_length=200)
    metadata: dict = Field(default_factory=dict)


class SearchHistoryCreate(BaseModel):
    query: str = Field(min_length=1, max_length=300)
    result_type: str | None = Field(default=None, max_length=30)
    clicked_result_id: str | None = Field(default=None, max_length=200)
