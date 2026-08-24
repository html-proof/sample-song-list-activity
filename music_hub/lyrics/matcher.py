from collections import Counter
from dataclasses import dataclass, replace
from difflib import SequenceMatcher

from music_hub.lyrics.models import LyricsCandidate, SongIdentity
from music_hub.lyrics.normalizer import (
    artist_tokens,
    detect_script,
    normalize_text,
    primary_artist,
    strip_noise,
    version_markers,
)

# Weights from the agreed scoring model. Duration carries as much weight as the
# artist because it is the cheapest reliable signal that two recordings of the
# same song are actually the same take.
_TITLE_WEIGHT = 0.30
_ARTIST_WEIGHT = 0.25
_DURATION_WEIGHT = 0.25
_ALBUM_WEIGHT = 0.10
_LANGUAGE_WEIGHT = 0.10

# Duration tolerances scale with track length: 12s of drift is noise on a
# ten-minute qawwali and a different edit entirely on a 90-second interlude.
# Full credit up to `full`, decaying to zero at `zero`, rejected past `reject`.
_DURATION_FULL_MS = 4_000
_DURATION_FULL_RATIO = 0.025
_DURATION_ZERO_MS = 12_000
_DURATION_ZERO_RATIO = 0.06
_DURATION_REJECT_MS = 20_000
_DURATION_REJECT_RATIO = 0.10

DEFAULT_MIN_CONFIDENCE = 0.62


@dataclass(frozen=True, slots=True)
class MatchResult:
    candidate: LyricsCandidate
    confidence: float
    rejected_reason: str = ""

    @property
    def accepted(self) -> bool:
        return not self.rejected_reason


def _ratio(left: str, right: str) -> float:
    if not left or not right:
        return 0.0
    if left == right:
        return 1.0
    return SequenceMatcher(None, left, right).ratio()


def title_score(identity: SongIdentity, candidate: LyricsCandidate) -> float:
    wanted = normalize_text(strip_noise(identity.title))
    offered = normalize_text(strip_noise(candidate.title))
    if not wanted or not offered:
        return 0.0
    score = _ratio(wanted, offered)
    # A containment match ("Song" inside "Song Title") is common across
    # providers and should not be punished as heavily as raw edit distance.
    if score < 0.9 and (wanted in offered or offered in wanted):
        score = max(score, 0.88)
    return score


def artist_score(identity: SongIdentity, candidate: LyricsCandidate) -> float:
    wanted_primary = normalize_text(primary_artist(identity.artist))
    offered_primary = normalize_text(primary_artist(candidate.artist))
    direct = _ratio(wanted_primary, offered_primary)

    wanted_tokens = artist_tokens(identity.artist)
    offered_tokens = artist_tokens(candidate.artist)
    if wanted_tokens and offered_tokens:
        overlap = len(wanted_tokens & offered_tokens) / len(wanted_tokens | offered_tokens)
    else:
        overlap = 0.0

    # Either signal alone is enough: providers credit collaborators differently.
    return max(direct, overlap)


def _duration_bounds(duration_ms: int) -> tuple[float, float, float]:
    """Full-credit, zero-credit, and rejection thresholds for a track length."""
    reference = max(duration_ms, 0)
    return (
        max(_DURATION_FULL_MS, reference * _DURATION_FULL_RATIO),
        max(_DURATION_ZERO_MS, reference * _DURATION_ZERO_RATIO),
        max(_DURATION_REJECT_MS, reference * _DURATION_REJECT_RATIO),
    )


def duration_delta(identity: SongIdentity, candidate: LyricsCandidate) -> int | None:
    if identity.duration_ms is None or candidate.duration_seconds is None:
        return None
    return abs(identity.duration_ms - int(candidate.duration_seconds * 1000))


def duration_score(identity: SongIdentity, candidate: LyricsCandidate) -> float:
    delta = duration_delta(identity, candidate)
    if delta is None:
        # Unknown duration must not look like a perfect match.
        return 0.5
    full, zero, _ = _duration_bounds(identity.duration_ms or 0)
    if delta <= full:
        return 1.0
    if delta >= zero:
        return 0.0
    return 1.0 - ((delta - full) / (zero - full))


def duration_is_corroborated(
    identity: SongIdentity, candidates: list[LyricsCandidate]
) -> bool:
    """Whether any candidate's length agrees with the one the catalog reported.

    When none do, the catalog duration is far more likely to be wrong than
    every independent source to be wrong in the same direction. Ranking on it
    then actively picks the worst candidate -- the one whose length happens to
    sit nearest a bad number -- so it stops being used as a discriminator.
    """
    if identity.duration_ms is None:
        return False
    full, _, _ = _duration_bounds(identity.duration_ms)
    for candidate in candidates:
        delta = duration_delta(identity, candidate)
        if delta is not None and delta <= full:
            return True
    return False


