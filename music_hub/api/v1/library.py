from fastapi import APIRouter, Depends, Query, Response, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.library import FollowedArtistCreate, LikedSongCreate


router = APIRouter(prefix="/library", tags=["library"])


@router.get("/likes")
async def likes(
    limit: int = Query(default=100, ge=1, le=500),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.library.liked(current.id, limit)}


@router.put("/likes/{song_id}")
async def like(
    song_id: str,
    payload: LikedSongCreate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    payload.song_id = song_id
    return await container.library.like(current.id, payload)


@router.delete("/likes/{song_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unlike(
    song_id: str,
    provider: str = Query(default="gaana"),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.library.unlike(current.id, provider, song_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/artists")
async def followed_artists(
    limit: int = Query(default=100, ge=1, le=500),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.library.followed(current.id, limit)}


@router.put("/artists/{artist_id}")
async def follow_artist(
    artist_id: str,
    payload: FollowedArtistCreate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    payload.artist_id = artist_id
    return await container.library.follow(current.id, payload)


@router.delete("/artists/{artist_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unfollow_artist(
    artist_id: str,
    provider: str = Query(default="gaana"),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.library.unfollow(current.id, provider, artist_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
