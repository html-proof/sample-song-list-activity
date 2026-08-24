from fastapi import APIRouter, Depends, Path

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user


router = APIRouter(prefix="/songs", tags=["songs"])


@router.get("/{seokey}")
async def song(
    seokey: str = Path(min_length=1, max_length=200, pattern=r"^[a-z0-9-]+$"),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.music.song(seokey)
