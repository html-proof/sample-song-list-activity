from dataclasses import dataclass, field
import hashlib


def _tokens(value: object) -> set[str]:
    if value is None:
        return set()
    return {part.strip().casefold() for part in str(value).split(",") if part.strip()}


def candidate_id(candidate: dict) -> str:
    return str(
        candidate.get("provider_id")
        or candidate.get("track_id")
        or candidate.get("seokey")
        or ""
    )


def candidate_artist_ids(candidate: dict) -> set[str]:
    return _tokens(candidate.get("artist_ids") or candidate.get("artist_id"))


@dataclass
class RecommendationSignals:
    languages: dict[str, int] = field(default_factory=dict)
    selected_artists: dict[str, float] = field(default_factory=dict)
    followed_artists: set[str] = field(default_factory=set)
    liked_songs: set[str] = field(default_factory=set)
    completed_songs: set[str] = field(default_factory=set)
    playlist_songs: set[str] = field(default_factory=set)
    play_counts: dict[str, int] = field(default_factory=dict)
    skipped_songs: dict[str, int] = field(default_factory=dict)
    skipped_artists: dict[str, int] = field(default_factory=dict)
    skipped_languages: dict[str, int] = field(default_factory=dict)
    search_terms: list[str] = field(default_factory=list)
    exploration_level: int = 20

    @classmethod
    def from_mapping(cls, data: dict) -> "RecommendationSignals":
        allowed = cls.__dataclass_fields__.keys()
        return cls(**{key: data[key] for key in allowed if key in data})


class WeightedScorer:
    def score(self, candidate: dict, signals: RecommendationSignals, seed: str) -> tuple[float, list[str]]:
        score = 10.0
        reasons: list[str] = []
        song_id = candidate_id(candidate)
        artist_ids = candidate_artist_ids(candidate)
        language = str(candidate.get("language") or "").casefold()

        if language and language in signals.languages:
            score += 30 + min(signals.languages[language], 10)
            reasons.append("preferred_language")

        if artist_ids & set(signals.selected_artists):
            score += 40
            reasons.append("selected_artist")

        if artist_ids & signals.followed_artists:
            score += 45
            reasons.append("followed_artist")

        if song_id in signals.liked_songs:
            score += 35
            reasons.append("liked_song")

        if song_id in signals.completed_songs:
            score += 20
            reasons.append("previously_completed")

        if song_id in signals.playlist_songs:
            score += 25
            reasons.append("in_playlist")

        if signals.play_counts.get(song_id, 0) >= 2:
            score += 30
            reasons.append("repeated_play")

        searchable = " ".join(
            str(candidate.get(key) or "")
            for key in ("title", "artists", "album", "language")
        ).casefold()
        if any(term and term in searchable for term in signals.search_terms[:25]):
            score += 15
            reasons.append("recent_search")

        skip_count = signals.skipped_songs.get(song_id, 0)
        if skip_count:
            score -= min(skip_count * 30, 90)
            reasons.append("skipped_song")

        if any(signals.skipped_artists.get(artist_id, 0) >= 2 for artist_id in artist_ids):
            score -= 40
            reasons.append("frequently_skipped_artist")

        if language and signals.skipped_languages.get(language, 0) >= 3:
            score -= 20
            reasons.append("frequently_skipped_language")

        source = candidate.get("recommendation_source")
        if source == "selected_artist":
            score += 10 + (100 - signals.exploration_level) * 0.1
            reasons.append("from_selected_artist")
        elif source == "new_release":
            score += 5 + signals.exploration_level * 0.2
            reasons.append("new_release")

        jitter_input = f"{seed}:{song_id}".encode("utf-8")
        jitter = int(hashlib.sha256(jitter_input).hexdigest()[:8], 16) / 0xFFFFFFFF * 5
        return round(score + jitter, 4), reasons

    def rank(self, candidates: list[dict], signals: RecommendationSignals, seed: str) -> list[dict]:
        ranked: list[dict] = []
        for candidate in candidates:
            if not candidate_id(candidate):
                continue
            score, reasons = self.score(candidate, signals, seed)
            ranked.append({**candidate, "recommendation_score": score, "recommendation_reasons": reasons})
        return sorted(ranked, key=lambda item: item["recommendation_score"], reverse=True)
