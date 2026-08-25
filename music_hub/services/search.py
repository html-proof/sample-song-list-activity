import asyncio
import hashlib
import re
import unicodedata
from difflib import SequenceMatcher
from uuid import UUID

from music_hub.cache import RedisCache
from music_hub.config import Settings
from music_hub.providers.base import MusicProvider
from music_hub.repositories.history import HistoryRepository
from music_hub.services.settings import SettingsService


_SOUNDTRACK_HINTS = frozenset({"album", "film", "movie", "ost", "soundtrack"})
_TOKEN_PATTERN = re.compile(r"[\w]+", re.UNICODE)
_PUNCTUATION = re.compile(r"[^\w\s]", re.UNICODE)

#: The four content types search groups results into. Every result carries one
#: of these in its ``type`` field before it leaves this service.
SONG = "song"
ARTIST = "artist"
ALBUM = "album"
PLAYLIST = "playlist"

_GROUPS: dict[str, str] = {
    "songs": SONG,
    "artists": ARTIST,
    "albums": ALBUM,
    "playlists": PLAYLIST,
}

#: Ranking tiers, highest first. A result scores the best tier it reaches, so
#: an exact title always outranks something that merely contains the query.
_EXACT_TITLE = 100
_STARTS_WITH = 90
_EXACT_ARTIST = 80
_EXACT_ALBUM = 70
_EXACT_PLAYLIST = 60
_CONTAINS = 40
_FUZZY_CEILING = 30

#: Applied only when two results from different groups score identically, so
#: "arijit singh" surfaces the artist while "tum hi ho" surfaces the song.
_TOP_RESULT_PREFERENCE = {ARTIST: 3, SONG: 2, ALBUM: 1, PLAYLIST: 0}


