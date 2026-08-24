from collections import Counter

from .scoring import candidate_artist_ids, candidate_id


def diversify(
    candidates: list[dict],
    max_per_artist: int = 3,
    max_per_language: int = 10,
) -> list[dict]:
    """Deduplicate and cap dominant artists/languages while retaining rank order."""
    output: list[dict] = []
    seen: set[str] = set()
    artist_counts: Counter[str] = Counter()
    language_counts: Counter[str] = Counter()

    for candidate in candidates:
        identity = candidate_id(candidate)
        if not identity or identity in seen:
            continue
        artists = candidate_artist_ids(candidate)
        language = str(candidate.get("language") or "unknown").casefold()
        if artists and any(artist_counts[artist] >= max_per_artist for artist in artists):
            continue
        if language_counts[language] >= max_per_language:
            continue
        seen.add(identity)
        output.append(candidate)
        language_counts[language] += 1
        for artist in artists:
            artist_counts[artist] += 1
    return output
