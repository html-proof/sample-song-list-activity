"""Deterministic relevance ranking for merged provider search results.

The ordering is *lexicographic by match tier*, not a flat sum of bonuses. That
distinction matters: with a plain sum, a title that merely starts with the query
can collect prefix + word + contains bonuses and overtake a title that matches
the query exactly, which is the opposite of what a search for "pattalam" should
do. The tier decides the position; the aggregate score only breaks ties inside a
tier, so an exact title can never be displaced by weaker evidence.
"""

from dataclasses import dataclass
from enum import IntEnum

from music_hub.search.intent import DetectedIntent, QueryIntent
from music_hub.search.normalize import best_similarity, normalize, tokenize


class MatchTier(IntEnum):
    """Match strength. Values double as the score contributed by that match."""

    NONE = 0
    FUZZY_WEAK = 120
    FUZZY = 250
    FUZZY_STRONG = 350
    #: Every query word is present across the record's fields.
    TOKEN_COVERAGE = 380
    ALBUM_CONTAINS = 400
    ARTIST_CONTAINS = 450
    TITLE_CONTAINS = 600
    TITLE_WORD = 700
    EXACT_ALBUM = 750
    EXACT_ARTIST = 800
    TITLE_PREFIX = 850
    #: A track pulled from the soundtrack album the query explicitly named.
    REQUESTED_ALBUM_TRACK = 900
    EXACT_TITLE = 1000


#: Tiers at or above this count as "strong"; fuzzy matches are suppressed while
#: enough strong results exist (rule: typo correction is a fallback only).
STRONG_TIER = MatchTier.TITLE_CONTAINS
#: Number of strong results above which fuzzy-only matches are dropped entirely.
FUZZY_SUPPRESSION_THRESHOLD = 5
#: Never return fewer than this many items while the providers returned some;
#: unmatched filler is appended below every scored result, never mixed in.
MINIMUM_RESULTS = 3

_MAX_POPULARITY_BOOST = 20.0
_PROMOTED_FLAG = "_from_requested_album"


@dataclass(frozen=True)
class Scored:
    item: dict
    tier: MatchTier
    score: float
    popularity: float
    identity: str

    @property
    def sort_key(self) -> tuple:
        # Negated numerics give descending order while the identity keeps ties
        # deterministic across runs and across provider response ordering.
        return (-int(self.tier), -self.score, -self.popularity, self.identity)


# -- canonical field access --------------------------------------------------


def song_title(song: dict) -> str:
    return normalize(song.get("title") or song.get("track_title") or song.get("name"))


def song_artist(song: dict) -> str:
    return normalize(song.get("artists") or song.get("artist") or song.get("singers"))


def song_album(song: dict) -> str:
    return normalize(song.get("album") or song.get("album_title"))


def song_language(song: dict) -> str:
    return normalize(song.get("language"))


def artist_name(artist: dict) -> str:
    return normalize(artist.get("name") or artist.get("title") or artist.get("artists"))


def album_title(album: dict) -> str:
    return normalize(album.get("title") or album.get("album") or album.get("name"))


def popularity_of(item: dict) -> float:
    for field in ("popularity", "play_count", "favorite_count"):
        raw = item.get(field)
        if raw in (None, ""):
            continue
        try:
            return float(raw)
        except (TypeError, ValueError):
            continue
    return 0.0


def identity_of(item: dict) -> str:
    """A globally unique id for one record.

    Namespaced by provider: Gaana track 123 and JioSaavn track 123 are
    different songs, and collapsing them would silently drop a result.
    """
    provider = str(item.get("provider") or "")
    for field in ("provider_id", "track_id", "album_id", "artist_id", "seokey", "id"):
        value = item.get(field)
        if value not in (None, ""):
            return f"{provider}:{value}" if provider else str(value)
    return normalize(item.get("title") or item.get("name"))


# -- scoring -----------------------------------------------------------------


def _text_tier(query: str, text: str, *, exact: MatchTier, prefix: MatchTier,
               word: MatchTier, contains: MatchTier) -> MatchTier:
    """Best single tier for one field. Tiers are exclusive, never additive."""
    if not query or not text:
        return MatchTier.NONE
    if text == query:
        return exact
    if text.startswith(query):
        return prefix
    if query in text.split():
        return word
    if query in text:
        return contains
    return MatchTier.NONE


