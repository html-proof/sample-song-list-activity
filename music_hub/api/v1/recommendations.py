from fastapi import APIRouter, Depends, Query

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.recommendations import RecommendationPage


router = APIRouter(prefix="/recommendations", tags=["recommendations"])


@router.get("", response_model=RecommendationPage)
async def recommendations(
    cursor: str | None = Query(default=None, max_length=1000),
    limit: int = Query(default=25, ge=1, le=40),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.recommendations.recommend(current.id, cursor, limit)
