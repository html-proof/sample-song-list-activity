from fastapi import APIRouter, Depends, Path, Query

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.lyrics import LyricsDocument, LyricsRequestHint


router = APIRouter(prefix="/songs", tags=["lyrics"])


@router.get("/{song_id}/lyrics", response_model=LyricsDocument)
async def lyrics(
    song_id: str = Path(min_length=1, max_length=200, pattern=r"^[a-zA-Z0-9_-]+$"),
    title: str | None = Query(
        default=None,
        max_length=300,
        description="Track title the client already holds. Sending it skips a catalogue lookup.",
    ),
    artist: str | None = Query(default=None, max_length=300),
    album: str | None = Query(default=None, max_length=300),
    duration: int | None = Query(
        default=None,
        ge=1,
        le=3600,
        description="Track length in seconds. Providers use it to reject the wrong version.",
    ),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
) -> LyricsDocument:
    """Return the lyrics document for a track.

    The catalogue id alone means nothing to an external lyrics service, so the
    player should always send the metadata it already has. When title and
    artist are both present the lookup starts immediately, which is what lets
    lyrics be ready before the lyrics screen is opened.
    """
    return await container.lyrics.get(
        song_id,
        LyricsRequestHint(
            title=title,
            artist=artist,
            album=album,
            duration_seconds=duration,
        ),
    )
