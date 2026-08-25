from pydantic import BaseModel, Field


class ArtistPage(BaseModel):
    """Cursor-paginated artists. Cursors are used rather than page numbers
    because the underlying recommendation set changes between requests."""

    data: list[dict] = Field(default_factory=list)
    next_cursor: str | None = None
    has_more: bool = False


class ArtistSearchResponse(BaseModel):
    data: list[dict] = Field(default_factory=list)
