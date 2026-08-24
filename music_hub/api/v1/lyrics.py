from fastapi import APIRouter, Depends, Path

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.lyrics import LyricsDocument


router = APIRouter(prefix="/songs", tags=["lyrics"])


@router.get("/{song_id}/lyrics", response_model=LyricsDocument)
async def lyrics(
    song_id: str = Path(min_length=1, max_length=200, pattern=r"^[a-zA-Z0-9_-]+$"),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
) -> LyricsDocument:
    return await container.lyrics.get(song_id)
