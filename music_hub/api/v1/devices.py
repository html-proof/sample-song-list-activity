from fastapi import APIRouter, Depends, Path, Response, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.devices import DeviceRegistration


router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("")
async def register_device(
    payload: DeviceRegistration,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.devices.register(current.id, payload)


@router.delete(
    "/{device_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def remove_device(
    device_id: str = Path(min_length=1, max_length=300),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.devices.remove(current.id, device_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
