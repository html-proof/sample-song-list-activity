import pytest
from unittest.mock import AsyncMock

from api import endpoints
from api.errors import Errors
from api.newreleases.newreleases import NewReleases


class FakeNewReleases(NewReleases):
    def __init__(self, response):
        self.api_endpoints = endpoints
        self.errors = Errors()
        self._safe_request = AsyncMock(return_value=response)
        self.get_track_info = AsyncMock(return_value=[{"track_id": "track-1"}])
        self.get_album_info = AsyncMock(return_value=[{"album_id": "album-1"}])


@pytest.mark.asyncio
async def test_track_only_new_releases_return_empty_album_list():
    client = FakeNewReleases({"entities": [{"entity_type": "TR", "seokey": "track-one"}]})

    result = await client.get_new_releases("Malayalam", 10)

    assert result["tracks"] == [{"track_id": "track-1"}]
    assert result["albums"] == []
    client.get_album_info.assert_not_awaited()


@pytest.mark.asyncio
async def test_album_only_new_releases_return_empty_track_list():
    client = FakeNewReleases({"entities": [{"entity_type": "AL", "seokey": "album-one"}]})

    result = await client.get_new_releases("Tamil", 10)

    assert result["tracks"] == []
    assert result["albums"] == [{"album_id": "album-1"}]
    client.get_track_info.assert_not_awaited()
