from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import StringConstraints

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.errors import MusicHubError
from music_hub.schemas.recommendations import HomeResponse


router = APIRouter(prefix="/home", tags=["home"])
LanguageName = Annotated[
    str,
    StringConstraints(min_length=2, max_length=50, pattern=r"^[A-Za-z][A-Za-z -]*$"),
]


@router.get("", response_model=HomeResponse)
async def home(
    cursor: str | None = Query(default=None, max_length=1000),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.home.build(current.id, cursor)


@router.get("/trending")
async def trending(
    languages: list[LanguageName] = Query(default=["Hindi"]),
    limit: int = Query(default=25, ge=1, le=100),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.provider.trending(languages, limit)}


@router.get("/new-releases")
async def new_releases(
    languages: list[LanguageName] = Query(default=["Hindi"]),
    limit: int = Query(default=25, ge=1, le=100),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.provider.new_releases(languages, limit)}


@router.get("/charts")
async def charts(
    limit: int = Query(default=10, ge=1, le=50),
    _: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.music.charts(limit)}
