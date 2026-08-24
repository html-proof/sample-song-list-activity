from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


Quality = Literal["auto", "low", "medium", "high"]


class GeneralSettings(BaseModel):
    app_language: str = "en"
    theme_mode: Literal["system", "light", "dark"] = "system"
    dynamic_artwork_colors: bool = True
    animations_enabled: bool = True
    model_config = ConfigDict(extra="ignore")


class GeneralSettingsUpdate(BaseModel):
    app_language: str | None = Field(default=None, min_length=2, max_length=12)
    theme_mode: Literal["system", "light", "dark"] | None = None
    dynamic_artwork_colors: bool | None = None
    animations_enabled: bool | None = None


class PlaybackSettings(BaseModel):
    streaming_quality: Quality = "auto"
    mobile_streaming_quality: Quality = "medium"
    wifi_streaming_quality: Quality = "high"
    autoplay: bool = True
    normalize_volume: bool = True
    gapless_playback: bool = True
    crossfade_seconds: int = 0
    explicit_content: bool = True
    auto_resume: bool = True
    repeat_mode: Literal["off", "all", "one"] = "off"
    model_config = ConfigDict(extra="ignore")


class PlaybackSettingsUpdate(BaseModel):
    streaming_quality: Quality | None = None
    mobile_streaming_quality: Quality | None = None
    wifi_streaming_quality: Quality | None = None
    autoplay: bool | None = None
    normalize_volume: bool | None = None
    gapless_playback: bool | None = None
    crossfade_seconds: int | None = Field(default=None, ge=0, le=12)
    explicit_content: bool | None = None
    auto_resume: bool | None = None
    repeat_mode: Literal["off", "all", "one"] | None = None


class DownloadSettings(BaseModel):
    quality: Literal["low", "medium", "high"] = "high"
    wifi_only: bool = True
    auto_download_liked: bool = False
    auto_download_playlists: bool = False
    delete_played_after_days: int | None = None
    model_config = ConfigDict(extra="ignore")


class DownloadSettingsUpdate(BaseModel):
    quality: Literal["low", "medium", "high"] | None = None
    wifi_only: bool | None = None
    auto_download_liked: bool | None = None
    auto_download_playlists: bool | None = None
    delete_played_after_days: int | None = Field(default=None, ge=1, le=365)


class RecommendationSettings(BaseModel):
    enabled: bool = True
    use_listening_history: bool = True
    use_search_history: bool = True
    use_likes: bool = True
    cross_language_discovery: bool = True
    discover_new_artists: bool = True
    exploration_level: int = 20
    diversity_level: int = 50
    model_config = ConfigDict(extra="ignore")


class RecommendationSettingsUpdate(BaseModel):
    enabled: bool | None = None
    use_listening_history: bool | None = None
    use_search_history: bool | None = None
    use_likes: bool | None = None
    cross_language_discovery: bool | None = None
    discover_new_artists: bool | None = None
    exploration_level: int | None = Field(default=None, ge=0, le=100)
    diversity_level: int | None = Field(default=None, ge=0, le=100)


class NotificationSettings(BaseModel):
    enabled: bool = True
    artist_releases: bool = True
    new_music: bool = True
    recommendations: bool = True
    playlist_updates: bool = True
    download_complete: bool = True
    headphone_health: bool = True
    model_config = ConfigDict(extra="ignore")


class NotificationSettingsUpdate(BaseModel):
    enabled: bool | None = None
    artist_releases: bool | None = None
    new_music: bool | None = None
    recommendations: bool | None = None
    playlist_updates: bool | None = None
    download_complete: bool | None = None
    headphone_health: bool | None = None


class PrivacySettings(BaseModel):
    save_listening_history: bool = True
    save_search_history: bool = True
    personalized_recommendations: bool = True
    analytics_enabled: bool = True
    model_config = ConfigDict(extra="ignore")


class PrivacySettingsUpdate(BaseModel):
    save_listening_history: bool | None = None
    save_search_history: bool | None = None
    personalized_recommendations: bool | None = None
    analytics_enabled: bool | None = None


class AppSettings(BaseModel):
    general: GeneralSettings = Field(default_factory=GeneralSettings)
    playback: PlaybackSettings = Field(default_factory=PlaybackSettings)
    downloads: DownloadSettings = Field(default_factory=DownloadSettings)
    recommendations: RecommendationSettings = Field(default_factory=RecommendationSettings)
    notifications: NotificationSettings = Field(default_factory=NotificationSettings)
    privacy: PrivacySettings = Field(default_factory=PrivacySettings)
