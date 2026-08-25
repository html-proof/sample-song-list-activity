from fastapi import APIRouter, Depends, Query

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.users import OnboardingRequest, OnboardingResponse


router = APIRouter(prefix="/onboarding", tags=["onboarding"])

SUPPORTED_LANGUAGES = [
    "Malayalam",
    "Tamil",
    "Hindi",
    "Telugu",
    "Kannada",
    "English",
    "Punjabi",
    "Bengali",
    "Marathi",
    "Gujarati",
]


@router.get("/languages")
async def languages(_: AuthenticatedUser = Depends(require_user)):
    return {
        "data": [
            {"code": language, "name": language}
            for language in SUPPORTED_LANGUAGES
        ]
    }


@router.get("/artists/suggested")
async def suggested_artists(
    language: list[str] = Query(default_factory=list, max_length=10),
    limit: int = Query(default=20, ge=1, le=50),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {
        "data": await container.onboarding.suggested_artists(
            current.id, language, limit
        )
    }


@router.get("/artists")
async def search_artists(
    q: str = Query(min_length=1, max_length=200),
    limit: int = Query(default=20, ge=1, le=50),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.onboarding.artists(q, limit)}


@router.get("", response_model=OnboardingResponse)
async def status(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.preferences_repository.get_onboarding(current.id)


@router.put("", response_model=OnboardingResponse)
async def complete(
    payload: OnboardingRequest,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.onboarding.complete(current.id, payload)
