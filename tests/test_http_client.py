import asyncio
from unittest.mock import AsyncMock

import pytest

from api.errors import Errors
from api.gaanapy import GaanaPy


class FakeResponse:
    def __init__(self, status, payload=None):
        self.status = status
        self.payload = payload

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        return False

    async def json(self):
        return self.payload


class FakeSession:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = 0

    def request(self, method, url, **kwargs):
        self.calls += 1
        return self.responses.pop(0)


def client_with(responses):
    client = GaanaPy.__new__(GaanaPy)
    client.aiohttp = FakeSession(responses)
    client.errors = Errors()
    client._request_semaphore = asyncio.Semaphore(1)
    return client


@pytest.mark.asyncio
async def test_safe_request_retries_server_error(monkeypatch):
    client = client_with([FakeResponse(503), FakeResponse(200, {"ok": True})])
    sleep = AsyncMock()
    monkeypatch.setattr("api.gaanapy.asyncio.sleep", sleep)

    result = await client._safe_request("GET", "https://example.test")

    assert result == {"ok": True}
    assert client.aiohttp.calls == 2
    sleep.assert_awaited_once()


@pytest.mark.asyncio
async def test_safe_request_does_not_retry_not_found(monkeypatch):
    client = client_with([FakeResponse(404)])
    sleep = AsyncMock()
    monkeypatch.setattr("api.gaanapy.asyncio.sleep", sleep)

    result = await client._safe_request("GET", "https://example.test")

    assert result == {"error": "Unable to find any results!"}
    assert client.aiohttp.calls == 1
    sleep.assert_not_awaited()
