from abc import ABC, abstractmethod

from music_hub.lyrics import ProviderLyricsCandidate, SongIdentity


class LyricsProviderTemporaryError(Exception):
    """The lyrics provider failed in a way that may succeed when retried."""


class LyricsProvider(ABC):
    name: str
    configured: bool = True

    @abstractmethod
    async def search(self, identity: SongIdentity) -> list[ProviderLyricsCandidate]: ...

    @abstractmethod
    async def close(self) -> None: ...
