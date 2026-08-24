from .models import LyricLine


def validated_lines(lines: list[LyricLine], duration_ms: int | None = None) -> list[LyricLine]:
    """Return ordered, non-overlapping timed lines or an empty list."""
    if not lines:
        return []
    output: list[LyricLine] = []
    previous_start = -1
    for index, line in enumerate(lines):
        if line.start_ms is None or line.start_ms < previous_start:
            return []
        next_start = lines[index + 1].start_ms if index + 1 < len(lines) else None
        end_ms = line.end_ms or next_start or duration_ms
        if end_ms is None or end_ms <= line.start_ms:
            return []
        if duration_ms and line.start_ms > duration_ms + 5_000:
            return []
        words = line.words
        if any(word.end_ms <= word.start_ms for word in words):
            return []
        output.append(line.model_copy(update={"end_ms": end_ms}))
        previous_start = line.start_ms
    return output
