from fastapi import APIRouter, Depends, HTTPException, Path, Query, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.recommendations.cursor import InvalidCursor
from music_hub.schemas.artists import ArtistPage


router = APIRouter(prefix="/artists", tags=["artists"])


# Declared before /{seokey} so the literal path is not captured by it.
@router.get("/recommended", response_model=ArtistPage)
async def recommended(
    limit: int = Query(default=30, ge=1, le=50),
    cursor: str | None = Query(default=None, max_length=1000),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    """Artists chosen from the user's languages, selections, listening,
    likes and searches. Cursor-paginated; see ArtistPage."""
    try:
        return await container.artist_recommendations.recommend(
            current.id,
            cursor,
            limit,
        )
    except InvalidCursor as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc


@router.get("/{seokey}")
async def artist(
    seokey: str = Path(min_length=1, max_length=200, pattern=r"^[a-z0-9-]+$"),
    limit: int = Query(default=10, ge=1, le=50),
    page: int = Query(default=1, ge=1, le=1000),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.music.artist(seokey, limit, page)


@router.get("/id/{artist_id}/tracks")
async def tracks(
    artist_id: str = Path(pattern=r"^[0-9]+$"),
    limit: int = Query(default=25, ge=1, le=100),
    page: int = Query(default=1, ge=1, le=1000),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.music.artist_tracks(artist_id, limit, page)


@router.get("/id/{artist_id}/similar")
async def similar(
    artist_id: str = Path(pattern=r"^[0-9]+$"),
    limit: int = Query(default=10, ge=1, le=50),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.music.similar_artists(artist_id, limit)}


@router.get("/id/{artist_id}/related")
async def related(
    artist_id: str = Path(pattern=r"^[0-9]+$"),
    limit: int = Query(default=20, ge=1, le=50),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    """Similar artists re-ranked against this listener rather than returned in
    the provider's own order."""
    return {
        "data": await container.artist_recommendations.related(
            current.id,
            artist_id,
            limit,
        )
    }