def album_score(identity: SongIdentity, candidate: LyricsCandidate) -> float:
    wanted = normalize_text(strip_noise(identity.album))
    offered = normalize_text(strip_noise(candidate.album))
    if not wanted or not offered:
        return 0.5
    return _ratio(wanted, offered)


def language_score(identity: SongIdentity, candidate: LyricsCandidate) -> float:
    wanted = (identity.language or "").casefold()[:2]
    offered = (candidate.language or "").casefold()[:2]
    if not offered:
        text = candidate.synced_text or candidate.plain_text
        offered = detect_script(text[:400]) if text else ""
    if not wanted or not offered:
        return 0.5
    return 1.0 if wanted == offered else 0.0


def version_conflict(identity: SongIdentity, candidate: LyricsCandidate) -> str:
    """Reject a live/remix/acoustic mismatch outright.

    A high title+artist score is exactly what a wrong-version match looks like,
    so this check runs independently of the confidence total.
    """
    wanted = version_markers(identity.title)
    offered = version_markers(candidate.title)
    if wanted == offered:
        return ""
    missing = wanted ^ offered
    # "instrumental" is handled as its own status, not a version mismatch.
    meaningful = {marker for marker in missing if marker != "instrumental"}
    if not meaningful:
        return ""
    return f"version mismatch: {', '.join(sorted(meaningful))}"


def score_candidate(
    identity: SongIdentity,
    candidate: LyricsCandidate,
    *,
    trust_duration: bool = True,
) -> MatchResult:
    conflict = version_conflict(identity, candidate)

    title = title_score(identity, candidate)
    artist = artist_score(identity, candidate)
    album = album_score(identity, candidate)
    # A duration nothing corroborates is treated as missing rather than as
    # evidence, which is exactly how an absent duration already behaves.
    duration = duration_score(identity, candidate) if trust_duration else 0.5

    confidence = (
        title * _TITLE_WEIGHT
        + artist * _ARTIST_WEIGHT
        + duration * _DURATION_WEIGHT
        + album * _ALBUM_WEIGHT
        + language_score(identity, candidate) * _LANGUAGE_WEIGHT
    )

    if conflict:
        return MatchResult(candidate=candidate, confidence=confidence, rejected_reason=conflict)

    delta = duration_delta(identity, candidate)
    if delta is not None:
        _, _, reject = _duration_bounds(identity.duration_ms or 0)
        if delta >= reject:
            # Far enough apart to be a snippet, an extended cut, or a different
            # song altogether. No amount of metadata agreement rescues this.
            return MatchResult(
                candidate=candidate,
                confidence=confidence,
                rejected_reason="duration outside tolerance",
            )
        # Between `zero` and `reject` the duration already scores 0. Rejecting
        # outright as well would make a slightly-wrong duration worse than no
        # duration at all, which is why a well-identified track is kept here
        # and left to the confidence threshold to judge.

    return MatchResult(candidate=candidate, confidence=confidence)


def consensus_duration_ms(candidates: list[LyricsCandidate]) -> int | None:
    """The length independent sources agree on, if they agree at all.

    Several uploads reporting the same runtime is stronger evidence of the real
    recording than one catalog field, so it can stand in for a duration the
    catalog got wrong. A lone candidate agrees with nothing and is ignored.
    """
    counts: Counter[int] = Counter()
    for candidate in candidates:
        if candidate.duration_seconds is None:
            continue
        counts[round(candidate.duration_seconds)] += 1
    if not counts:
        return None
    seconds, agreeing = counts.most_common(1)[0]
    return seconds * 1000 if agreeing >= 2 else None


def best_match(
    identity: SongIdentity,
    candidates: list[LyricsCandidate],
    minimum_confidence: float = DEFAULT_MIN_CONFIDENCE,
) -> MatchResult | None:
    """Highest-confidence accepted candidate, or None when nothing is safe.

    Showing nothing is strictly better than showing the wrong lyrics, so a
    below-threshold winner is discarded rather than downgraded.
    """
    trust_duration = duration_is_corroborated(identity, candidates)
    if not trust_duration:
        # Fall back to the length the sources agree on. Judging against that is
        # better than judging against a number nothing supports, and better
        # than ignoring duration entirely and letting near-identical uploads
        # separate on incidental metadata.
        consensus = consensus_duration_ms(candidates)
        if consensus is not None:
            identity = replace(identity, duration_ms=consensus)
            trust_duration = True
    scored = [
        score_candidate(identity, candidate, trust_duration=trust_duration)
        for candidate in candidates
    ]
    accepted = [result for result in scored if result.accepted]
    if not accepted:
        return None
    # Prefer synced lyrics when confidence is effectively tied, so a slightly
    # weaker synced match beats a marginally better plain-only one.
    accepted.sort(
        key=lambda result: (
            round(result.confidence, 2),
            bool(result.candidate.synced_text),
        ),
        reverse=True,
    )
    winner = accepted[0]
    return winner if winner.confidence >= minimum_confidence else None
