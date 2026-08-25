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
    settings = Settings(database_url=None, redis_url=None, search_cache_ttl=180)
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
    assert cache.set_json.await_args.args[2] == 60
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
    assert cache.set_json.await_args.args[2] == 60


@pytest.mark.asyncio
async def test_album_search_keeps_normal_search_cache_ttl():
    service, provider, _, cache = make_service()
    provider.search_albums.return_value = [{"album_id": "1", "title": "Sarkar"}]

    await service.search(uuid4(), "Sarkar", "albums", 10)

    assert cache.set_json.await_args.args[2] == 180


@pytest.mark.asyncio
async def test_every_result_is_grouped_and_carries_its_type():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [{"track_id": "1", "title": "Pattalam"}]
    provider.search_albums.return_value = [{"album_id": "2", "title": "Pattalam"}]
    provider.search_artists.return_value = [{"artist_id": "3", "name": "Vidyasagar"}]
    provider.search_playlists.return_value = [
        {"playlist_id": "4", "title": "Malayalam Hits", "provider": "gaana"}
    ]

    result = await service.search(uuid4(), "pattalam", "all", 10)

    assert result["query"] == "pattalam"
    assert [item["type"] for item in result["songs"]] == ["song"]
    assert [item["type"] for item in result["albums"]] == ["album"]
    assert [item["type"] for item in result["artists"]] == ["artist"]
    assert [item["type"] for item in result["playlists"]] == ["playlist"]


@pytest.mark.asyncio
async def test_a_typed_search_returns_only_that_group():
    service, provider, _, _ = make_service()
    provider.search_artists.return_value = [{"artist_id": "3", "name": "A. R. Rahman"}]

    result = await service.search(uuid4(), "a r rahman", "artists", 10)

    assert [item["name"] for item in result["artists"]] == ["A. R. Rahman"]
    assert result["songs"] == []
    assert result["albums"] == []
    assert result["playlists"] == []
    provider.search_songs.assert_not_awaited()


@pytest.mark.asyncio
async def test_exact_title_outranks_a_merely_similar_one():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [
        {"track_id": "1", "title": "Pattalam Police"},
        {"track_id": "2", "title": "Nothing Alike"},
        {"track_id": "3", "title": "Pattalam"},
    ]

    result = await service.search(uuid4(), "pattalam", "songs", 10)

    assert [song["title"] for song in result["songs"]] == [
        "Pattalam",
        "Pattalam Police",
        "Nothing Alike",
    ]


@pytest.mark.asyncio
async def test_ranking_ignores_case_and_punctuation_and_keeps_unicode():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [
        {"track_id": "1", "title": "Unrelated"},
        {"track_id": "2", "title": "പട്ടാളം"},
    ]

    result = await service.search(uuid4(), "  പട്ടാളം!  ", "songs", 10)

    assert result["songs"][0]["title"] == "പട്ടാളം"


@pytest.mark.asyncio
async def test_duplicate_artists_differing_only_in_case_collapse():
    service, provider, _, _ = make_service()
    provider.search_artists.return_value = [
        {"artist_id": "1", "name": "Arijit Singh"},
        {"artist_id": "2", "name": "ARIJIT SINGH"},
        {"artist_id": "3", "name": "Arijit singh"},
    ]

    result = await service.search(uuid4(), "arijit singh", "artists", 10)

    assert [item["name"] for item in result["artists"]] == ["Arijit Singh"]


@pytest.mark.asyncio
async def test_songs_sharing_a_title_but_not_an_artist_both_survive():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [
        {"track_id": "1", "title": "Roja", "artists": "A. R. Rahman", "duration": "300"},
        {"track_id": "2", "title": "Roja", "artists": "Someone Else", "duration": "280"},
        {"track_id": "3", "title": "Roja", "artists": "A. R. Rahman", "duration": "300"},
    ]

    result = await service.search(uuid4(), "roja", "songs", 10)

    assert [song["track_id"] for song in result["songs"]] == ["1", "2"]


@pytest.mark.asyncio
async def test_top_result_is_the_artist_when_the_query_is_an_artist_name():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [{"track_id": "1", "title": "Arijit Singh Hits"}]
    provider.search_artists.return_value = [{"artist_id": "2", "name": "Arijit Singh"}]

    result = await service.search(uuid4(), "arijit singh", "all", 10)

    assert result["top_result"]["type"] == "artist"
    assert result["top_result"]["name"] == "Arijit Singh"


@pytest.mark.asyncio
async def test_top_result_is_the_song_when_the_query_is_a_song_title():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [{"track_id": "1", "title": "Tum Hi Ho"}]
    provider.search_albums.return_value = [{"album_id": "2", "title": "Tum Hi Ho (Remix)"}]
    provider.search_artists.return_value = [{"artist_id": "3", "name": "Arijit Singh"}]

    result = await service.search(uuid4(), "tum hi ho", "all", 10)

    assert result["top_result"]["type"] == "song"
    assert result["top_result"]["title"] == "Tum Hi Ho"


@pytest.mark.asyncio
async def test_one_failing_group_does_not_empty_the_others():
    service, provider, _, _ = make_service()
    provider.search_songs.side_effect = RuntimeError("provider down")
    provider.search_artists.return_value = [{"artist_id": "1", "name": "Vidyasagar"}]

    result = await service.search(uuid4(), "vidyasagar", "all", 10)

    assert result["songs"] == []
    assert [item["name"] for item in result["artists"]] == ["Vidyasagar"]


@pytest.mark.asyncio
async def test_an_album_named_like_the_query_fills_in_weak_song_results():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [
        {"track_id": "9", "title": "Dinkiri Pattalam"}
    ]
    provider.search_albums.return_value = [
        {
            "album_id": "1",
            "seokey": "pattalam",
            "title": "Pattalam (Original Motion Picture Soundtrack)",
        }
    ]
    provider.get_album.return_value = {
        "tracks": [{"track_id": "1", "seokey": "pattalam", "title": "Pattalam"}]
    }

    result = await service.search(uuid4(), "pattalam", "all", 10)

    assert [song["title"] for song in result["songs"]] == [
        "Pattalam",
        "Dinkiri Pattalam",
    ]
    assert result["top_result"]["type"] == "song"


@pytest.mark.asyncio
async def test_a_compilation_that_merely_mentions_the_query_is_not_promoted():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [
        {"track_id": "9", "title": "Heeriye (feat. Arijit Singh)"}
    ]
    provider.search_albums.return_value = [
        {"album_id": "1", "seokey": "hits", "title": "Arijit Singh Bollywood Hits"}
    ]

    result = await service.search(uuid4(), "arijit singh", "all", 10)

    assert [song["title"] for song in result["songs"]] == [
        "Heeriye (feat. Arijit Singh)"
    ]
    provider.get_album.assert_not_awaited()


@pytest.mark.asyncio
async def test_a_strong_song_match_never_triggers_an_album_lookup():
    service, provider, _, _ = make_service()
    provider.search_songs.return_value = [{"track_id": "1", "title": "Pattalam"}]
    provider.search_albums.return_value = [
        {"album_id": "2", "seokey": "pattalam", "title": "Pattalam"}
    ]

    await service.search(uuid4(), "pattalam", "all", 10)

    provider.get_album.assert_not_awaited()
