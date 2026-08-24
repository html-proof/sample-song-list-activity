import pytest
from pydantic import ValidationError

from music_hub.cache import redis as redis_module
from music_hub.cache.redis import RedisCache
from music_hub.config import Settings


class FakeUpstashRedis:
    def __init__(self, *, url, token, allow_telemetry):
        self.url = url
        self.token = token
        self.allow_telemetry = allow_telemetry
        self.values = {}
        self.closed = False

    async def ping(self):
        return "PONG"

    async def get(self, key):
        return self.values.get(key)

    async def set(self, key, value, ex=None):
        self.values[key] = value
        return "OK"

    async def delete(self, *keys):
        for key in keys:
            self.values.pop(key, None)

    async def close(self):
        self.closed = True


@pytest.mark.asyncio
async def test_rest_cache_connects_and_round_trips_json(monkeypatch):
    monkeypatch.setattr(redis_module, "UpstashRedis", FakeUpstashRedis)
    cache = RedisCache(
        None,
        rest_url="https://redis.example.test",
        rest_token="secret",
    )

    await cache.connect()
    assert cache.client.values == {}
    await cache.set_json("result", {"ok": True}, 60)

    assert cache.configured is True
    assert cache.connected is True
    assert await cache.get_json("result") == {"ok": True}
    assert cache.client.allow_telemetry is False

    client = cache.client
    await cache.close()

    assert client.closed is True
    assert cache.connected is False


def test_upstash_rest_credentials_must_be_configured_together():
    with pytest.raises(ValidationError):
        Settings(
            database_url=None,
            redis_url=None,
            upstash_redis_rest_url="https://redis.example.test",
            upstash_redis_rest_token=None,
        )


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("redis.example.test", "https://redis.example.test"),
        ("//redis.example.test", "https://redis.example.test"),
        (
            "[https://redis.example.test](https://redis.example.test)",
            "https://redis.example.test",
        ),
        ('"https://redis.example.test/"', "https://redis.example.test"),
    ],
)
def test_upstash_rest_url_is_normalized(value, expected):
    settings = Settings(
        database_url=None,
        redis_url=None,
        upstash_redis_rest_url=value,
        upstash_redis_rest_token="secret",
    )

    assert settings.upstash_redis_rest_url == expected


def test_upstash_rest_url_rejects_non_http_protocols():
    with pytest.raises(ValidationError, match="valid HTTP or HTTPS URL"):
        Settings(
            database_url=None,
            redis_url=None,
            upstash_redis_rest_url="redis://redis.example.test",
            upstash_redis_rest_token="secret",
        )
