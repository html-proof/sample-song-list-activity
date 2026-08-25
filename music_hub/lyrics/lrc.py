"""Parser for the LRC timestamped-lyrics format.

Only genuinely timestamped input produces timed lines. Plain text never gets
manufactured timestamps: callers receive an empty line list instead so the
caller can fall back to unsynchronised display.
"""

from __future__ import annotations

import re

from .models import LyricLine


_TIMESTAMP = re.compile(r"\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]")
_OFFSET = re.compile(r"^\s*\[offset:\s*([+-]?\d{1,7})\s*\]\s*$", re.IGNORECASE | re.MULTILINE)
_METADATA = re.compile(r"^\s*\[[a-z_]+:[^\]]*\]\s*$", re.IGNORECASE)
_WORD_TIMESTAMP = re.compile(r"<\d{1,3}:[0-5]\d(?:[.:]\d{1,3})?>")

# Guards against a malformed document turning into an unbounded line list.
_MAX_LINES = 2_000
# How long the closing line stays highlighted when the track length is unknown.
_TRAILING_HOLD_MS = 10_000


def parse_offset(lrc: str) -> int:
    """Return the ``[offset:]`` tag in milliseconds, or 0 when absent."""
    match = _OFFSET.search(lrc or "")
    if not match:
        return 0
    try:
        return int(match.group(1))
    except ValueError:
        return 0


def parse_lrc(
    lrc: str | None,
    *,
    offset_ms: int | None = None,
    total_ms: int | None = None,
) -> list[LyricLine]:
    """Return ordered, de-duplicated timed lines parsed from an LRC document.

    A single source line may carry several timestamps (``[00:12.00][01:44.00]``),
    which repeats the same text at each of them. ``end_ms`` is derived from the
    next line's start; the last line ends at ``total_ms`` when the track length
    is known, and otherwise gets a short hold so downstream validation still
    sees a complete, ordered document.
    """
    if not lrc:
        return []

    offset = parse_offset(lrc) if offset_ms is None else offset_ms
    collected: list[tuple[int, str]] = []

    for raw in lrc.splitlines():
        stamps = list(_TIMESTAMP.finditer(raw))
        if not stamps:
            continue
        text = _clean(raw[stamps[-1].end() :])
        if not text:
            # A timestamp with no text marks an instrumental gap, not a lyric.
            continue
        for stamp in stamps:
            collected.append((_milliseconds(stamp) + offset, text))
        if len(collected) > _MAX_LINES:
            return []

    if not collected:
        return []

    collected.sort(key=lambda item: item[0])

    lines: list[LyricLine] = []
    for index, (start_ms, text) in enumerate(collected):
        start = max(0, start_ms)
        # Two identical starts cannot both be highlighted; keep the first.
        if lines and lines[-1].start_ms == start:
            continue
        next_start = collected[index + 1][0] if index + 1 < len(collected) else None
        end = max(0, next_start) if next_start is not None else None
        lines.append(
            LyricLine(
                text=text,
                start_ms=start,
                end_ms=end if end is not None and end > start else None,
            )
        )

    # Recompute ends after de-duplication so no gap points at a dropped line.
    for index, line in enumerate(lines[:-1]):
        lines[index] = line.model_copy(update={"end_ms": lines[index + 1].start_ms})

    last = lines[-1]
    if total_ms and total_ms > last.start_ms:
        lines[-1] = last.model_copy(update={"end_ms": total_ms})
    else:
        lines[-1] = last.model_copy(update={"end_ms": last.start_ms + _TRAILING_HOLD_MS})
    return lines


def plain_lines(text: str | None) -> list[str]:
    """Return the untimed lyric lines of a plain-text document."""
    if not text:
        return []
    return [stripped for raw in text.splitlines() if (stripped := _clean(raw))]


def _clean(value: str) -> str:
    # Enhanced LRC embeds per-word timings inline; drop them rather than
    # letting them leak into the displayed text.
    return _WORD_TIMESTAMP.sub("", value).strip()


def _milliseconds(match: re.Match[str]) -> int:
    minutes = int(match.group(1))
    seconds = int(match.group(2))
    fraction = match.group(3) or "0"
    if len(fraction) == 1:
        milliseconds = int(fraction) * 100
    elif len(fraction) == 2:
        milliseconds = int(fraction) * 10
    else:
        milliseconds = int(fraction[:3])
    return minutes * 60_000 + seconds * 1_000 + milliseconds


def is_metadata_only(lrc: str | None) -> bool:
    """Return True when the document carries tags but no timed lyric lines."""
    if not lrc:
        return True
    for raw in lrc.splitlines():
        if not raw.strip() or _METADATA.match(raw):
            continue
        if _TIMESTAMP.search(raw):
            return False
    return True
