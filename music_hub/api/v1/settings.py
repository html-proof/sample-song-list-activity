from fastapi import APIRouter, Depends, Response, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.settings import (
    AppSettings,
    DownloadSettingsUpdate,
    GeneralSettingsUpdate,
    NotificationSettingsUpdate,
    PlaybackSettingsUpdate,
    PrivacySettingsUpdate,
    RecommendationSettingsUpdate,
)


router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("", response_model=AppSettings)
async def get_settings(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.get_all(current.id)


@router.patch("/general")
async def update_general(
    payload: GeneralSettingsUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.update(current.id, "general", payload)


@router.patch("/playback")
async def update_playback(
    payload: PlaybackSettingsUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.update(current.id, "playback", payload)


@router.patch("/downloads")
async def update_downloads(
    payload: DownloadSettingsUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.update(current.id, "downloads", payload)


@router.patch("/recommendations")
async def update_recommendations(
    payload: RecommendationSettingsUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.update(current.id, "recommendations", payload)


@router.patch("/notifications")
async def update_notifications(
    payload: NotificationSettingsUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.update(current.id, "notifications", payload)


@router.patch("/privacy")
async def update_privacy(
    payload: PrivacySettingsUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.update(current.id, "privacy", payload)


@router.post("/reset", response_model=AppSettings)
async def reset_settings(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.settings_service.reset(current.id)


@router.post(
    "/history/listening/clear",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def clear_listening_history(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.settings_service.clear_history(current.id, "listening")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/history/search/clear",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def clear_search_history(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.settings_service.clear_history(current.id, "search")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/recommendations/reset",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def reset_recommendations(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.settings_service.reset_recommendations(current.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
