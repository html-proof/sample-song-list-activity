from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from music_hub.providers.gaana.provider import GaanaProvider
from music_hub.services.onboarding import OnboardingService


def make_service():
    preferences = AsyncMock()
    provider = AsyncMock()
    cache = AsyncMock()
    cache.get_json.return_value = None
    return OnboardingService(preferences, provider, cache), preferences, provider, cache


@pytest.mark.asyncio
async def test_suggested_artists_uses_the_requested_languages():
    service, preferences, provider, _ = make_service()
    provider.suggested_artists.return_value = [{"artist_id": "1", "name": "Sushin Shyam"}]

    result = await service.suggested_artists(uuid4(), ["Malayalam"], 5)

    provider.suggested_artists.assert_awaited_once_with(["Malayalam"], 5)
    preferences.get_languages.assert_not_awaited()
    assert [artist["name"] for artist in result] == ["Sushin Shyam"]


@pytest.mark.asyncio
async def test_suggested_artists_falls_back_to_saved_languages():
    service, preferences, provider, _ = make_service()
    preferences.get_languages.return_value = [{"language_code": "Tamil", "priority": 1}]
    provider.suggested_artists.return_value = []

    await service.suggested_artists(uuid4(), ["   "], 5)

    provider.suggested_artists.assert_awaited_once_with(["Tamil"], 5)


@pytest.mark.asyncio
async def test_suggested_artists_serves_the_cached_list():
    service, _, provider, cache = make_service()
    cache.get_json.return_value = [{"artist_id": "9", "name": "Cached"}]

    result = await service.suggested_artists(uuid4(), ["Hindi"], 5)

    provider.suggested_artists.assert_not_awaited()
    assert [artist["name"] for artist in result] == ["Cached"]


@pytest.mark.asyncio
async def test_suggested_artists_ranks_leads_above_featured_artists():
    provider = GaanaProvider()
    provider.trending = AsyncMock(
        return_value=[
            {"artist_seokeys": "lead, guest"},
            {"artist_seokeys": "lead"},
            {"artist_seokeys": "guest"},
        ]
    )
    provider.client.get_artist_info = AsyncMock(
        return_value=[
            {"artist_id": "1", "seokey": "lead", "name": "Lead"},
            {"artist_id": "2", "seokey": "guest", "name": "Guest"},
        ]
    )

    result = await provider.suggested_artists(["Malayalam"], 2)

    provider.client.get_artist_info.assert_awaited_once_with(["lead", "guest"], False)
    assert [artist["provider_id"] for artist in result] == ["1", "2"]


@pytest.mark.asyncio
async def test_suggested_artists_reports_when_nothing_is_trending():
    provider = GaanaProvider()
    provider.trending = AsyncMock(return_value=[{"artist_seokeys": ""}])

    with pytest.raises(Exception, match="No suggested artists were found"):
        await provider.suggested_artists(["Malayalam"], 5)
