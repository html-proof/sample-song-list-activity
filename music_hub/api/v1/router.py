from fastapi import APIRouter

from . import (
    account,
    albums,
    artists,
    auth,
    devices,
    history,
    home,
    library,
    lyrics,
    onboarding,
    playlists,
    preferences,
    recommendations,
    search,
    settings,
    songs,
    users,
)

router = APIRouter()
router.include_router(auth.router)
router.include_router(account.router)
router.include_router(users.router)
router.include_router(onboarding.router)
router.include_router(home.router)
router.include_router(search.router)
router.include_router(songs.router)
router.include_router(lyrics.router)
router.include_router(artists.router)
router.include_router(albums.router)
router.include_router(playlists.router)
router.include_router(library.router)
router.include_router(history.router)
router.include_router(recommendations.router)
router.include_router(preferences.router)
router.include_router(settings.router)
router.include_router(devices.router)
