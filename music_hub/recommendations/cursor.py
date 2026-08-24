import base64
import hashlib
import hmac
import json
import time


class InvalidCursor(ValueError):
    pass


class CursorCodec:
    def __init__(self, secret: str, max_age_seconds: int = 86400) -> None:
        self.secret = secret.encode("utf-8")
        self.max_age_seconds = max_age_seconds

    def encode(self, seed: str, offset: int) -> str:
        payload = {"seed": seed, "offset": offset, "issued_at": int(time.time())}
        raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
        signature = hmac.new(self.secret, raw, hashlib.sha256).digest()
        return base64.urlsafe_b64encode(raw + b"." + signature).decode("ascii").rstrip("=")

    def decode(self, cursor: str) -> tuple[str, int]:
        try:
            padded = cursor + "=" * (-len(cursor) % 4)
            token = base64.urlsafe_b64decode(padded.encode("ascii"))
            canonical = base64.urlsafe_b64encode(token).decode("ascii").rstrip("=")
            if not hmac.compare_digest(canonical, cursor):
                raise InvalidCursor("Cursor encoding is invalid")
            signature_size = hashlib.sha256().digest_size
            separator_index = len(token) - signature_size - 1
            if separator_index < 1 or token[separator_index : separator_index + 1] != b".":
                raise InvalidCursor("Cursor structure is invalid")
            raw = token[:separator_index]
            signature = token[-signature_size:]
            expected = hmac.new(self.secret, raw, hashlib.sha256).digest()
            if not hmac.compare_digest(signature, expected):
                raise InvalidCursor("Cursor signature is invalid")
            payload = json.loads(raw)
            issued_at = int(payload["issued_at"])
            if int(time.time()) - issued_at > self.max_age_seconds:
                raise InvalidCursor("Cursor has expired")
            seed = str(payload["seed"])
            offset = int(payload["offset"])
            if not seed or offset < 0:
                raise InvalidCursor("Cursor payload is invalid")
            return seed, offset
        except InvalidCursor:
            raise
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            raise InvalidCursor("Cursor is malformed") from exc
