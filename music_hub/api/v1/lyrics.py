from fastapi import APIRouter, Depends, Path, Response

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.lyrics.models import LyricsStatus


router = APIRouter(prefix="/songs", tags=["lyrics"])

# Clients may keep a successful document for a week; a miss is rechecked sooner
# because lyrics databases gain entries over time.
_CONTENT_MAX_AGE = 604_800
_NEGATIVE_MAX_AGE = 3_600


@router.get("/{seokey}/lyrics")
async def song_lyrics(
    response: Response,
    seokey: str = Path(min_length=1, max_length=200, pattern=r"^[a-z0-9-]+$"),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    """Lyrics for a song, matched and verified against the exact recording.

    Always returns 200 with an explicit `status`. Missing lyrics are a normal
    outcome, not an error, so the client can render the right message without
    treating it as a playback failure.
    """
    document = await container.lyrics.for_song(seokey)

    if document.status is LyricsStatus.TEMPORARY_ERROR:
        response.headers["Cache-Control"] = "no-store"
        response.headers["Retry-After"] = "30"
    elif document.status in (
        LyricsStatus.AVAILABLE,
        LyricsStatus.PLAIN_ONLY,
        LyricsStatus.INSTRUMENTAL,
    ):
        response.headers["Cache-Control"] = f"private, max-age={_CONTENT_MAX_AGE}"
    else:
        response.headers["Cache-Control"] = f"private, max-age={_NEGATIVE_MAX_AGE}"

    return document.to_dict()
