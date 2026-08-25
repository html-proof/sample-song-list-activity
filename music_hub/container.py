from dataclasses import dataclass

from music_hub.auth import FirebaseVerifier
from music_hub.cache import RedisCache
from music_hub.config import Settings
from music_hub.database import Database
from music_hub.providers.base import MusicProvider
from music_hub.providers.lyrics.base import LyricsProvider
from music_hub.recommendations import (
    ArtistRecommendationEngine,
    RecommendationEngine,
)
from music_hub.repositories import (
    DeviceRepository,
    HistoryRepository,
    LibraryRepository,
    PlaylistRepository,
    PreferenceRepository,
    RecommendationRepository,
    SettingsRepository,
    UserRepository,
)
from music_hub.services.devices import DeviceService
from music_hub.services.history import HistoryService
from music_hub.services.home import HomeService
from music_hub.services.library import LibraryService
from music_hub.services.lyrics_service import LyricsService
from music_hub.services.music import MusicService
from music_hub.services.onboarding import OnboardingService
from music_hub.services.playlists import PlaylistService
from music_hub.services.search import SearchService
from music_hub.services.settings import SettingsService
from music_hub.services.users import UserService


@dataclass
class Container:
    settings: Settings
    database: Database
    cache: RedisCache
    firebase: FirebaseVerifier
    provider: MusicProvider
    lyrics_provider: LyricsProvider
    users_repository: UserRepository
    preferences_repository: PreferenceRepository
    history_repository: HistoryRepository
    library_repository: LibraryRepository
    playlists_repository: PlaylistRepository
    recommendations_repository: RecommendationRepository
    settings_repository: SettingsRepository
    devices_repository: DeviceRepository
    users: UserService
    onboarding: OnboardingService
    search: SearchService
    music: MusicService
    lyrics: LyricsService
    history: HistoryService
    library: LibraryService
    playlists: PlaylistService
    recommendations: RecommendationEngine
    artist_recommendations: ArtistRecommendationEngine
    settings_service: SettingsService
    devices: DeviceService
    home: HomeService
