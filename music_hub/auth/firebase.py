import asyncio
from dataclasses import dataclass

import firebase_admin
from firebase_admin import auth, credentials

from music_hub.config import Settings
from music_hub.errors import InfrastructureUnavailable


class InvalidFirebaseToken(Exception):
    pass


@dataclass(frozen=True)
class FirebaseIdentity:
    uid: str
    email: str | None
    display_name: str | None
    photo_url: str | None
    email_verified: bool


class FirebaseVerifier:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._app: firebase_admin.App | None = None

    def _initialize(self) -> firebase_admin.App:
        if self._app is not None:
            return self._app
        try:
            self._app = firebase_admin.get_app()
            return self._app
        except ValueError:
            pass

        try:
            credential = None
            if self.settings.firebase_credentials_path:
                credential = credentials.Certificate(str(self.settings.firebase_credentials_path))
            options = (
                {"projectId": self.settings.firebase_project_id}
                if self.settings.firebase_project_id else None
            )
            self._app = firebase_admin.initialize_app(credential, options)
            return self._app
        except Exception as exc:
            raise InfrastructureUnavailable("Firebase Admin could not be initialized") from exc

    async def verify(self, token: str) -> FirebaseIdentity:
        app = self._initialize()
        try:
            claims = await asyncio.to_thread(
                auth.verify_id_token,
                token,
                app,
                self.settings.firebase_check_revoked,
            )
        except (
            auth.InvalidIdTokenError,
            auth.ExpiredIdTokenError,
            auth.RevokedIdTokenError,
            auth.UserDisabledError,
        ) as exc:
            raise InvalidFirebaseToken("Invalid or expired Firebase ID token") from exc
        except Exception as exc:
            raise InfrastructureUnavailable("Firebase token verification failed") from exc

        provider = (claims.get("firebase") or {}).get("sign_in_provider")
        if provider != "google.com":
            raise InvalidFirebaseToken("Only Google sign-in is accepted")

        uid = claims.get("uid") or claims.get("sub")
        if not uid:
            raise InvalidFirebaseToken("Firebase token does not contain a user ID")

        return FirebaseIdentity(
            uid=uid,
            email=claims.get("email"),
            display_name=claims.get("name"),
            photo_url=claims.get("picture"),
            email_verified=bool(claims.get("email_verified")),
        )

    async def delete_user(self, uid: str) -> None:
        app = self._initialize()
        try:
            await asyncio.to_thread(auth.delete_user, uid, app)
        except auth.UserNotFoundError:
            return
        except Exception as exc:
            raise InfrastructureUnavailable(
                "Firebase account deletion failed"
            ) from exc
