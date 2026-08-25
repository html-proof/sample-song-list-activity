from abc import ABC, abstractmethod


class MusicProvider(ABC):
    name: str

    @abstractmethod
    async def close(self) -> None: ...

    @abstractmethod
    async def search_songs(self, query: str, limit: int = 10) -> list[dict]: ...

    @abstractmethod
    async def search_albums(self, query: str, limit: int = 10) -> list[dict]: ...

    @abstractmethod
    async def search_artists(self, query: str, limit: int = 10) -> list[dict]: ...

    @abstractmethod
    async def search_playlists(self, query: str, limit: int = 10) -> list[dict]: ...

    @abstractmethod
    async def get_song(self, seokey: str) -> dict: ...

    @abstractmethod
    async def get_album(self, seokey: str) -> dict: ...

    @abstractmethod
    async def get_artist(self, seokey: str, limit: int = 10, page: int = 1) -> dict: ...

    @abstractmethod
    async def get_artist_tracks(self, artist_id: str, limit: int = 25, page: int = 1) -> dict: ...

    @abstractmethod
    async def get_similar_artists(self, artist_id: str, limit: int = 10) -> list[dict]: ...

    @abstractmethod
    async def get_similar_albums(self, album_id: str, limit: int = 10) -> list[dict]: ...

    @abstractmethod
    async def trending(self, languages: list[str], limit: int = 25) -> list[dict]: ...

    @abstractmethod
    async def new_releases(self, languages: list[str], limit: int = 25) -> list[dict]: ...

    @abstractmethod
    async def charts(self, limit: int = 10) -> list[dict]: ...

    @abstractmethod
    async def get_provider_playlist(self, seokey: str) -> list[dict]: ...