class SearchService:
    def __init__(
        self,
        provider: MusicProvider,
        history: HistoryRepository,
        cache: RedisCache,
        settings: Settings,
        settings_repository: SettingsService | None = None,
    ) -> None:
        self.provider = provider
        self.history = history
        self.cache = cache
        self.settings = settings
        self.settings_repository = settings_repository

    async def _save_history(self, user_id: UUID) -> bool:
        if self.settings_repository is None:
            return True
        privacy = await self.settings_repository.get_group(user_id, "privacy")
        return bool(privacy["save_search_history"])

    async def record_event(
        self,
        user_id: UUID,
        query: str,
        result_type: str | None,
        clicked_result_id: str | None,
    ) -> bool:
        if not await self._save_history(user_id):
            return False
        await self.history.add_search(user_id, query, result_type, clicked_result_id)
        await self._invalidate_recommendations(user_id)
        return True

    async def search(self, user_id: UUID, query: str, result_type: str, limit: int) -> dict:
        normalized = self._normalize(query)
        digest = hashlib.sha256(f"{result_type}:{normalized}:{limit}".encode()).hexdigest()
        cache_key = f"search:{digest}"
        cached = await self.cache.get_json(cache_key)
        if cached is not None:
            await self._record(user_id, query, result_type)
            return await self._finalize(user_id, query, cached)

        result = await self._collect(query, result_type, limit)

        cache_ttl = (
            min(self.settings.search_cache_ttl, 60)
            if result_type in {"all", "songs"}
            else self.settings.search_cache_ttl
        )
        await self.cache.set_json(cache_key, result, cache_ttl)
        await self._record(user_id, query, result_type)
        return await self._finalize(user_id, query, result)

    async def _collect(self, query: str, result_type: str, limit: int) -> dict:
        """Fetch, classify, rank and de-duplicate each group.

        Accuracy is settled here, before anything is handed to the client:
        ranking one mixed pile and splitting it afterwards lets an unrelated
        album outrank the song the user actually typed.
        """
        if result_type == "songs":
            songs = self._prepare(
                query, await self._safely(self.provider.search_songs, query, limit), SONG
            )
            if self._has_soundtrack_intent(query) or self._weak_song_match(query, songs):
                albums = await self._safely(self.provider.search_albums, query, limit)
                songs = await self._promote_soundtrack_tracks(query, songs, albums, limit)
                songs = await self._promote_title_album_tracks(query, songs, albums, limit)
            return {"songs": songs}

        if result_type in {"albums", "artists", "playlists"}:
            fetch = {
                "albums": self.provider.search_albums,
                "artists": self.provider.search_artists,
                "playlists": self.provider.search_playlists,
            }[result_type]
            items = await self._safely(fetch, query, limit)
            return {result_type: self._prepare(query, items, _GROUPS[result_type])}

        songs, albums, artists, playlists = await asyncio.gather(
            self._safely(self.provider.search_songs, query, limit),
            self._safely(self.provider.search_albums, query, limit),
            self._safely(self.provider.search_artists, query, limit),
            self._safely(self.provider.search_playlists, query, limit),
        )
        ranked_songs = self._prepare(query, songs, SONG)
        ranked_songs = await self._promote_soundtrack_tracks(
            query, ranked_songs, albums, limit
        )
        ranked_songs = await self._promote_title_album_tracks(
            query, ranked_songs, albums, limit
        )
        return {
            "songs": ranked_songs,
            "albums": self._prepare(query, albums, ALBUM),
            "artists": self._prepare(query, artists, ARTIST),
            "playlists": self._prepare(query, playlists, PLAYLIST),
        }

    @staticmethod
    async def _safely(fetch, query: str, limit: int) -> list[dict]:
        """One failing group must never empty the whole search."""
        try:
            result = await fetch(query, limit)
        except Exception:
            return []
        if not isinstance(result, list):
            return []
        return [item for item in result if isinstance(item, dict)]

    def _prepare(self, query: str, items: list[dict], kind: str) -> list[dict]:
        typed = [{**item, "type": item.get("type") or kind} for item in items]
        return self._rank(query, self._deduplicate(typed, kind))

    async def _record(self, user_id: UUID, query: str, result_type: str) -> None:
        if await self._save_history(user_id):
            await self.history.add_search(user_id, query, result_type)
            await self._invalidate_recommendations(user_id)

    async def _finalize(self, user_id: UUID, query: str, result: dict) -> dict:
        filtered = await self._apply_content_settings(user_id, result)
        payload: dict = {"query": query}
        for group in _GROUPS:
            value = filtered.get(group)
            payload[group] = value if isinstance(value, list) else []
        # Computed after filtering so a hidden explicit track can never become
        # the headline result.
        payload["top_result"] = self._top_result(query, payload)
        return payload

    async def _invalidate_recommendations(self, user_id: UUID) -> None:
        await self.cache.delete_pattern(f"recommendations:{user_id}:*")

    async def _apply_content_settings(self, user_id: UUID, result: dict) -> dict:
        if self.settings_repository is None:
            return result
        playback = await self.settings_repository.get_group(user_id, "playback")
        if playback["explicit_content"]:
            return result
        filtered: dict = {}
        for key, value in result.items():
            if isinstance(value, list):
                filtered[key] = [item for item in value if not self._is_explicit(item)]
            else:
                filtered[key] = value
        return filtered

    @staticmethod
    def _is_explicit(item: object) -> bool:
        if not isinstance(item, dict):
            return False
        value = item.get("explicit_content", item.get("is_explicit", item.get("explicit")))
        return value is True or str(value).casefold() in {"1", "true", "yes", "explicit"}

    # ------------------------------------------------------------------ text

    @staticmethod
    def _normalize(value: object) -> str:
        """Casefold and drop punctuation while preserving every script.

        NFKC keeps Malayalam, Tamil and Devanagari intact; folding to ASCII
        would erase the very names being searched for.
        """
        text = unicodedata.normalize("NFKC", str(value or "")).casefold()
        return " ".join(_PUNCTUATION.sub(" ", text).split())

    @classmethod
    def _tokens(cls, value: object) -> set[str]:
        return {token.casefold() for token in _TOKEN_PATTERN.findall(str(value or ""))}

    @staticmethod
    def _title(item: dict) -> str:
        return str(item.get("title") or item.get("name") or "")

    @classmethod
    def _primary_artist(cls, item: dict) -> str:
        artists = str(item.get("artists") or item.get("artist_name") or "")
        return cls._normalize(artists.split(",")[0])

    # --------------------------------------------------------------- ranking

    @classmethod
    def _score(cls, query: str, item: dict) -> float:
        target = cls._normalize(cls._title(item))
        if not target:
            return 0.0
        if target == query:
            return _EXACT_TITLE
        if target.startswith(query):
            return _STARTS_WITH
        if cls._primary_artist(item) == query:
            return _EXACT_ARTIST
        if cls._normalize(item.get("album")) == query:
            return _EXACT_ALBUM
        if cls._normalize(item.get("playlist_title")) == query:
            return _EXACT_PLAYLIST
        if query in target:
            return _CONTAINS
        return SequenceMatcher(None, query, target).ratio() * _FUZZY_CEILING

    @classmethod
    def _rank(cls, query: str, items: list[dict]) -> list[dict]:
        normalized = cls._normalize(query)
        if not normalized:
            return items
        # Stable sort: inside a tier the provider's own relevance order stands.
        return sorted(items, key=lambda item: -cls._score(normalized, item))

    def _top_result(self, query: str, payload: dict) -> dict | None:
        normalized = self._normalize(query)
        if not normalized:
            return None
        best: dict | None = None
        best_key: tuple[float, int] | None = None
        for group, kind in _GROUPS.items():
            # Each group is already ranked, so only its leader can win.
            for item in payload[group][:1]:
                key = (self._score(normalized, item), _TOP_RESULT_PREFERENCE[kind])
                if best_key is None or key > best_key:
                    best, best_key = item, key
        return best

    # ------------------------------------------------------------ duplicates

    @classmethod
    def _identity(cls, item: dict, kind: str) -> tuple:
        title = cls._normalize(cls._title(item))
        if kind == SONG:
            return (title, cls._primary_artist(item), str(item.get("duration") or ""))
        if kind == ARTIST:
            return (title,)
        if kind == ALBUM:
            return (title, cls._primary_artist(item))
        return (
            str(item.get("provider") or ""),
            str(
                item.get("playlist_id")
                or item.get("provider_id")
                or item.get("seokey")
                or ""
            ),
        )

    @classmethod
    def _deduplicate(cls, items: list[dict], kind: str) -> list[dict]:
        output: list[dict] = []
        seen: set[tuple] = set()
        for item in items:
            identity = cls._identity(item, kind)
            if not any(identity) or identity in seen:
                continue
            seen.add(identity)
            output.append(item)
        return output

    # ----------------------------------------------------------- soundtracks

    @classmethod
    def _has_soundtrack_intent(cls, query: str) -> bool:
        return bool(cls._tokens(query) & _SOUNDTRACK_HINTS)

    @classmethod
    def _matching_album(cls, query: str, albums: list[dict]) -> dict | None:
        query_tokens = cls._tokens(query) - _SOUNDTRACK_HINTS
        if not query_tokens:
            return None

        for album in albums:
            searchable = " ".join(
                str(album.get(field) or "")
                for field in ("title", "album", "artists", "language")
            )
            if query_tokens <= cls._tokens(searchable) and album.get("seokey"):
                return album
        return None

    def _weak_song_match(self, query: str, songs: list[dict]) -> bool:
        """True when nothing in the song results really is what was typed."""
        normalized = self._normalize(query)
        if not normalized:
            return False
        return not any(self._score(normalized, song) >= _STARTS_WITH for song in songs)

    @classmethod
    def _album_titled(cls, query: str, albums: list[dict]) -> dict | None:
        """The album whose name *is* the query, ignoring a trailing qualifier.

        "Pattalam (Original Motion Picture Soundtrack)" is the album called
        Pattalam; "Arijit Singh Bollywood Hits" is a compilation that merely
        mentions him, and is deliberately not matched.
        """
        normalized = cls._normalize(query)
        if not normalized:
            return None
        for album in albums:
            bare = re.sub(r"\s*[(\[][^)\]]*[)\]]\s*$", "", cls._title(album)).strip()
            if cls._normalize(bare) == normalized and album.get("seokey"):
                return album
        return None

    async def _promote_title_album_tracks(
        self,
        query: str,
        songs: list[dict],
        albums: list[dict],
        limit: int,
    ) -> list[dict]:
        """Fill in songs from an album that is named exactly like the query.

        Some titles exist only as an album: the provider's song search for
        "pattalam" returns songs that merely contain the word, while the album
        called Pattalam holds the tracks the user was after. This runs only
        when no song is a strong match, so it costs a request only when the
        song results were going to be poor anyway.
        """
        if not self._weak_song_match(query, songs):
            return songs
        album = self._album_titled(query, albums)
        if album is None:
            return songs
        return await self._prepend_album_tracks(album, songs, limit)

    async def _promote_soundtrack_tracks(
        self,
        query: str,
        songs: list[dict],
        albums: list[dict],
        limit: int,
    ) -> list[dict]:
        if not self._has_soundtrack_intent(query):
            return songs

        album = self._matching_album(query, albums)
        if album is None:
            return songs
        return await self._prepend_album_tracks(album, songs, limit)

    async def _prepend_album_tracks(
        self,
        album: dict,
        songs: list[dict],
        limit: int,
    ) -> list[dict]:
        try:
            details = await self.provider.get_album(str(album["seokey"]))
        except Exception:
            return songs
        tracks = details.get("tracks") if isinstance(details, dict) else None
        if not isinstance(tracks, list):
            return songs

        output: list[dict] = []
        seen: set[str] = set()
        for item in [*tracks, *songs]:
            if not isinstance(item, dict):
                continue
            identity = str(
                item.get("provider_id")
                or item.get("track_id")
                or item.get("song_id")
                or item.get("seokey")
                or ""
            )
            if not identity or identity in seen:
                continue
            seen.add(identity)
            # An album's track list is songs, whatever the album row said.
            output.append({**item, "type": SONG})
            if len(output) >= limit:
                break
        return output