def _fuzzy_tier(query: str, text: str) -> MatchTier:
    ratio = best_similarity(query, text)
    if ratio >= 0.90:
        return MatchTier.FUZZY_STRONG
    if ratio >= 0.80:
        return MatchTier.FUZZY
    if ratio >= 0.70:
        return MatchTier.FUZZY_WEAK
    return MatchTier.NONE


def _token_coverage(query_tokens: set[str], *fields: str) -> bool:
    """True when every query word appears somewhere in the record."""
    if not query_tokens:
        return False
    available: set[str] = set()
    for field in fields:
        available.update(field.split())
    return query_tokens <= available


def score_song(song: dict, query: str, query_tokens: set[str] | None = None) -> tuple[MatchTier, float]:
    """Return the deciding tier and the aggregate tie-break score for a song."""
    if not query:
        return MatchTier.NONE, 0.0
    if song.get(_PROMOTED_FLAG):
        return MatchTier.REQUESTED_ALBUM_TRACK, float(MatchTier.REQUESTED_ALBUM_TRACK)

    tokens = query_tokens if query_tokens is not None else set(query.split())
    title = song_title(song)
    artist = song_artist(song)
    album = song_album(song)

    title_tier = _text_tier(
        query,
        title,
        exact=MatchTier.EXACT_TITLE,
        prefix=MatchTier.TITLE_PREFIX,
        word=MatchTier.TITLE_WORD,
        contains=MatchTier.TITLE_CONTAINS,
    )
    artist_tier = _text_tier(
        query,
        artist,
        exact=MatchTier.EXACT_ARTIST,
        prefix=MatchTier.ARTIST_CONTAINS,
        word=MatchTier.ARTIST_CONTAINS,
        contains=MatchTier.ARTIST_CONTAINS,
    )
    album_tier = _text_tier(
        query,
        album,
        exact=MatchTier.EXACT_ALBUM,
        prefix=MatchTier.ALBUM_CONTAINS,
        word=MatchTier.ALBUM_CONTAINS,
        contains=MatchTier.ALBUM_CONTAINS,
    )

    tiers = [title_tier, artist_tier, album_tier]
    if max(tiers) is MatchTier.NONE and _token_coverage(tokens, title, artist, album,
                                                        song_language(song)):
        tiers.append(MatchTier.TOKEN_COVERAGE)

    best = max(tiers)
    if best is MatchTier.NONE:
        # Typo tolerance is the last resort, never a competitor to real matches.
        best = _fuzzy_tier(query, title)
        if best is MatchTier.NONE:
            return MatchTier.NONE, 0.0
        tiers = [best]

    score = float(sum(int(tier) for tier in tiers))
    score += min(popularity_of(song) / 100.0, _MAX_POPULARITY_BOOST)
    return best, score


def score_named(item: dict, query: str, name: str) -> tuple[MatchTier, float]:
    """Score an artist or album by its own name."""
    if not query or not name:
        return MatchTier.NONE, 0.0
    tier = _text_tier(
        query,
        name,
        exact=MatchTier.EXACT_TITLE,
        prefix=MatchTier.TITLE_PREFIX,
        word=MatchTier.TITLE_WORD,
        contains=MatchTier.TITLE_CONTAINS,
    )
    if tier is MatchTier.NONE:
        tier = _fuzzy_tier(query, name)
        if tier is MatchTier.NONE:
            return MatchTier.NONE, 0.0
    score = float(int(tier)) + min(popularity_of(item) / 100.0, _MAX_POPULARITY_BOOST)
    return tier, score


def score_song_for_language(song: dict, language: str) -> tuple[MatchTier, float]:
    """Language queries are answered from metadata, not from title text."""
    if not language:
        return MatchTier.NONE, 0.0
    if song_language(song) != language:
        return MatchTier.NONE, 0.0
    score = float(MatchTier.EXACT_TITLE)
    score += min(popularity_of(song) / 100.0, _MAX_POPULARITY_BOOST)
    return MatchTier.EXACT_TITLE, score


# -- deduplication -----------------------------------------------------------


