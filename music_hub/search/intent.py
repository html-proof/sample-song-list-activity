"""Query-intent detection.

A query such as ``malayalam`` is a request for a language, not for songs whose
title contains the word "malayalam". Detecting that up front lets the ranker
filter on the language metadata field instead of on text similarity.
"""

from dataclasses import dataclass
from enum import Enum

from music_hub.search.normalize import normalize, tokenize


class QueryIntent(str, Enum):
    SONG = "song"
    ARTIST = "artist"
    ALBUM = "album"
    LANGUAGE = "language"


# Languages carried in Gaana's ``language`` metadata field.
LANGUAGES = frozenset(
    {
        "assamese",
        "bengali",
        "bhojpuri",
        "english",
        "gujarati",
        "haryanvi",
        "hindi",
        "kannada",
        "kashmiri",
        "konkani",
        "malayalam",
        "manipuri",
        "marathi",
        "nepali",
        "odia",
        "oriya",
        "punjabi",
        "rajasthani",
        "sanskrit",
        "sindhi",
        "tamil",
        "telugu",
        "tulu",
        "urdu",
    }
)

# Words that describe the *kind* of result wanted rather than its name.
_FILLER = frozenset({"songs", "song", "music", "tracks", "track", "hits", "top", "best", "new"})
_ARTIST_HINTS = frozenset({"artist", "singer", "composer", "musician", "band"})
_ALBUM_HINTS = frozenset({"album", "film", "movie", "ost", "soundtrack"})

# Alternate spellings that map onto a canonical language name.
_LANGUAGE_ALIASES = {"oriya": "odia"}


@dataclass(frozen=True)
class DetectedIntent:
    intent: QueryIntent
    #: The query with descriptive filler removed, used for matching.
    subject: str
    #: Set only for :attr:`QueryIntent.LANGUAGE`.
    language: str | None = None

    @property
    def is_language(self) -> bool:
        return self.intent is QueryIntent.LANGUAGE


def detect_intent(query: str) -> DetectedIntent:
    words = tokenize(query)
    if not words:
        return DetectedIntent(QueryIntent.SONG, "")

    meaningful = [word for word in words if word not in _FILLER]
    if not meaningful:
        meaningful = words

    languages = [word for word in meaningful if word in LANGUAGES]
    remainder = [word for word in meaningful if word not in LANGUAGES]

    # "malayalam", "malayalam songs", "top hindi hits" -- nothing but a language.
    if languages and not remainder:
        canonical = _LANGUAGE_ALIASES.get(languages[0], languages[0])
        return DetectedIntent(QueryIntent.LANGUAGE, canonical, canonical)

    hint_words = set(meaningful)
    subject_words = [word for word in remainder if word not in _ARTIST_HINTS | _ALBUM_HINTS]
    subject = " ".join(subject_words) or normalize(query)

    if hint_words & _ARTIST_HINTS:
        return DetectedIntent(QueryIntent.ARTIST, subject)
    if hint_words & _ALBUM_HINTS:
        return DetectedIntent(QueryIntent.ALBUM, subject)
    return DetectedIntent(QueryIntent.SONG, normalize(query))
