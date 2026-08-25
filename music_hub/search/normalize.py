"""Text normalization shared by every stage of the search pipeline.

Both the query and every searchable field go through :func:`normalize` so that
comparisons are made on identical footing regardless of which provider supplied
the metadata.
"""

import html
import re
import unicodedata
from difflib import SequenceMatcher

_WHITESPACE = re.compile(r"\s+")


def _strip_punctuation(text: str) -> str:
    """Replace punctuation with spaces while preserving every script.

    A ``[^\\w\\s]`` character class cannot be used here: Python's ``\\w`` excludes
    Unicode combining marks, so it shreds Malayalam, Tamil, Hindi and every
    other Indic title into disconnected consonants. Vowel signs and viramas
    (categories Mn/Mc) are part of the word and are kept.
    """
    return "".join(
        character
        if character.isalnum()
        or character.isspace()
        or unicodedata.category(character).startswith("M")
        else " "
        for character in text
    )


def normalize(value: object) -> str:
    """Fold a query or metadata field into a comparable form.

    Decodes HTML entities, applies Unicode NFKC, case-folds, replaces
    punctuation with spaces, and collapses runs of whitespace.
    """
    if value is None:
        return ""
    text = str(value)
    if not text:
        return ""
    text = html.unescape(text)
    text = unicodedata.normalize("NFKC", text)
    text = text.casefold()
    text = _strip_punctuation(text)
    text = _WHITESPACE.sub(" ", text)
    return text.strip()


def tokenize(value: object) -> list[str]:
    normalized = normalize(value)
    return normalized.split() if normalized else []


def similarity(left: str, right: str) -> float:
    """Ratio in [0, 1]; both inputs are expected to be normalized already."""
    if not left or not right:
        return 0.0
    return SequenceMatcher(None, left, right).ratio()


def best_similarity(query: str, text: str) -> float:
    """Similarity against the whole field and against its individual words.

    A typo in a one-word query should still match a long title that contains
    the intended word, which a whole-string ratio alone would miss.
    """
    if not query or not text:
        return 0.0
    best = similarity(query, text)
    for word in text.split():
        if abs(len(word) - len(query)) > 3:
            continue
        best = max(best, similarity(query, word))
    return best
