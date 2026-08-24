import re
import unicodedata

from music_hub.lyrics.models import LyricLine, LyricWord

# Trailing "version" markers that describe the *recording*, not the song. They are
# stripped before comparing titles but recorded separately so a live take never
# silently matches the studio original.
_VERSION_MARKERS: tuple[str, ...] = (
    "live",
    "remix",
    "acoustic",
    "unplugged",
    "cover",
    "reprise",
    "instrumental",
    "karaoke",
    "sped up",
    "spedup",
    "slowed",
    "reverb",
    "remastered",
    "remaster",
    "radio edit",
    "extended",
    "demo",
    "mtv",
    "lofi",
    "lo fi",
)

_BRACKETS = re.compile(r"[\(\[\{]([^)\]\}]*)[\)\]\}]")
_FEATURING = re.compile(
    r"\s*[-–—]?\s*\b(?:feat|ft|featuring|with)\b\.?\s+.*$",
    re.IGNORECASE,
)
_DASH_SUFFIX = re.compile(r"\s+[-–—]\s+(.*)$")
_WHITESPACE = re.compile(r"\s+")

_LRC_LINE = re.compile(r"^((?:\[\d+:\d+(?:[.:]\d+)?\])+)(.*)$")
_LRC_STAMP = re.compile(r"\[(\d+):(\d+)(?:[.:](\d+))?\]")
_LRC_METADATA = re.compile(r"^\[(ar|ti|al|au|by|re|ve|length|offset|lang):(.*)\]$", re.IGNORECASE)
_WORD_STAMP = re.compile(r"<(\d+):(\d+)(?:[.:](\d+))?>")

_DEFAULT_TAIL_MS = 3000
_MAX_TAIL_MS = 8000


def fold(value: str) -> str:
    """Unicode-safe casefold + accent strip used for all fuzzy comparisons.

    NFKC first so composed and decomposed Indic sequences compare equal; the
    combining-mark filter only removes marks from scripts where they are purely
    diacritical, which leaves Indic vowel signs (category Mc/Mn on base
    consonants) meaningful by keeping NFC recomposition afterwards.
    """
    if not value:
        return ""
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return _WHITESPACE.sub(" ", normalized).strip()


def _is_meaningful(char: str) -> bool:
    """Whether a character carries meaning for comparison.

    Categories starting with M are combining marks — Malayalam vowel signs,
    the virama, Devanagari matras. A regex `\\w` class does NOT match them, so
    using one here silently mangles every Indic script into bare consonants
    ("പാട്ട്" -> "പ ട ട"). Keep letters, numbers, and marks; drop the rest.
    """
    if char.isspace():
        return True
    return unicodedata.category(char)[0] in ("L", "N", "M")


def normalize_text(value: str) -> str:
    """Comparison key: punctuation removed, whitespace collapsed, script kept."""
    folded = fold(value)
    if not folded:
        return ""
    kept: list[str] = []
    for char in folded:
        if _is_meaningful(char):
            kept.append(char)
        elif unicodedata.category(char) == "Cf":
            # ZWJ/ZWNJ join conjuncts; removing them outright keeps words whole
            # instead of splitting them on an invisible character.
            continue
        else:
            kept.append(" ")
    return _WHITESPACE.sub(" ", "".join(kept)).strip()


def strip_noise(title: str) -> str:
    """Remove featuring credits and bracketed qualifiers from a title."""
    if not title:
        return ""
    without_brackets = _BRACKETS.sub(" ", title)
    without_features = _FEATURING.sub("", without_brackets)
    return _WHITESPACE.sub(" ", without_features).strip()


def version_markers(title: str) -> frozenset[str]:
    """Version keywords found in brackets or after a trailing dash."""
    if not title:
        return frozenset()
    segments = [match.group(1) for match in _BRACKETS.finditer(title)]
    dash = _DASH_SUFFIX.search(_BRACKETS.sub(" ", title))
    if dash:
        segments.append(dash.group(1))
    found: set[str] = set()
    for segment in segments:
        folded = fold(segment)
        for marker in _VERSION_MARKERS:
            if re.search(rf"\b{re.escape(marker)}\b", folded):
                found.add(marker)
    return frozenset(found)


def primary_artist(artist: str) -> str:
    """First credited artist. Providers disagree on how they join collaborators."""
    if not artist:
        return ""
    head = re.split(r"\s*(?:,|&|/|\||;|\bfeat\b\.?|\bft\b\.?|\bx\b|\band\b)\s*", artist, maxsplit=1, flags=re.IGNORECASE)
    return head[0].strip() if head else artist.strip()


def artist_tokens(artist: str) -> frozenset[str]:
    """All artist name tokens, for order-independent overlap scoring."""
    return frozenset(token for token in normalize_text(artist).split() if token)


