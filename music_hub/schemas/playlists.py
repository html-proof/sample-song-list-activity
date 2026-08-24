from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class PlaylistCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=1000)
    is_public: bool = False


class PlaylistUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=1000)
    is_public: bool | None = None


class PlaylistTrackCreate(BaseModel):
    provider: str = "gaana"
    song_id: str = Field(min_length=1, max_length=200)
    song_name: str | None = Field(default=None, max_length=500)
    artist_name: str | None = Field(default=None, max_length=500)
    album_name: str | None = Field(default=None, max_length=500)
    artwork_url: str | None = Field(default=None, max_length=2000)
    duration_ms: int | None = Field(default=None, ge=0)


class PlaylistResponse(BaseModel):
    id: UUID
    name: str
    description: str | None
    is_public: bool
    created_at: datetime
    updated_at: datetime
    track_count: int = 0


class PlaylistDetail(PlaylistResponse):
    tracks: list[dict] = Field(default_factory=list)
