from fastapi import APIRouter, Depends

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.users import UserResponse


router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/session", response_model=UserResponse)
async def create_session(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.users.register_login(current.id, current.identity)
