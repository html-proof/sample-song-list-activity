from uuid import UUID

from fastapi import APIRouter, Depends, Path, Query, Response, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.playlists import (
    PlaylistCreate,
    PlaylistDetail,
    PlaylistResponse,
    PlaylistTrackCreate,
    PlaylistUpdate,
)


router = APIRouter(prefix="/playlists", tags=["playlists"])


@router.get("/provider/{seokey}")
async def provider_playlist(
    seokey: str = Path(min_length=1, max_length=200, pattern=r"^[a-z0-9-]+$"),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.music.provider_playlist(seokey)}


@router.post("", response_model=PlaylistResponse, status_code=status.HTTP_201_CREATED)
async def create(
    payload: PlaylistCreate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.playlists.create(current.id, payload)


@router.get("", response_model=list[PlaylistResponse])
async def list_playlists(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.playlists.list(current.id)


@router.get("/{playlist_id}", response_model=PlaylistDetail)
async def get_playlist(
    playlist_id: UUID,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.playlists.get(current.id, playlist_id)


@router.patch("/{playlist_id}", response_model=PlaylistResponse)
async def update_playlist(
    playlist_id: UUID,
    payload: PlaylistUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.playlists.update(current.id, playlist_id, payload)


@router.delete("/{playlist_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_playlist(
    playlist_id: UUID,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.playlists.delete(current.id, playlist_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{playlist_id}/tracks", status_code=status.HTTP_201_CREATED)
async def add_track(
    playlist_id: UUID,
    payload: PlaylistTrackCreate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.playlists.add_track(current.id, playlist_id, payload)


@router.delete("/{playlist_id}/tracks/{track_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_track(
    playlist_id: UUID,
    track_id: UUID,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.playlists.remove_track(current.id, playlist_id, track_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
