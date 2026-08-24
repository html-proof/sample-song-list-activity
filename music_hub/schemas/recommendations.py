from pydantic import BaseModel, Field


class RecommendationPage(BaseModel):
    data: list[dict] = Field(default_factory=list)
    next_cursor: str | None = None
    has_more: bool = False


class HomeResponse(BaseModel):
    continue_listening: list[dict] = Field(default_factory=list)
    recommended_for_you: list[dict] = Field(default_factory=list)
    because_you_like: list[dict] = Field(default_factory=list)
    new_releases: list[dict] = Field(default_factory=list)
    trending: list[dict] = Field(default_factory=list)
    language_mix: list[dict] = Field(default_factory=list)
    recently_played: list[dict] = Field(default_factory=list)
    recommended_artists: list[dict] = Field(default_factory=list)
    next_cursor: str | None = None
