from fastapi import APIRouter, Depends, Path, Query

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user


router = APIRouter(prefix="/albums", tags=["albums"])


@router.get("/{seokey}")
async def album(
    seokey: str = Path(min_length=1, max_length=200, pattern=r"^[a-z0-9-]+$"),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.music.album(seokey)


@router.get("/id/{album_id}/similar")
async def similar(
    album_id: str = Path(pattern=r"^[0-9]+$"),
    limit: int = Query(default=10, ge=1, le=50),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.music.similar_albums(album_id, limit)}
