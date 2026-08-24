from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from music_hub.auth.firebase import FirebaseIdentity, InvalidFirebaseToken
from music_hub.container import Container


bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthenticatedUser:
    record: dict
    identity: FirebaseIdentity

    @property
    def id(self):
        return self.record["id"]


def get_container(request: Request) -> Container:
    return request.app.state.container


async def require_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    container: Container = Depends(get_container),
) -> AuthenticatedUser:
    if credentials is None or credentials.scheme.casefold() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="A Firebase bearer token is required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        identity = await container.firebase.verify(credentials.credentials)
    except InvalidFirebaseToken as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    record = await container.users_repository.resolve_identity(identity)
    return AuthenticatedUser(record=record, identity=identity)
