"""Ranking for artist recommendations and for artist search.

These are deliberately separate functions. Search has to return the artist the
user typed, so it ranks on name match alone. Recommendation has to return
artists the user is likely to enjoy, so it ranks on affinity. Mixing the two is
what makes a search for "arijit" return a playlist.
"""

from __future__ import annotations

from difflib import SequenceMatcher

from .artist_identity import (
    artist_language,
    artist_name,
    artist_provider_id,
    name_tokens,
    normalize,
)


# Where a recommended artist came from, and how much of the list each source is
# allowed to fill. Quotas keep the page from becoming a list of artists the user
# already follows.
SOURCE_QUOTAS: dict[str, float] = {
    "selected_artist": 0.40,
    "recent_artist": 0.25,
    "liked_artist": 0.15,
    "search_artist": 0.10,
    "discovery": 0.10,
}


def artist_ids(artist: dict) -> set[str]:
    ids = {str(value) for value in artist.get("provider_ids", []) or [] if value}
    provider_id = artist_provider_id(artist)
    if provider_id:
        ids.add(provider_id)
    return ids


def artist_score(
    artist: dict,
    selected_artists: set[str],
    recent_artists: set[str],
    liked_artists: set[str],
    languages: dict[str, int] | set[str],
    popularity_cap: float = 30.0,
) -> float:
    """Affinity score for a candidate artist.

    Higher is better. The bonuses are ordered so an explicitly chosen artist
    always outranks one merely inferred from listening.
    """
    score = 0.0
    ids = artist_ids(artist)

    if ids & selected_artists:
        score += 100
    if ids & liked_artists:
        score += 80
    if ids & recent_artists:
        score += 60

    language = artist_language(artist)
    if language and language in {normalize(item) for item in languages}:
        score += 50
        if isinstance(languages, dict):
            # A higher onboarding priority nudges the preferred language up
            # without letting it overtake an explicit artist choice.
            priority = languages.get(language) or languages.get(language.title(), 0)
            score += min(float(priority), 10.0)

    score += min(_popularity(artist), popularity_cap)
    return score


def _popularity(artist: dict) -> float:
    for field in ("popularity", "favorite_count", "follower_count", "play_count"):
        value = artist.get(field)
        if value in (None, ""):
            continue
        try:
            number = float(value)
        except (TypeError, ValueError):
            continue
        if number <= 0:
            continue
        # Raw counts span several orders of magnitude, so compress them into a
        # comparable range instead of letting one artist dominate the cap.
        if number > 100:
            import math

            return min(math.log10(number) * 8.0, 40.0)
        return number
    return 0.0


def fuzzy_artist_score(name: str, query: str) -> float:
    """0-500 similarity fallback, below every exact-match tier."""
    if not name or not query:
        return 0.0
    ratio = SequenceMatcher(None, name, query).ratio()
    return ratio * 500


def artist_search_score(artist: dict, query: str) -> float:
    """Rank purely on how well the name answers what was typed."""
    q = normalize(query)
    name = normalize(artist_name(artist))
    if not q or not name:
        return 0.0

    if name == q:
        return 1000
    if name.startswith(q):
        return 850

    tokens = name.split()
    query_tokens = q.split()
    if q in tokens:
        return 700
    # "arijit singh" typed in full should beat a partial substring hit.
    if query_tokens and all(token in tokens for token in query_tokens):
        return 680
    if q in name:
        return 600
    if any(token.startswith(q) for token in tokens):
        return 560

    return fuzzy_artist_score(name, q)


def rank_search_results(artists: list[dict], query: str) -> list[dict]:
    """Sorts by match quality, then popularity, then name for a stable order."""
    return sorted(
        artists,
        key=lambda artist: (
            -artist_search_score(artist, query),
            -_popularity(artist),
            normalize(artist_name(artist)),
        ),
    )


def rank_artists(
    candidates: list[dict],
    languages: dict[str, int] | set[str],
    selected_artists: set[str],
    recent_artists: set[str],
    liked_artists: set[str],
) -> list[dict]:
    """Scores every candidate and returns them best-first."""
    scored = [
        (
            artist_score(
                artist,
                selected_artists,
                recent_artists,
                liked_artists,
                languages,
            ),
            index,
            artist,
        )
        for index, artist in enumerate(candidates)
    ]
    scored.sort(key=lambda row: (-row[0], row[1]))
    return [
        {**artist, "recommendation_score": round(score, 3)}
        for score, _index, artist in scored
    ]


def apply_source_quotas(ranked: list[dict], limit: int) -> list[dict]:
    """Interleaves the ranked list so no single source fills the page.

    Two phases. Each source first takes its quota share in rank order, then any
    shortfall is topped up round-robin across the sources rather than from the
    head of the global ranking. Topping up in rank order was enough on its own
    to hand the page back to the artists the user already follows, since those
    score highest and sit at the front.
    """
    if limit <= 0:
        return []

    buckets: dict[str, list[dict]] = {source: [] for source in SOURCE_QUOTAS}
    for artist in ranked:
        source = str(artist.get("recommendation_source", "discovery"))
        buckets.setdefault(source, []).append(artist)

    cursors = {source: 0 for source in buckets}
    selected: list[dict] = []

    def take(source: str) -> bool:
        items = buckets[source]
        index = cursors[source]
        if index >= len(items):
            return False
        cursors[source] = index + 1
        selected.append(items[index])
        return True

    for source, share in SOURCE_QUOTAS.items():
        if source not in buckets:
            continue
        allowance = max(1, round(share * limit))
        for _ in range(allowance):
            if len(selected) >= limit or not take(source):
                break

    # Round-robin top-up, so a shortfall in one source is spread across the
    # others instead of being handed to whichever scores highest.
    order = [source for source in SOURCE_QUOTAS if source in buckets]
    order += [source for source in buckets if source not in SOURCE_QUOTAS]
    while len(selected) < limit:
        progressed = False
        for source in order:
            if len(selected) >= limit:
                break
            if take(source):
                progressed = True
        if not progressed:
            break

    # Restore global rank order across the picks so the strongest still leads.
    position = {id(artist): index for index, artist in enumerate(ranked)}
    selected.sort(key=lambda artist: position.get(id(artist), len(ranked)))
    return selected
