from abc import ABC, abstractmethod

from music_hub.lyrics import ProviderLyricsCandidate, SongIdentity


class LyricsProviderTemporaryError(Exception):
    """The lyrics provider failed in a way that may succeed when retried."""


class LyricsProvider(ABC):
    name: str
    configured: bool = True
    #: Whether the provider returns catalogue metadata of its own that can be
    #: scored against the requested recording. A provider that merely echoes
    #: the request back cannot be verified, so its results are only ever used
    #: as unsynchronised text of last resort.
    verifiable: bool = True

    @abstractmethod
    async def search(self, identity: SongIdentity) -> list[ProviderLyricsCandidate]: ...

    @abstractmethod
    async def close(self) -> None: ...
