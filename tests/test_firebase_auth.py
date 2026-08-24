import asyncio
import datetime
import time

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from google.auth import crypt, jwt as google_jwt
from google.auth.exceptions import DefaultCredentialsError

from music_hub.auth.firebase import ADMIN_MODE, PUBLIC_MODE, FirebaseVerifier
from music_hub.auth.errors import InvalidFirebaseToken
from music_hub.auth.public_keys import GooglePublicKeyVerifier, _cache_seconds
from music_hub.config import Settings
from music_hub.errors import InfrastructureUnavailable


PROJECT_ID = "personal-songs"
KEY_ID = "test-key"


@pytest.fixture(scope="module")
def signing_material():
    """A throwaway RSA key plus the self-signed certificate that publishes it."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "test")])
    now = datetime.datetime.now(datetime.timezone.utc)
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=1))
        .sign(key, hashes.SHA256())
    )
    private_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    certificate_pem = certificate.public_bytes(serialization.Encoding.PEM)
    signer = crypt.RSASigner.from_string(private_pem, KEY_ID)
    return signer, certificate_pem.decode()


def make_token(signer, **overrides) -> str:
    issued_at = int(time.time())
    payload = {
        "iss": f"https://securetoken.google.com/{PROJECT_ID}",
        "aud": PROJECT_ID,
        "sub": "firebase-uid-1",
        "auth_time": issued_at,
        "iat": issued_at,
        "exp": issued_at + 3600,
        "email": "listener@example.com",
        "email_verified": True,
        "name": "Listener",
        "firebase": {"sign_in_provider": "google.com"},
    }
    payload.update(overrides)
    return google_jwt.encode(signer, payload).decode()


@pytest.fixture
def public_verifier(signing_material, monkeypatch):
    _, certificate_pem = signing_material
    verifier = GooglePublicKeyVerifier(PROJECT_ID)

    async def certificate_for(key_id):
        if key_id != KEY_ID:
            raise InvalidFirebaseToken("Token was signed with an unrecognized key")
        return certificate_pem

    monkeypatch.setattr(verifier, "certificate_for", certificate_for)
    return verifier


# -- public-key verification -------------------------------------------------


def test_valid_token_is_accepted(public_verifier, signing_material):
    signer, _ = signing_material
    claims = asyncio.run(public_verifier.verify(make_token(signer)))
    assert claims["sub"] == "firebase-uid-1"
    assert claims["email"] == "listener@example.com"


def test_token_for_another_project_is_rejected(public_verifier, signing_material):
    signer, _ = signing_material
    token = make_token(signer, aud="someone-elses-project")
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify(token))


def test_token_with_a_forged_issuer_is_rejected(public_verifier, signing_material):
    signer, _ = signing_material
    token = make_token(signer, iss="https://evil.example.com/personal-songs")
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify(token))


def test_expired_token_is_rejected(public_verifier, signing_material):
    signer, _ = signing_material
    past = int(time.time()) - 7200
    token = make_token(signer, iat=past, exp=past + 3600)
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify(token))


def test_token_without_a_subject_is_rejected(public_verifier, signing_material):
    signer, _ = signing_material
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify(make_token(signer, sub="")))


def test_token_with_a_future_auth_time_is_rejected(public_verifier, signing_material):
    signer, _ = signing_material
    token = make_token(signer, auth_time=int(time.time()) + 3600)
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify(token))


def test_token_signed_by_an_unknown_key_is_rejected(public_verifier, signing_material):
    other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = other_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    rogue_signer = crypt.RSASigner.from_string(pem, "rogue-key")
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify(make_token(rogue_signer)))


def test_unsigned_token_is_rejected(public_verifier):
    # An "alg: none" token carries no signature at all.
    import base64
    import json

    def segment(payload):
        return base64.urlsafe_b64encode(json.dumps(payload).encode()).rstrip(b"=").decode()

    token = ".".join(
        [
            segment({"alg": "none", "kid": KEY_ID}),
            segment({"sub": "firebase-uid-1", "aud": PROJECT_ID}),
            "",
        ]
    )
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify(token))


def test_garbage_is_rejected_as_a_bad_token(public_verifier):
    with pytest.raises(InvalidFirebaseToken):
        asyncio.run(public_verifier.verify("dummy"))


def test_certificate_cache_ttl_follows_cache_control():
    assert _cache_seconds("public, max-age=22780, must-revalidate") == 22780
    assert _cache_seconds(None) == 3600
    assert _cache_seconds("max-age=5") == 60


# -- mode selection ----------------------------------------------------------


def _without_default_credentials(monkeypatch):
    def explode():
        raise DefaultCredentialsError("no ADC")

    monkeypatch.setattr(
        "music_hub.auth.firebase.credentials.ApplicationDefault", explode
    )


def test_public_mode_is_used_when_no_service_account_is_configured(monkeypatch):
    _without_default_credentials(monkeypatch)
    verifier = FirebaseVerifier(Settings(firebase_project_id=PROJECT_ID))
    assert verifier.check() == PUBLIC_MODE


def test_project_id_is_required(monkeypatch):
    _without_default_credentials(monkeypatch)
    verifier = FirebaseVerifier(Settings())
    with pytest.raises(InfrastructureUnavailable) as excinfo:
        verifier.check()
    assert "FIREBASE_PROJECT_ID" in str(excinfo.value)


def test_blank_firebase_credentials_json_is_optional():
    assert Settings(firebase_credentials_json="  ").firebase_credentials_json is None


def test_malformed_credentials_json_is_reported():
    verifier = FirebaseVerifier(
        Settings(firebase_project_id=PROJECT_ID, firebase_credentials_json="{not json")
    )
    with pytest.raises(InfrastructureUnavailable) as excinfo:
        verifier.check()
    assert "not valid JSON" in str(excinfo.value)


def test_credentials_path_must_exist():
    verifier = FirebaseVerifier(
        Settings(
            firebase_project_id=PROJECT_ID, firebase_credentials_path="missing.json"
        )
    )
    with pytest.raises(InfrastructureUnavailable) as excinfo:
        verifier.check()
    assert "FIREBASE_CREDENTIALS_PATH" in str(excinfo.value)


def test_account_deletion_requires_a_service_account(monkeypatch):
    _without_default_credentials(monkeypatch)
    verifier = FirebaseVerifier(Settings(firebase_project_id=PROJECT_ID))
    with pytest.raises(InfrastructureUnavailable) as excinfo:
        asyncio.run(verifier.delete_user("firebase-uid-1"))
    assert "service account" in str(excinfo.value)


# -- identity mapping --------------------------------------------------------


def test_identity_is_built_from_claims():
    identity = FirebaseVerifier._identity(
        {
            "sub": "firebase-uid-1",
            "email": "listener@example.com",
            "email_verified": True,
            "name": "Listener",
            "picture": "https://example.com/a.png",
            "firebase": {"sign_in_provider": "google.com"},
        }
    )
    assert identity.uid == "firebase-uid-1"
    assert identity.display_name == "Listener"
    assert identity.email_verified is True


def test_non_google_sign_in_is_rejected():
    with pytest.raises(InvalidFirebaseToken):
        FirebaseVerifier._identity(
            {"sub": "u1", "firebase": {"sign_in_provider": "password"}}
        )


def test_end_to_end_token_yields_an_identity(monkeypatch, signing_material, public_verifier):
    """A signed token goes all the way through FirebaseVerifier to an identity."""
    signer, _ = signing_material
    _without_default_credentials(monkeypatch)
    verifier = FirebaseVerifier(Settings(firebase_project_id=PROJECT_ID))
    assert verifier.check() == PUBLIC_MODE
    monkeypatch.setattr(verifier, "_public", public_verifier)

    identity = asyncio.run(verifier.verify(make_token(signer)))
    assert identity.uid == "firebase-uid-1"
    assert identity.email == "listener@example.com"
