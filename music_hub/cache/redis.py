import json
from typing import Any
from uuid import uuid4

from redis.asyncio import Redis as NativeRedis
from upstash_redis.asyncio import Redis as UpstashRedis


class RedisCache:
    """Optional Redis cache. All methods degrade safely when Redis is absent."""

    def __init__(
        self,
        url: str | None,
        namespace: str = "music-hub",
        rest_url: str | None = None,
        rest_token: str | None = None,
    ) -> None:
        self.url = url
        self.namespace = namespace
        self.rest_url = rest_url
        self.rest_token = rest_token
        self.client: NativeRedis | UpstashRedis | None = None
        self._using_rest = False

    @property
    def configured(self) -> bool:
        return bool(self.url or (self.rest_url and self.rest_token))

    @property
    def connected(self) -> bool:
        return self.client is not None

    def key(self, value: str) -> str:
        return f"{self.namespace}:{value}"

    async def connect(self) -> None:
        if self.url:
            self.client = NativeRedis.from_url(self.url, decode_responses=True)
        elif self.rest_url and self.rest_token:
            self.client = UpstashRedis(
                url=self.rest_url,
                token=self.rest_token,
                allow_telemetry=False,
            )
            self._using_rest = True
        if self.client is not None:
            await self.client.ping()
            probe_key = self.key(f"connection-probe:{uuid4().hex}")
            await self.client.set(probe_key, "1", ex=10)
            await self.client.delete(probe_key)

    async def close(self) -> None:
        if self.client is not None:
            if self._using_rest:
                await self.client.close()
            else:
                await self.client.aclose()
            self.client = None
            self._using_rest = False

    async def get_json(self, key: str) -> Any | None:
        if self.client is None:
            return None
        value = await self.client.get(self.key(key))
        if value is None or not isinstance(value, str):
            return value
        return json.loads(value)

    async def set_json(self, key: str, value: Any, ttl: int) -> None:
        if self.client is not None:
            await self.client.set(self.key(key), json.dumps(value, default=str), ex=ttl)

    async def delete(self, key: str) -> None:
        if self.client is not None:
            await self.client.delete(self.key(key))

    async def delete_pattern(self, pattern: str) -> None:
        if self.client is None:
            return
        cursor = 0
        while True:
            cursor_value, keys = await self.client.scan(
                cursor,
                match=self.key(pattern),
                count=100,
            )
            if keys:
                await self.client.delete(*keys)
            cursor = int(cursor_value)
            if cursor == 0:
                break

    async def members(self, key: str) -> set[str]:
        if self.client is None:
            return set()
        return set(await self.client.smembers(self.key(key)))

    async def add_to_set(self, key: str, values: list[str], ttl: int) -> None:
        if self.client is None or not values:
            return
        namespaced = self.key(key)
        if self._using_rest:
            async with self.client.multi() as pipe:
                pipe.sadd(namespaced, *values)
                pipe.expire(namespaced, ttl)
                await pipe.exec()
        else:
            async with self.client.pipeline(transaction=True) as pipe:
                pipe.sadd(namespaced, *values)
                pipe.expire(namespaced, ttl)
                await pipe.execute()

    async def increment_window(self, key: str, ttl: int) -> int:
        if self.client is None:
            return 0
        namespaced = self.key(key)
        if self._using_rest:
            async with self.client.multi() as pipe:
                pipe.incr(namespaced)
                pipe.expire(namespaced, ttl, nx=True)
                result = await pipe.exec()
        else:
            async with self.client.pipeline(transaction=True) as pipe:
                pipe.incr(namespaced)
                pipe.expire(namespaced, ttl, nx=True)
                result = await pipe.execute()
        return int(result[0])

    async def ping(self) -> bool:
        if self.client is None:
            return False
        try:
            return bool(await self.client.ping())
        except Exception:
            return False
