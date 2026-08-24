import re
import unicodedata


_SPACE = re.compile(r"\s+")
_PUNCTUATION = re.compile(r"[^\w\s]", re.UNICODE)
_VERSION_TOKEN = re.compile(
    r"\b(live|remix|mix|acoustic|instrumental|karaoke|cover|sped\s*up|slowed|reprise|radio\s*edit|version)\b",
    re.IGNORECASE,
)


def normalize_text(value: str | None) -> str:
    if not value:
        return ""
    normalized = unicodedata.normalize("NFKC", value).casefold()
    normalized = _PUNCTUATION.sub(" ", normalized)
    return _SPACE.sub(" ", normalized).strip()


def version_tokens(*values: str | None) -> set[str]:
    text = " ".join(value for value in values if value)
    return {normalize_text(match.group(0)) for match in _VERSION_TOKEN.finditer(text)}
