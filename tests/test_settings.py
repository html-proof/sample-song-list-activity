from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from pydantic import ValidationError

from music_hub.schemas.history import ListeningHistoryCreate, MusicEventCreate
from music_hub.schemas.library import FollowedArtistCreate, LikedSongCreate
from music_hub.schemas.settings import (
    AppSettings,
    DownloadSettingsUpdate,
    PlaybackSettingsUpdate,
    RecommendationSettingsUpdate,
)
from music_hub.services.history import HistoryService
from music_hub.services.library import LibraryService
from music_hub.services.settings import SettingsService


def test_settings_schema_supplies_all_group_defaults():
    settings = AppSettings()

    assert settings.playback.autoplay is True
    assert settings.downloads.wifi_only is True
    assert settings.recommendations.diversity_level == 50
    assert settings.privacy.save_search_history is True


def test_playback_crossfade_is_bounded():
    with pytest.raises(ValidationError):
        PlaybackSettingsUpdate(crossfade_seconds=13)


def test_download_retention_can_be_explicitly_cleared():
    payload = DownloadSettingsUpdate(delete_played_after_days=None)

    assert payload.model_dump(exclude_unset=True) == {
        "delete_played_after_days": None,
    }


@pytest.mark.asyncio
async def test_recommendation_change_invalidates_user_feed_cache():
    user_id = uuid4()
    repository = AsyncMock()
    repository.update_group.return_value = {"enabled": False}
    cache = AsyncMock()
    service = SettingsService(repository, cache)

    result = await service.update(
        user_id,
        "recommendations",
        RecommendationSettingsUpdate(enabled=False),
    )

    assert result == {"enabled": False}
    cache.delete_pattern.assert_awaited_once_with(
        f"recommendations:{user_id}:*"
    )
    cache.delete.assert_any_await(f"settings:{user_id}")
    cache.delete.assert_any_await(f"seen:{user_id}")


@pytest.mark.asyncio
async def test_disabled_listening_history_prevents_collection():
    repository = AsyncMock()
    settings = AsyncMock()
    settings.get_group.return_value = {"save_listening_history": False}
    service = HistoryService(repository, settings)

    result = await service.record_listen(
        uuid4(),
        ListeningHistoryCreate(song_id="song-1"),
    )

    assert result["stored"] is False
    repository.add_listen.assert_not_awaited()


@pytest.mark.asyncio
async def test_disabled_analytics_prevents_event_collection():
    repository = AsyncMock()
    settings = AsyncMock()
    settings.get_group.return_value = {"analytics_enabled": False}
    service = HistoryService(repository, settings)

    result = await service.record_event(
        uuid4(),
        MusicEventCreate(event_type="play", song_id="song-1"),
    )

    assert result["stored"] is False
    repository.add_event.assert_not_awaited()


@pytest.mark.asyncio
async def test_listening_signal_invalidates_only_the_owning_users_feed():
    user_id = uuid4()
    repository = AsyncMock()
    repository.add_listen.return_value = {"id": "listen-1"}
    cache = AsyncMock()
    service = HistoryService(repository, cache=cache)

    await service.record_listen(
        user_id,
        ListeningHistoryCreate(song_id="song-1"),
    )

    cache.delete_pattern.assert_awaited_once_with(
        f"recommendations:{user_id}:*"
    )


@pytest.mark.asyncio
async def test_library_signals_invalidate_only_the_owning_users_feed():
    user_id = uuid4()
    repository = AsyncMock()
    repository.like_song.return_value = {"song_id": "song-1"}
    repository.follow_artist.return_value = {"artist_id": "artist-1"}
    cache = AsyncMock()
    service = LibraryService(repository, cache)

    await service.like(user_id, LikedSongCreate(song_id="song-1"))
    await service.follow(
        user_id,
        FollowedArtistCreate(artist_id="artist-1"),
    )

    assert cache.delete_pattern.await_count == 2
    for call in cache.delete_pattern.await_args_list:
        assert call.args == (f"recommendations:{user_id}:*",)
