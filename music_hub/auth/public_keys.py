"""Credential-free verification of Firebase ID tokens.

Firebase signs ID tokens with rotating Google keys whose public certificates are
published at a well-known, unauthenticated URL. Verifying a token therefore needs
only the project ID -- a service account is required for privileged Admin
operations (revocation checks, account deletion), not for authentication.

Reference: https://firebase.google.com/docs/auth/admin/verify-id-tokens
"""

import asyncio
import logging
import re
import time

import aiohttp
from google.auth import jwt as google_jwt

from music_hub.auth.errors import InvalidFirebaseToken
from music_hub.errors import InfrastructureUnavailable


logger = logging.getLogger("music_hub.auth")

FIREBASE_CERTS_URL = (
    "https://www.googleapis.com/robot/v1/metadata/x509/"
    "securetoken@system.gserviceaccount.com"
)
_MAX_AGE = re.compile(r"max-age=(\d+)", re.IGNORECASE)
_FALLBACK_CACHE_SECONDS = 3600
_MAX_UID_LENGTH = 128
_CLOCK_SKEW_SECONDS = 60


def _cache_seconds(cache_control: str | None) -> int:
    match = _MAX_AGE.search(cache_control or "")
    if not match:
        return _FALLBACK_CACHE_SECONDS
    return max(int(match.group(1)), 60)


class GooglePublicKeyVerifier:
    """Verifies Firebase ID tokens against Google's published signing certificates."""

    def __init__(
        self,
        project_id: str,
        certs_url: str = FIREBASE_CERTS_URL,
        timeout_seconds: float = 10,
    ) -> None:
        if not project_id:
            raise ValueError("project_id is required")
        self.project_id = project_id
        self.certs_url = certs_url
        self.timeout_seconds = timeout_seconds
        self._certs: dict[str, str] = {}
        self._expires_at = 0.0
        self._lock = asyncio.Lock()

    @property
    def issuer(self) -> str:
        return f"https://securetoken.google.com/{self.project_id}"

    async def _fetch_certs(self) -> None:
        timeout = aiohttp.ClientTimeout(total=self.timeout_seconds)
        try:
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(self.certs_url) as response:
                    response.raise_for_status()
                    certs = await response.json(content_type=None)
                    ttl = _cache_seconds(response.headers.get("Cache-Control"))
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            raise InfrastructureUnavailable(
                "Google's Firebase signing certificates could not be retrieved"
            ) from exc
        if not isinstance(certs, dict) or not certs:
            raise InfrastructureUnavailable(
                "Google returned an unusable Firebase certificate document"
            )
        self._certs = {str(kid): str(cert) for kid, cert in certs.items()}
        self._expires_at = time.monotonic() + ttl
        logger.info("Loaded %d Firebase signing certificates (ttl %ds)", len(certs), ttl)

    async def certificate_for(self, key_id: str) -> str:
        """Return the certificate for a key id, refreshing once on a cache miss."""
        async with self._lock:
            if time.monotonic() >= self._expires_at:
                await self._fetch_certs()
            if key_id not in self._certs:
                # Google rotates signing keys; refresh before rejecting the token.
                await self._fetch_certs()
            certificate = self._certs.get(key_id)
        if certificate is None:
            raise InvalidFirebaseToken("Token was signed with an unrecognized key")
        return certificate

    async def warm(self) -> None:
        async with self._lock:
            if time.monotonic() >= self._expires_at:
                await self._fetch_certs()

    async def verify(self, token: str) -> dict:
        try:
            header = google_jwt.decode_header(token)
        except Exception as exc:
            raise InvalidFirebaseToken("Token is not a well-formed JWT") from exc

        if header.get("alg") != "RS256":
            raise InvalidFirebaseToken("Token is not signed with RS256")
        key_id = header.get("kid")
        if not key_id:
            raise InvalidFirebaseToken("Token header does not name a signing key")

        certificate = await self.certificate_for(str(key_id))
        try:
            # Verifies the RS256 signature and the aud/exp/iat claims.
            claims = await asyncio.to_thread(
                google_jwt.decode,
                token,
                {str(key_id): certificate},
                True,
                self.project_id,
            )
        except ValueError as exc:
            raise InvalidFirebaseToken("Invalid or expired Firebase ID token") from exc

        self._check_claims(claims)
        return claims

    def _check_claims(self, claims: dict) -> None:
        if claims.get("iss") != self.issuer:
            raise InvalidFirebaseToken("Token was issued for a different Firebase project")

        subject = claims.get("sub")
        if not isinstance(subject, str) or not subject:
            raise InvalidFirebaseToken("Token does not contain a user ID")
        if len(subject) > _MAX_UID_LENGTH:
            raise InvalidFirebaseToken("Token contains an oversized user ID")

        auth_time = claims.get("auth_time")
        if auth_time is not None:
            try:
                authenticated_at = float(auth_time)
            except (TypeError, ValueError) as exc:
                raise InvalidFirebaseToken("Token has an unreadable auth_time claim") from exc
            if authenticated_at > time.time() + _CLOCK_SKEW_SECONDS:
                raise InvalidFirebaseToken("Token reports a future authentication time")
