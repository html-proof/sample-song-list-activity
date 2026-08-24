from contextlib import asynccontextmanager
import json
import ssl
from typing import Any, AsyncIterator

import asyncpg

from music_hub.errors import InfrastructureUnavailable


class Database:
    def __init__(
        self,
        dsn: str | None,
        min_size: int = 1,
        max_size: int = 10,
        require_ssl: bool = True,
        verify_ssl: bool = True,
    ) -> None:
        self.dsn = dsn
        self.min_size = min_size
        self.max_size = max_size
        self.require_ssl = require_ssl
        self.verify_ssl = verify_ssl
        self.pool: asyncpg.Pool | None = None

    @property
    def configured(self) -> bool:
        return bool(self.dsn)

    @property
    def connected(self) -> bool:
        return self.pool is not None

    async def connect(self) -> None:
        if not self.dsn:
            return
        self.pool = await asyncpg.create_pool(
            dsn=self.dsn,
            min_size=self.min_size,
            max_size=self.max_size,
            ssl=self._ssl_parameter(),
            command_timeout=30,
            init=self._initialize_connection,
        )

    def _ssl_parameter(self) -> ssl.SSLContext | str | bool:
        if not self.require_ssl:
            return False
        if not self.verify_ssl:
            # Equivalent to PostgreSQL sslmode=require: encryption is mandatory,
            # but the server certificate is not verified.
            return "require"
        return ssl.create_default_context()

    @staticmethod
    async def _initialize_connection(connection: asyncpg.Connection) -> None:
        for type_name in ("json", "jsonb"):
            await connection.set_type_codec(
                type_name,
                schema="pg_catalog",
                encoder=json.dumps,
                decoder=json.loads,
                format="text",
            )

    async def close(self) -> None:
        if self.pool is not None:
            await self.pool.close()
            self.pool = None

    def require_pool(self) -> asyncpg.Pool:
        if self.pool is None:
            raise InfrastructureUnavailable("PostgreSQL is not configured or connected")
        return self.pool

    async def fetchrow(self, query: str, *args: Any) -> asyncpg.Record | None:
        return await self.require_pool().fetchrow(query, *args)

    async def fetch(self, query: str, *args: Any) -> list[asyncpg.Record]:
        return await self.require_pool().fetch(query, *args)

    async def execute(self, query: str, *args: Any) -> str:
        return await self.require_pool().execute(query, *args)

    @asynccontextmanager
    async def transaction(self) -> AsyncIterator[asyncpg.Connection]:
        async with self.require_pool().acquire() as connection:
            async with connection.transaction():
                yield connection

    async def ping(self) -> bool:
        if self.pool is None:
            return False
        try:
            return await self.pool.fetchval("SELECT TRUE") is True
        except (asyncpg.PostgresError, OSError):
            return False