def detect_script(value: str) -> str:
    """Best-effort language hint from the dominant Unicode block."""
    counts: dict[str, int] = {}
    for char in value:
        if not char.isalpha():
            continue
        try:
            name = unicodedata.name(char)
        except ValueError:
            continue
        block = name.split(" ")[0]
        counts[block] = counts.get(block, 0) + 1
    if not counts:
        return ""
    dominant = max(counts, key=counts.__getitem__)
    return {
        "MALAYALAM": "ml",
        "TAMIL": "ta",
        "DEVANAGARI": "hi",
        "TELUGU": "te",
        "KANNADA": "kn",
        "BENGALI": "bn",
        "GUJARATI": "gu",
        "GURMUKHI": "pa",
        "ORIYA": "or",
        "LATIN": "en",
    }.get(dominant, "")


def _stamp_ms(minutes: str, seconds: str, fraction: str | None) -> int:
    total = int(minutes) * 60_000 + int(seconds) * 1000
    if fraction:
        # LRC uses centiseconds; some providers emit milliseconds.
        digits = fraction[:3]
        scale = {1: 100, 2: 10, 3: 1}[len(digits)]
        total += int(digits) * scale
    return total


def parse_lrc(payload: str) -> tuple[list[LyricLine], int, str]:
    """Parse LRC text into ordered lines.

    Returns the lines, any global offset declared by the file, and a language
    tag if the file carries one. Timestamps are kept exactly as authored — end
    times are derived from the next line's start so gaps stay real gaps.
    """
    if not payload:
        return [], 0, ""

    offset_ms = 0
    language = ""
    staged: list[tuple[int, str, list[LyricWord]]] = []

    for raw_line in payload.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        metadata = _LRC_METADATA.match(line)
        if metadata:
            tag, value = metadata.group(1).lower(), metadata.group(2).strip()
            if tag == "offset":
                try:
                    offset_ms = int(float(value))
                except ValueError:
                    offset_ms = 0
            elif tag == "lang":
                language = value
            continue

        match = _LRC_LINE.match(line)
        if not match:
            continue

        stamps, text = match.group(1), match.group(2).strip()
        words = _parse_words(text)
        clean = _WORD_STAMP.sub("", text).strip()
        for stamp in _LRC_STAMP.finditer(stamps):
            start = _stamp_ms(stamp.group(1), stamp.group(2), stamp.group(3))
            staged.append((start, clean, words))

    if not staged:
        return [], offset_ms, language

    staged.sort(key=lambda entry: entry[0])

    lines: list[LyricLine] = []
    for index, (start, text, words) in enumerate(staged):
        if index + 1 < len(staged):
            end = staged[index + 1][0]
        elif words:
            end = max(word.end_ms for word in words)
        else:
            end = start + _DEFAULT_TAIL_MS
        # A blank LRC line marks silence; keep it as a real gap rather than
        # letting the previous line stay highlighted through it.
        if not text:
            continue
        if end <= start:
            end = start + _DEFAULT_TAIL_MS
        lines.append(LyricLine(start_ms=start, end_ms=end, text=text, words=words))

    return lines, offset_ms, language


def _parse_words(text: str) -> list[LyricWord]:
    """Enhanced-LRC word timings, when the provider supplies them."""
    stamps = list(_WORD_STAMP.finditer(text))
    if len(stamps) < 2:
        return []
    words: list[LyricWord] = []
    for index, stamp in enumerate(stamps):
        start = _stamp_ms(stamp.group(1), stamp.group(2), stamp.group(3))
        tail = stamps[index + 1].start() if index + 1 < len(stamps) else len(text)
        chunk = text[stamp.end() : tail].strip()
        if not chunk:
            continue
        end = (
            _stamp_ms(stamps[index + 1].group(1), stamps[index + 1].group(2), stamps[index + 1].group(3))
            if index + 1 < len(stamps)
            else start + _DEFAULT_TAIL_MS
        )
        words.append(LyricWord(text=chunk, start_ms=start, end_ms=max(end, start + 1)))
    return words


def clean_plain_text(payload: str) -> str:
    """Strip any stray timestamps and collapse excess blank lines."""
    if not payload:
        return ""
    lines = []
    for raw_line in payload.splitlines():
        line = _WORD_STAMP.sub("", _LRC_STAMP.sub("", raw_line)).rstrip()
        if _LRC_METADATA.match(line.strip()):
            continue
        lines.append(line.strip())
    collapsed: list[str] = []
    for line in lines:
        if not line and (not collapsed or not collapsed[-1]):
            continue
        collapsed.append(line)
    return "\n".join(collapsed).strip()


def clamp_tail(lines: list[LyricLine], duration_ms: int | None) -> list[LyricLine]:
    """Keep the final line from hanging until the end of a long outro."""
    if not lines:
        return lines
    last = lines[-1]
    ceiling = last.start_ms + _MAX_TAIL_MS
    if duration_ms:
        ceiling = min(ceiling, max(duration_ms, last.start_ms + 1))
    if last.end_ms <= ceiling:
        return lines
    return lines[:-1] + [
        LyricLine(start_ms=last.start_ms, end_ms=ceiling, text=last.text, words=last.words)
    ]