def song_identity(song: dict) -> tuple[str, str, str]:
    return (song_title(song), song_artist(song), song_album(song))


def _completeness(song: dict) -> int:
    """How usable a record is, used to pick a winner among duplicates."""
    fields = ("stream_urls", "images", "duration", "album", "artists", "language")
    return sum(1 for field in fields if song.get(field))


def deduplicate(items: list[dict], key=song_identity) -> list[dict]:
    """Collapse the same record arriving from more than one provider.

    Provider ids are checked first; records that share a title/artist/album
    identity collapse onto whichever copy carries the most usable metadata, so
    merging a second provider never degrades a playable result.
    """
    unique: dict[tuple, dict] = {}
    seen_ids: set[str] = set()
    order: list[tuple] = []

    for item in items:
        if not isinstance(item, dict):
            continue
        provider_id = identity_of(item)
        if provider_id and provider_id in seen_ids:
            continue
        signature = key(item)
        if not any(signature):
            signature = (provider_id, "", "")
        if signature in unique:
            if _completeness(item) > _completeness(unique[signature]):
                unique[signature] = item
            continue
        if provider_id:
            seen_ids.add(provider_id)
        unique[signature] = item
        order.append(signature)

    return [unique[signature] for signature in order]


# -- ranking -----------------------------------------------------------------


def _present(item: dict, score: float) -> dict:
    return strip_internal_flags(dict(item, search_score=round(score, 2)))


def _assemble(
    scored: list[Scored],
    unmatched: list[Scored],
    limit: int,
    pad: bool = True,
) -> list[dict]:
    scored.sort(key=lambda entry: entry.sort_key)

    # Typo correction is a fallback: once enough genuine matches exist, drop it.
    strong = sum(1 for entry in scored if entry.tier >= STRONG_TIER)
    if strong >= FUZZY_SUPPRESSION_THRESHOLD:
        scored = [entry for entry in scored if entry.tier > MatchTier.FUZZY_STRONG]

    results = [_present(entry.item, entry.score) for entry in scored]

    # Only pad with unmatched records when there is almost nothing to show, and
    # always strictly below everything that did match.
    if pad and len(results) < MINIMUM_RESULTS:
        unmatched.sort(key=lambda entry: (-entry.popularity, entry.identity))
        for entry in unmatched:
            if len(results) >= MINIMUM_RESULTS:
                break
            results.append(_present(entry.item, 0.0))

    return results[:limit]


def rank_songs(songs: list[dict], query: str, detected: DetectedIntent, limit: int) -> list[dict]:
    normalized_query = detected.subject if detected.is_language else normalize(query)
    query_tokens = set(tokenize(query))

    scored: list[Scored] = []
    unmatched: list[Scored] = []
    for song in songs:
        if not isinstance(song, dict):
            continue
        if detected.is_language:
            tier, score = score_song_for_language(song, detected.language or "")
        else:
            tier, score = score_song(song, normalized_query, query_tokens)
        entry = Scored(song, tier, score, popularity_of(song), identity_of(song))
        (scored if tier > MatchTier.NONE else unmatched).append(entry)

    # A language query is a filter, not a similarity search: padding it with
    # songs in other languages would answer a different question.
    return _assemble(scored, unmatched, limit, pad=not detected.is_language)


def rank_named(items: list[dict], query: str, name_of, limit: int) -> list[dict]:
    normalized_query = normalize(query)
    scored: list[Scored] = []
    unmatched: list[Scored] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        name = name_of(item)
        tier, score = score_named(item, normalized_query, name)
        entry = Scored(item, tier, score, popularity_of(item), identity_of(item))
        (scored if tier > MatchTier.NONE else unmatched).append(entry)
    return _assemble(scored, unmatched, limit)


def rank_artists(artists: list[dict], query: str, limit: int) -> list[dict]:
    return rank_named(artists, query, artist_name, limit)


def rank_albums(albums: list[dict], query: str, limit: int) -> list[dict]:
    return rank_named(albums, query, album_title, limit)


def mark_requested_album_track(song: dict) -> dict:
    return dict(song, **{_PROMOTED_FLAG: True})


def strip_internal_flags(song: dict) -> dict:
    return {key: value for key, value in song.items() if key != _PROMOTED_FLAG}
