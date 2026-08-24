from fastapi import APIRouter, Depends, Path, Query

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user


router = APIRouter(prefix="/artists", tags=["artists"])


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
