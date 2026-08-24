from fastapi import APIRouter, Depends, Header, Query, Response, status

from music_hub.container import Container
from music_hub.dependencies import AuthenticatedUser, get_container, require_user
from music_hub.schemas.history import ListeningHistoryCreate, MusicEventCreate


router = APIRouter(prefix="/history", tags=["history"])


@router.post("/listens", status_code=status.HTTP_201_CREATED)
async def record_listen(
    payload: ListeningHistoryCreate,
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return await container.history.record_listen(current.id, payload)


@router.post("/events", status_code=status.HTTP_201_CREATED)
async def record_event(
    payload: MusicEventCreate,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=200),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    if idempotency_key and not payload.idempotency_key:
        payload = payload.model_copy(update={"idempotency_key": idempotency_key})
    return await container.history.record_event(current.id, payload)


@router.get("/recent")
async def recent(
    limit: int = Query(default=25, ge=1, le=100),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.history.recent(current.id, limit)}


@router.get("/continue")
async def continue_listening(
    limit: int = Query(default=10, ge=1, le=50),
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    return {"data": await container.history.continue_listening(current.id, limit)}


@router.delete(
    "/listening",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def clear_listening(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.settings_service.clear_history(current.id, "listening")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete(
    "/search",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def clear_search(
    current: AuthenticatedUser = Depends(require_user),
    container: Container = Depends(get_container),
):
    await container.settings_service.clear_history(current.id, "search")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
