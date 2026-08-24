from abc import ABC, abstractmethod

from music_hub.lyrics.models import LyricsCandidate, SongIdentity


class LyricsProvider(ABC):
    """A lyrics source, deliberately separate from the music provider.

    The music provider supplies catalog metadata and audio; it is never asked
    to also be the lyrics database.
    """

    name: str

    @abstractmethod
    async def close(self) -> None: ...

    @abstractmethod
    async def search(self, identity: SongIdentity) -> list[LyricsCandidate]:
        """Return candidates for the recording, best-effort and unranked.

        Implementations must not raise on "nothing found" — return an empty
        list. Raise only when the provider itself is unreachable, so the
        service can distinguish `not_found` from `temporary_error`.
        """


class NullLyricsProvider(LyricsProvider):
    """Used when no lyrics source is configured, so the API still answers."""

    name = "none"

    async def close(self) -> None:
        return None

    async def search(self, identity: SongIdentity) -> list[LyricsCandidate]:
        return []
