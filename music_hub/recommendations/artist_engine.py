"""Artist recommendation and artist search.

Kept separate from the song engine on purpose. The two answer different
questions and share only the signal repository and the cursor codec.
"""

from __future__ import annotations

import asyncio
import hashlib
from uuid import UUID, uuid4

from music_hub.cache import RedisCache
from music_hub.config import Settings
from music_hub.providers.base import MusicProvider
from music_hub.repositories.recommendations import RecommendationRepository
from music_hub.schemas.artists import ArtistPage

from .artist_identity import (
    artist_language,
    artist_name,
    artist_provider_id,
    deduplicate_artists,
    normalize,
)
from .artist_scoring import (
    apply_source_quotas,
    artist_ids,
    rank_artists,
    rank_search_results,
)
from .cursor import CursorCodec


# How much of a refreshed page is held stable. The rest rotates so the screen
# does not look frozen, without the list reshuffling randomly on every open.
STABLE_SHARE = 0.70

_SEED_ARTIST_LIMIT = 8
_SEARCH_SEED_LIMIT = 4


class ArtistRecommendationEngine:
    def __init__(
        self,
        repository: RecommendationRepository,
        provider: MusicProvider,
        cache: RedisCache,
        settings: Settings,
    ) -> None:
        self.repository = repository
        self.provider = provider
        self.cache = cache
        self.settings = settings
        self.cursor = CursorCodec(settings.cursor_secret.get_secret_value())

    # ------------------------------------------------------------------ search

    async def search(self, query: str, limit: int) -> list[dict]:
        """Artist-only search, ranked by how well the name answers the query."""
        normalized = " ".join(query.casefold().split())
        if not normalized:
            return []

        digest = hashlib.sha256(f"artists:{normalized}:{limit}".encode()).hexdigest()
        cache_key = f"artist_search:{digest}"
        cached = await self.cache.get_json(cache_key)
        if cached is not None:
            return cached

        # Over-fetch so ranking has room to move the exact match to the top even
        # when the provider buries it.
        try:
            raw = await self.provider.search_artists(query, min(limit * 3, 50))
        except Exception:
            raw = []
        artists = [item for item in raw if isinstance(item, dict)]
        ranked = rank_search_results(deduplicate_artists(artists), query)[:limit]
        result = [self._public(artist) for artist in ranked]
        await self.cache.set_json(cache_key, result, self.settings.search_cache_ttl)
        return result

    async def related(self, user_id: UUID, artist_id: str, limit: int) -> list[dict]:
        """Similar artists, re-ranked for this listener.

        The provider orders by its own notion of similarity; this adds the
        user's languages and history on top so a Malayalam listener does not get
        a page of unrelated Hindi artists.
        """
        try:
            raw = await self.provider.get_similar_artists(str(artist_id), limit * 2)
        except Exception:
            return []

        candidates = deduplicate_artists(
            [item for item in raw if isinstance(item, dict)]
        )
        if not candidates:
            return []

        signals = await self.repository.signals(user_id)
        ranked = rank_artists(
            candidates=candidates,
            languages=dict(signals.get("languages", {})),
            selected_artists={
                str(value) for value in signals.get("selected_artists", {})
            }
            | {str(value) for value in signals.get("followed_artists", set())},
            recent_artists={
                str(value) for value in signals.get("recent_artists", [])
            },
            liked_artists={str(value) for value in signals.get("liked_artists", [])},
        )
        return [self._public(artist) for artist in ranked[:limit]]

    # ----------------------------------------------------------- recommendation

    async def recommend(
        self,
        user_id: UUID,
        cursor: str | None = None,
        limit: int = 30,
    ) -> ArtistPage:
        if cursor:
            seed, offset = self.cursor.decode(cursor)
        else:
            seed, offset = uuid4().hex, 0

        cache_key = f"artist_recommendations:{user_id}:{seed}"
        ranked = await self.cache.get_json(cache_key)
        if ranked is None:
            ranked = await self._build(user_id, seed)
            await self.cache.set_json(
                cache_key,
                ranked,
                self.settings.recommendation_cache_ttl,
            )

        page = ranked[offset : offset + limit]
        has_more = offset + limit < len(ranked)
        return ArtistPage(
            data=page,
            next_cursor=(
                self.cursor.encode(seed, offset + limit) if has_more else None
            ),
            has_more=has_more,
        )

    async def _build(self, user_id: UUID, seed: str) -> list[dict]:
        signals = await self.repository.signals(user_id)

        languages: dict[str, int] = dict(signals.get("languages", {}))
        selected = {str(value) for value in signals.get("selected_artists", {})}
        followed = {str(value) for value in signals.get("followed_artists", set())}
        recent = [str(value) for value in signals.get("recent_artists", [])]
        liked = [str(value) for value in signals.get("liked_artists", [])]
        search_terms = [str(value) for value in signals.get("search_terms", [])]

        candidates = await self._discover(
            languages=languages,
            selected_artists=list(selected | followed),
            recent_artists=recent,
            liked_artists=liked,
            search_terms=search_terms,
        )
        candidates = deduplicate_artists(candidates)

        ranked = rank_artists(
            candidates=candidates,
            languages=languages,
            selected_artists=selected | followed,
            recent_artists=set(recent),
            liked_artists=set(liked),
        )
        ranked = self._rotate(ranked, seed)
        # Quota the head of the list, where the user actually looks, then keep
        # the remainder in rank order for paging.
        head = apply_source_quotas(ranked, min(len(ranked), 60))
        chosen = {id(artist) for artist in head}
        tail = [artist for artist in ranked if id(artist) not in chosen]
        return [self._public(artist) for artist in [*head, *tail]]

    def _rotate(self, ranked: list[dict], seed: str) -> list[dict]:
        """Holds the top `STABLE_SHARE` still and shuffles the discovery tail.

        The shuffle is seeded by the cursor seed, so paging through one refresh
        stays consistent while the next refresh reorders the tail.
        """
        if len(ranked) < 4:
            return ranked
        pivot = max(1, int(len(ranked) * STABLE_SHARE))
        stable = ranked[:pivot]
        fresh = ranked[pivot:]
        if not fresh:
            return ranked
        digest = hashlib.sha256(seed.encode()).digest()
        rotation = int.from_bytes(digest[:4], "big") % len(fresh)
        return [*stable, *fresh[rotation:], *fresh[:rotation]]

    async def _discover(
        self,
        languages: dict[str, int],
        selected_artists: list[str],
        recent_artists: list[str],
        liked_artists: list[str],
        search_terms: list[str],
    ) -> list[dict]:
        """Fans out to the provider and labels every candidate with its source.

        The label is what the quota mix later works from, so a candidate reached
        through more than one route keeps the strongest of them.
        """
        requests: list = []
        sources: list[str] = []

        def seed_artists(ids: list[str], source: str, cap: int) -> None:
            for artist_id in list(dict.fromkeys(ids))[:cap]:
                if not artist_id:
                    continue
                requests.append(self._similar(artist_id))
                sources.append(source)

        seed_artists(selected_artists, "selected_artist", _SEED_ARTIST_LIMIT)
        seed_artists(recent_artists, "recent_artist", _SEED_ARTIST_LIMIT)
        seed_artists(liked_artists, "liked_artist", _SEED_ARTIST_LIMIT)

        for term in list(dict.fromkeys(search_terms))[:_SEARCH_SEED_LIMIT]:
            requests.append(self._search_artists(term))
            sources.append("search_artist")

        # Trending in the preferred languages is the only source that needs no
        # history, so a brand-new account still gets a populated screen.
        preferred = [name.title() for name in list(languages)[:3]] or ["Hindi"]
        for language in preferred:
            requests.append(self._trending_artists(language))
            sources.append("discovery")

        results = await asyncio.gather(*requests, return_exceptions=True)

        priority = {
            "selected_artist": 5,
            "recent_artist": 4,
            "liked_artist": 3,
            "search_artist": 2,
            "discovery": 1,
        }
        best: dict[str, dict] = {}
        for index, result in enumerate(results):
            if isinstance(result, Exception) or not isinstance(result, list):
                continue
            source = sources[index]
            for item in result:
                if not isinstance(item, dict):
                    continue
                name = artist_name(item)
                if not name:
                    continue
                key = normalize(name)
                existing = best.get(key)
                if existing is not None and priority[
                    str(existing.get("recommendation_source"))
                ] >= priority[source]:
                    continue
                best[key] = {**item, "recommendation_source": source}
        return list(best.values())

    async def _similar(self, artist_id: str) -> list[dict]:
        if not str(artist_id).isdigit():
            return []
        try:
            return await self.provider.get_similar_artists(str(artist_id), 15)
        except Exception:
            return []

    async def _search_artists(self, term: str) -> list[dict]:
        try:
            return await self.provider.search_artists(term, 8)
        except Exception:
            return []

    async def _trending_artists(self, language: str) -> list[dict]:
        """Derives artists from the language's trending tracks.

        The provider exposes no trending-artists feed, so the artists behind the
        trending songs stand in for one.
        """
        try:
            tracks = await self.provider.trending([language], 40)
        except Exception:
            return []

        artists: list[dict] = []
        seen: set[str] = set()
        for track in tracks:
            if not isinstance(track, dict):
                continue
            name = str(track.get("artists") or track.get("artist_name") or "").split(",")[0]
            identity = normalize(name)
            if not identity or identity in seen:
                continue
            seen.add(identity)
            artist_id = str(track.get("artist_ids") or "").split(",")[0].strip()
            artists.append(
                {
                    "name": name.strip(),
                    "artist_id": artist_id,
                    "seokey": track.get("artist_seokey"),
                    "language": track.get("language"),
                    "artwork_url": track.get("artwork_url") or track.get("artwork"),
                    "popularity": track.get("play_count") or track.get("favorite_count"),
                }
            )
        return artists

    @staticmethod
    def _public(artist: dict) -> dict:
        """The shape the app consumes, independent of which provider supplied it."""
        provider_ids = [
            str(value) for value in artist.get("provider_ids", []) or [] if value
        ]
        primary = artist_provider_id(artist)
        if primary and primary not in provider_ids:
            provider_ids.insert(0, primary)
        return {
            "provider": artist.get("provider", "gaana"),
            "artist_id": primary,
            "provider_ids": provider_ids,
            "name": artist_name(artist),
            "seokey": artist.get("seokey"),
            "language": artist.get("language"),
            "artwork_url": (
                artist.get("artwork_url")
                or artist.get("artist_image")
                or artist.get("image_url")
            ),
            "recommendation_source": artist.get("recommendation_source"),
            "recommendation_score": artist.get("recommendation_score"),
        }


__all__ = [
    "ArtistRecommendationEngine",
    "artist_ids",
    "artist_language",
]
