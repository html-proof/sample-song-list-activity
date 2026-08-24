from fastapi import APIRouter, Depends, Response, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user


router = APIRouter(prefix="/account", tags=["account"])


@router.delete(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def delete_account(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    # The authenticated token supplies both identifiers; the client never
    # chooses which account is deleted.
    await container.firebase.delete_user(current.identity.uid)
    await container.users_repository.delete(current.id)
    await container.cache.delete_pattern(f"*:{current.id}*")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
