from fastapi import APIRouter, Depends

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.users import (
    ArtistPreferencesUpdate,
    LanguagePreferencesUpdate,
    UserPreferencesUpdate,
)


router = APIRouter(prefix="/preferences", tags=["preferences"])


@router.get("")
async def get_preferences(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.preferences_repository.get_preferences(current.id)


@router.patch("")
async def update_preferences(
    payload: UserPreferencesUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.preferences_repository.update_preferences(current.id, payload)


@router.put("/languages")
async def update_languages(
    payload: LanguagePreferencesUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.onboarding.update_languages(current.id, payload)


@router.put("/artists")
async def update_artists(
    payload: ArtistPreferencesUpdate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.onboarding.update_artists(current.id, payload)
