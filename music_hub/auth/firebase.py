import asyncio
import json
import logging
from dataclasses import dataclass

import firebase_admin
from firebase_admin import auth, credentials
from google.auth.exceptions import GoogleAuthError

from music_hub.auth.errors import InvalidFirebaseToken
from music_hub.auth.public_keys import GooglePublicKeyVerifier
from music_hub.config import Settings
from music_hub.errors import InfrastructureUnavailable


logger = logging.getLogger("music_hub.auth")

__all__ = ["FirebaseIdentity", "FirebaseVerifier", "InvalidFirebaseToken"]

ADMIN_MODE = "admin"
PUBLIC_MODE = "public"


@dataclass(frozen=True)
class FirebaseIdentity:
    uid: str
    email: str | None
    display_name: str | None
    photo_url: str | None
    email_verified: bool


class FirebaseVerifier:
    """Verifies Firebase ID tokens, with or without a service-account credential.

    Two modes:

    * ``admin``  - a service account is configured, so the Admin SDK is used and
      privileged operations (token revocation checks, account deletion) work.
    * ``public`` - no service account is configured. ID tokens are still verified
      in full against Google's published signing certificates, which is all
      authentication requires; privileged operations are refused.
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._app: firebase_admin.App | None = None
        self._public: GooglePublicKeyVerifier | None = None
        self._mode: str | None = None

    # -- configuration -----------------------------------------------------

    @property
    def project_id(self) -> str | None:
        return self.settings.firebase_project_id

    def _service_account_credential(self) -> credentials.Base | None:
        """Build a service-account credential, or return None if none is configured.

        Deployments that cannot ship a file into the image (Render, Fly, Cloud
        Run) set FIREBASE_CREDENTIALS_JSON instead of FIREBASE_CREDENTIALS_PATH.
        A credential that is configured but broken is an error, never a silent
        downgrade to public-key mode.
        """
        if self.settings.firebase_credentials_json:
            raw = self.settings.firebase_credentials_json.get_secret_value()
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise InfrastructureUnavailable(
                    "FIREBASE_CREDENTIALS_JSON is not valid JSON"
                ) from exc
            return credentials.Certificate(payload)

        if self.settings.firebase_credentials_path:
            path = self.settings.firebase_credentials_path
            if not path.is_file():
                raise InfrastructureUnavailable(
                    f"FIREBASE_CREDENTIALS_PATH does not point at a readable file: {path}"
                )
            return credentials.Certificate(str(path))

        try:
            default = credentials.ApplicationDefault()
            default.get_credential()  # ApplicationDefault resolves lazily.
            return default
        except Exception:
            # No Application Default Credentials in this environment.
            return None

    def _resolve(self) -> str:
        """Select and initialize a verification mode. Idempotent."""
        if self._mode is not None:
            return self._mode

        credential = self._service_account_credential()
        project_id = self.project_id or getattr(credential, "project_id", None)
        if not project_id:
            raise InfrastructureUnavailable(
                "FIREBASE_PROJECT_ID is not set and could not be derived from the "
                "Firebase credentials; ID tokens cannot be verified without it."
            )

        if credential is None:
            self._public = GooglePublicKeyVerifier(project_id)
            self._mode = PUBLIC_MODE
            logger.info(
                "Verifying Firebase ID tokens for project %s using Google's public "
                "certificates. Set FIREBASE_CREDENTIALS_JSON to enable revocation "
                "checks and account deletion.",
                project_id,
            )
            if self.settings.firebase_check_revoked:
                logger.warning(
                    "FIREBASE_CHECK_REVOKED is enabled but requires a service "
                    "account; revoked tokens stay valid until they expire."
                )
            return self._mode

        try:
            self._app = firebase_admin.get_app()
        except ValueError:
            try:
                self._app = firebase_admin.initialize_app(
                    credential, {"projectId": project_id}
                )
            except Exception as exc:
                raise InfrastructureUnavailable(
                    "Firebase Admin could not be initialized"
                ) from exc
        self._mode = ADMIN_MODE
        logger.info("Firebase Admin initialized for project %s", project_id)
        return self._mode

    def check(self) -> str:
        """Eagerly resolve the mode so misconfiguration surfaces at startup."""
        return self._resolve()

    async def warm(self) -> str:
        """Resolve the mode and pre-fetch signing certificates."""
        mode = self._resolve()
        if mode == PUBLIC_MODE:
            await self._public.warm()
        return mode

    # -- verification ------------------------------------------------------

    async def verify(self, token: str) -> FirebaseIdentity:
        if self._resolve() == PUBLIC_MODE:
            claims = await self._public.verify(token)
        else:
            claims = await self._verify_with_admin_sdk(token)
        return self._identity(claims)

    async def _verify_with_admin_sdk(self, token: str) -> dict:
        try:
            return await asyncio.to_thread(
                auth.verify_id_token,
                token,
                self._app,
                self.settings.firebase_check_revoked,
            )
        except (
            auth.InvalidIdTokenError,
            auth.ExpiredIdTokenError,
            auth.RevokedIdTokenError,
            auth.UserDisabledError,
        ) as exc:
            raise InvalidFirebaseToken("Invalid or expired Firebase ID token") from exc
        except ValueError as exc:
            # firebase-admin raises a plain ValueError for malformed tokens and for
            # tokens whose audience belongs to another project. Both are the
            # caller's fault, not an outage.
            raise InvalidFirebaseToken("Invalid or expired Firebase ID token") from exc
        except GoogleAuthError as exc:
            logger.exception("Firebase credentials rejected while verifying an ID token")
            raise InfrastructureUnavailable(
                "Firebase credentials are missing or invalid"
            ) from exc
        except Exception as exc:
            logger.exception("Firebase token verification failed unexpectedly")
            raise InfrastructureUnavailable("Firebase token verification failed") from exc

    @staticmethod
    def _identity(claims: dict) -> FirebaseIdentity:
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

    # -- privileged operations --------------------------------------------

    async def delete_user(self, uid: str) -> None:
        if self._resolve() == PUBLIC_MODE:
            raise InfrastructureUnavailable(
                "Deleting a Firebase account requires a service account; set "
                "FIREBASE_CREDENTIALS_JSON to enable account deletion."
            )
        try:
            await asyncio.to_thread(auth.delete_user, uid, self._app)
        except auth.UserNotFoundError:
            return
        except Exception as exc:
            logger.exception("Firebase account deletion failed for uid %s", uid)
            raise InfrastructureUnavailable("Firebase account deletion failed") from exc
