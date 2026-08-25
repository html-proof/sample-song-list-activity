from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from music_hub.config import Settings
from music_hub.services.search import SearchService


def make_service():
    provider = AsyncMock()
    history = AsyncMock()
    cache = AsyncMock()
    cache.get_json.return_value = None
    settings = Settings(database_url=None, redis_url=None)
    return SearchService(provider, history, cache, settings), provider, history, cache


@pytest.mark.asyncio
async def test_movie_search_promotes_tracks_from_matching_soundtrack():
    service, provider, history, cache = make_service()
    provider.search_songs.return_value = [
        {"track_id": "unrelated", "title": "Champ", "language": "Haryanvi"}
    ]
    provider.search_albums.return_value = [
        {
            "album_id": "2236606",
            "seokey": "sarkar-tamil",
            "title": "Sarkar (Tamil) (Original Motion Picture Soundtrack)",
            "language": "Tamil",
        }
    ]
    provider.search_artists.return_value = []
    provider.get_album.return_value = {
        "tracks": [
            {"track_id": "1", "seokey": "simtaangaran", "title": "Simtaangaran"},
            {"track_id": "2", "seokey": "top-tucker", "title": "Top Tucker"},
        ]
    }

    result = await service.search(uuid4(), "Sarkar Tamil movie", "all", 3)

    assert [song["title"] for song in result["songs"]] == [
        "Simtaangaran",
        "Top Tucker",
        "Champ",
    ]
    provider.get_album.assert_awaited_once_with("sarkar-tamil")
    assert 30 <= cache.set_json.await_args.args[2] <= 60
    history.add_search.assert_awaited_once()


@pytest.mark.asyncio
async def test_song_filter_uses_soundtrack_album_for_movie_query():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = []
    provider.search_albums.return_value = [
        {
            "seokey": "sarkar-tamil",
            "title": "Sarkar Tamil Original Motion Picture Soundtrack",
            "language": "Tamil",
        }
    ]
    provider.get_album.return_value = {
        "tracks": [{"track_id": "1", "title": "Simtaangaran"}]
    }

    result = await service.search(uuid4(), "Sarkar Tamil movie", "songs", 10)

    assert [song["title"] for song in result["songs"]] == ["Simtaangaran"]
    provider.search_albums.assert_awaited_once_with("Sarkar Tamil movie", 10)


@pytest.mark.asyncio
async def test_regular_song_search_does_not_fetch_an_album():
    service, provider, _, cache = make_service()
    provider.search_songs.return_value = [{"track_id": "1", "title": "Simtaangaran"}]

    result = await service.search(uuid4(), "Simtaangaran", "songs", 10)

    assert result["songs"][0]["title"] == "Simtaangaran"
    provider.search_albums.assert_not_awaited()
    provider.get_album.assert_not_awaited()
    assert 30 <= cache.set_json.await_args.args[2] <= 60


@pytest.mark.asyncio
async def test_every_search_response_uses_a_short_cache_ttl():
    """Search results go stale the moment the user types another character."""
    service, provider, _, cache = make_service()
    provider.search_albums.return_value = [{"album_id": "1", "title": "Sarkar"}]

    await service.search(uuid4(), "Sarkar", "albums", 10)

    assert 30 <= cache.set_json.await_args.args[2] <= 60
