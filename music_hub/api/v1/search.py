from typing import Literal

from fastapi import APIRouter, Depends, Query, Response, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.history import SearchHistoryCreate


router = APIRouter(prefix="/search", tags=["search"])


@router.get("")
async def search(
    q: str = Query(min_length=1, max_length=300),
    type: Literal["all", "songs", "albums", "artists"] = "all",
    limit: int = Query(default=20, ge=1, le=50),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.search.search(current.id, q, type, limit)


@router.post(
    "/events",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def record_search_event(
    payload: SearchHistoryCreate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.search.record_event(
        current.id,
        payload.query,
        payload.result_type,
        payload.clicked_result_id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
