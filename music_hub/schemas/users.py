from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class UserResponse(BaseModel):
    id: UUID
    display_name: str | None = None
    email: str | None = None
    photo_url: str | None = None
    onboarding_completed: bool = False
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class LanguagePreference(BaseModel):
    language_code: str = Field(
        min_length=2,
        max_length=50,
        pattern=r"^[A-Za-z][A-Za-z -]*$",
    )
    priority: int = Field(default=1, ge=1, le=100)


class ArtistPreference(BaseModel):
    provider: str = Field(default="gaana", min_length=1, max_length=30)
    provider_artist_id: str = Field(min_length=1, max_length=200)
    artist_name: str = Field(min_length=1, max_length=300)
    artist_image: str | None = Field(default=None, max_length=2000)
    preference_score: float = Field(default=1.0, ge=0, le=100)

    @model_validator(mode="after")
    def validate_provider_id(self) -> "ArtistPreference":
        if self.provider.casefold() == "gaana" and not self.provider_artist_id.isdigit():
            raise ValueError("Gaana artist IDs must be numeric")
        return self


class OnboardingRequest(BaseModel):
    languages: list[LanguagePreference]
    artists: list[ArtistPreference]

    @model_validator(mode="after")
    def validate_selections(self) -> "OnboardingRequest":
        if not self.languages:
            raise ValueError("Select at least one language")
        if len(self.languages) > 10:
            raise ValueError("Select at most 10 languages")
        if len(self.artists) > 50:
            raise ValueError("Select at most 50 artists")
        language_codes = [item.language_code.casefold() for item in self.languages]
        if len(language_codes) != len(set(language_codes)):
            raise ValueError("Language selections must be unique")
        artist_keys = [(item.provider, item.provider_artist_id) for item in self.artists]
        if len(artist_keys) != len(set(artist_keys)):
            raise ValueError("Artist selections must be unique")
        return self


class OnboardingResponse(BaseModel):
    onboarding_completed: bool
    languages: list[LanguagePreference]
    artists: list[ArtistPreference]


class LanguagePreferencesUpdate(BaseModel):
    languages: list[LanguagePreference]

    @model_validator(mode="after")
    def validate_languages(self) -> "LanguagePreferencesUpdate":
        if not self.languages:
            raise ValueError("Select at least one language")
        if len(self.languages) > 10:
            raise ValueError("Select at most 10 languages")
        codes = [item.language_code.casefold() for item in self.languages]
        if len(codes) != len(set(codes)):
            raise ValueError("Language selections must be unique")
        return self


class ArtistPreferencesUpdate(BaseModel):
    artists: list[ArtistPreference]

    @model_validator(mode="after")
    def validate_artists(self) -> "ArtistPreferencesUpdate":
        if len(self.artists) > 50:
            raise ValueError("Select at most 50 artists")
        keys = [(item.provider, item.provider_artist_id) for item in self.artists]
        if len(keys) != len(set(keys)):
            raise ValueError("Artist selections must be unique")
        return self


class UserPreferencesUpdate(BaseModel):
    explicit_content: bool | None = None
    autoplay: bool | None = None
    audio_quality: str | None = Field(default=None, pattern="^(low|medium|high|very_high)$")
    settings: dict = Field(default_factory=dict)
