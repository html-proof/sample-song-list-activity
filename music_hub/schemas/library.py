from pydantic import BaseModel, Field


class LikedSongCreate(BaseModel):
    provider: str = "gaana"
    song_id: str = Field(min_length=1, max_length=200)
    seokey: str | None = Field(default=None, max_length=200, pattern=r"^[a-z0-9-]+$")
    song_name: str | None = Field(default=None, max_length=500)
    artist_id: str | None = Field(default=None, max_length=200)
    artist_name: str | None = Field(default=None, max_length=500)
    album_id: str | None = Field(default=None, max_length=200)
    language: str | None = Field(default=None, max_length=50)
    artwork_url: str | None = Field(default=None, max_length=2000)


class FollowedArtistCreate(BaseModel):
    provider: str = "gaana"
    artist_id: str = Field(min_length=1, max_length=200)
    artist_name: str | None = Field(default=None, max_length=500)
    artwork_url: str | None = Field(default=None, max_length=2000)
    notifications_enabled: bool = True
