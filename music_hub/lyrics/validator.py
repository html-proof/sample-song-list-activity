from dataclasses import dataclass

from music_hub.lyrics.models import LyricLine

# A synced file with only a couple of stamped lines is usually a broken parse.
_MIN_SYNCED_LINES = 3
# The first line must land inside the track. Anything past the end (beyond a
# small grace for rounded provider durations) is matched to the wrong audio.
_MAX_START_OVERSHOOT_MS = 5_000
# Tolerate a little drift past the track end; providers round durations.
_END_GRACE_MS = 30_000


@dataclass(frozen=True, slots=True)
class ValidationResult:
    lines: list[LyricLine]
    valid: bool
    reason: str = ""


def validate_timeline(lines: list[LyricLine], duration_ms: int | None) -> ValidationResult:
    """Verify timestamps are monotonic, in range, and dense enough to be real.

    Anything that fails here falls back to plain lyrics — never to fabricated
    or partially-correct synchronization.
    """
    if not lines:
        return ValidationResult(lines=[], valid=False, reason="no timed lines")

    ordered = sorted(lines, key=lambda line: line.start_ms)

    repaired: list[LyricLine] = []
    for index, line in enumerate(ordered):
        if line.start_ms < 0:
            return ValidationResult(lines=[], valid=False, reason="negative timestamp")

        end = line.end_ms
        # Clamp an overlapping end to the next start rather than discarding the
        # line: overlap is a common authoring artifact, not a broken file.
        if index + 1 < len(ordered):
            next_start = ordered[index + 1].start_ms
            if end > next_start:
                end = next_start
        if end <= line.start_ms:
            end = line.start_ms + 1
        repaired.append(
            LyricLine(start_ms=line.start_ms, end_ms=end, text=line.text, words=line.words)
        )

    timed = [line for line in repaired if line.text.strip()]
    if len(timed) < _MIN_SYNCED_LINES:
        return ValidationResult(lines=[], valid=False, reason="too few timed lines")

    if duration_ms:
        if timed[0].start_ms > duration_ms + _MAX_START_OVERSHOOT_MS:
            return ValidationResult(lines=[], valid=False, reason="lyrics start after track end")
        if timed[-1].start_ms > duration_ms + _END_GRACE_MS:
            return ValidationResult(lines=[], valid=False, reason="lyrics run past track end")

    return ValidationResult(lines=repaired, valid=True)


def validate_words(lines: list[LyricLine]) -> bool:
    """True only when every line's word timings sit inside the line itself."""
    saw_words = False
    for line in lines:
        if not line.words:
            continue
        saw_words = True
        previous_end = line.start_ms
        for word in line.words:
            if word.start_ms < previous_end - 1 or word.end_ms <= word.start_ms:
                return False
            if word.end_ms > line.end_ms + 1000:
                return False
            previous_end = word.end_ms
    return saw_words
