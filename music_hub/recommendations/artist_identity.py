"""Identity and de-duplication for artists coming from any provider.

Providers disagree about ids for the same person, and the same catalogue can
return "Arijit Singh", "ARIJIT SINGH" and "Arijit  singh" as separate rows. The
identity used here is therefore the normalised name, narrowed by language when
both records claim one, with the provider id kept only as a tie-breaker so a
second provider can be merged in later without changing callers.
"""

from __future__ import annotations

import re
import unicodedata


_PUNCTUATION = re.compile(r"[^\w\s]", re.UNICODE)
_WHITESPACE = re.compile(r"\s+", re.UNICODE)

# Honorifics and role suffixes that providers append inconsistently.
_NOISE_TOKENS = frozenset(
    {
        "singer",
        "singers",
        "artist",
        "artists",
        "feat",
        "featuring",
        "ft",
        "and",
        "the",
    }
)


def normalize(value: object) -> str:
    """Casefold, strip accents and punctuation, and collapse whitespace."""
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = _PUNCTUATION.sub(" ", text)
    return _WHITESPACE.sub(" ", text).strip().casefold()


def name_tokens(value: object) -> tuple[str, ...]:
    """Meaningful tokens of a name, with provider noise words removed."""
    tokens = [token for token in normalize(value).split() if token not in _NOISE_TOKENS]
    return tuple(tokens)


def artist_name(artist: dict) -> str:
    for field in ("name", "artist_name", "title", "seokey"):
        value = artist.get(field)
        if value:
            return str(value)
    return ""


def artist_provider_id(artist: dict) -> str:
    for field in ("provider_id", "artist_id", "provider_artist_id", "id", "seokey"):
        value = artist.get(field)
        if value not in (None, ""):
            return str(value)
    return ""


def artist_language(artist: dict) -> str:
    return normalize(artist.get("language") or artist.get("primary_language") or "")


def artist_identity(artist: dict) -> str:
    """The key two records must share to be considered the same artist."""
    tokens = name_tokens(artist_name(artist))
    if not tokens:
        # Nothing to compare on, so fall back to the provider id and let the
        # record through rather than collapsing unrelated unnamed rows.
        return f"id:{artist_provider_id(artist)}"
    return " ".join(tokens)


def _completeness(artist: dict) -> tuple[int, int, int]:
    """Prefers the richer of two records for the same artist."""
    return (
        1 if artist.get("artwork_url") or artist.get("artist_image") or artist.get("images") else 0,
        1 if artist.get("language") else 0,
        1 if artist.get("seokey") else 0,
    )


def deduplicate_artists(artists: list[dict]) -> list[dict]:
    """Collapses duplicates, keeping the first-seen order and richest record.

    When two records share a normalised name but declare different languages
    they are kept apart: distinct artists genuinely do share a name across
    catalogues, and merging them would hide one of them entirely.
    """
    merged: dict[tuple[str, str], dict] = {}
    order: list[tuple[str, str]] = []
    for artist in artists:
        if not isinstance(artist, dict):
            continue
        identity = artist_identity(artist)
        if not identity or identity == "id:":
            continue
        key = (identity, artist_language(artist))
        existing = merged.get(key)
        if existing is None:
            # A record with no declared language merges into a language-bearing
            # sibling rather than standing alone as a near-duplicate.
            sibling_key = next(
                (
                    candidate
                    for candidate in merged
                    if candidate[0] == identity
                    and (not candidate[1] or not key[1])
                ),
                None,
            )
            if sibling_key is not None:
                existing = merged[sibling_key]
                key = sibling_key
            else:
                merged[key] = artist
                order.append(key)
                continue
        if _completeness(artist) > _completeness(existing):
            # Keep the position of the first sighting, upgrade the payload, and
            # remember every provider id that pointed at this artist.
            promoted = {**artist}
            promoted["provider_ids"] = _provider_ids(existing, artist)
            merged[key] = promoted
        else:
            existing["provider_ids"] = _provider_ids(existing, artist)
    return [merged[key] for key in order]


def _provider_ids(*artists: dict) -> list[str]:
    ids: list[str] = []
    for artist in artists:
        for value in artist.get("provider_ids", []) or []:
            if value and value not in ids:
                ids.append(str(value))
        provider_id = artist_provider_id(artist)
        if provider_id and provider_id not in ids:
            ids.append(provider_id)
    return ids
