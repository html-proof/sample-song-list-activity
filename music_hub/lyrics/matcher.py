from dataclasses import dataclass
from difflib import SequenceMatcher

from .models import ProviderLyricsCandidate, SongIdentity
from .normalizer import normalize_text, version_tokens


@dataclass(frozen=True)
class LyricsMatch:
    candidate: ProviderLyricsCandidate
    confidence: float


class LyricsMatcher:
    def __init__(self, minimum_confidence: float = 0.82) -> None:
        self.minimum_confidence = minimum_confidence

    def best(
        self,
        identity: SongIdentity,
        candidates: list[ProviderLyricsCandidate],
    ) -> LyricsMatch | None:
        matches = [LyricsMatch(candidate, self.score(identity, candidate)) for candidate in candidates]
        if not matches:
            return None
        best = max(matches, key=lambda match: match.confidence)
        return best if best.confidence >= self.minimum_confidence else None

    def score(self, identity: SongIdentity, candidate: ProviderLyricsCandidate) -> float:
        if (
            identity.provider_song_id
            and candidate.provider_song_id
            and normalize_text(identity.provider_song_id)
            == normalize_text(candidate.provider_song_id)
        ):
            return 1.0
        if identity.isrc and candidate.isrc and identity.isrc.casefold() == candidate.isrc.casefold():
            return 0.99

        expected_versions = version_tokens(identity.title, identity.album)
        candidate_versions = version_tokens(candidate.title, candidate.album)
        if expected_versions != candidate_versions:
            return 0.0

        title = _similarity(identity.title, candidate.title)
        artist = _similarity(identity.primary_artist, candidate.primary_artist)
        duration = _duration_score(identity.duration_ms, candidate.duration_ms)
        album = _similarity(identity.album, candidate.album, unknown=0.5)
        language = _language_score(identity.language, candidate.language)
        confidence = (
            title * 0.30
            + artist * 0.25
            + duration * 0.25
            + album * 0.10
            + language * 0.10
        )
        return round(confidence, 4)


def _similarity(left: str | None, right: str | None, *, unknown: float = 0.0) -> float:
    normalized_left = normalize_text(left)
    normalized_right = normalize_text(right)
    if not normalized_left or not normalized_right:
        return unknown
    return SequenceMatcher(None, normalized_left, normalized_right).ratio()


def _duration_score(left: int | None, right: int | None) -> float:
    if not left or not right:
        return 0.5
    difference = abs(left - right)
    if difference > 15_000:
        return 0.0
    return 1.0 - (difference / 15_000)


def _language_score(left: str | None, right: str | None) -> float:
    normalized_left = normalize_text(left)
    normalized_right = normalize_text(right)
    if not normalized_left or not normalized_right:
        return 0.5
    return 1.0 if normalized_left == normalized_right else 0.0
