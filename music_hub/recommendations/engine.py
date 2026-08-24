from uuid import UUID, uuid4

from music_hub.cache import RedisCache
from music_hub.config import Settings
from music_hub.repositories.recommendations import RecommendationRepository
from music_hub.schemas.recommendations import RecommendationPage

from .candidate_generator import CandidateGenerator
from .cursor import CursorCodec
from .diversity import diversify
from .scoring import RecommendationSignals, WeightedScorer, candidate_id


class RecommendationEngine:
    def __init__(
        self,
        repository: RecommendationRepository,
        generator: CandidateGenerator,
        cache: RedisCache,
        settings: Settings,
    ) -> None:
        self.repository = repository
        self.generator = generator
        self.cache = cache
        self.settings = settings
        self.scorer = WeightedScorer()
        self.cursor = CursorCodec(settings.cursor_secret.get_secret_value())

    async def recommend(
        self,
        user_id: UUID,
        cursor: str | None = None,
        limit: int = 25,
    ) -> RecommendationPage:
        if cursor:
            seed, offset = self.cursor.decode(cursor)
        else:
            seed, offset = uuid4().hex, 0

        cache_key = f"recommendations:{user_id}:{seed}"
        ranked = await self.cache.get_json(cache_key)
        if ranked is None:
            raw_signals = await self.repository.signals(user_id)
            candidates = await self.generator.generate(raw_signals)
            if not raw_signals.get("allow_explicit_content", True):
                candidates = [
                    candidate
                    for candidate in candidates
                    if not self._is_explicit(candidate)
                ]
            signals = RecommendationSignals.from_mapping(raw_signals)
            controls = raw_signals.get("recommendation_settings", {})
            diversity_level = int(controls.get("diversity_level", 50))
            max_per_artist = max(2, 6 - diversity_level // 25)
            max_per_language = max(6, 18 - diversity_level // 8)
            ranked = diversify(
                self.scorer.rank(candidates, signals, seed),
                max_per_artist=max_per_artist,
                max_per_language=max_per_language,
            )
            await self.cache.set_json(
                cache_key,
                ranked,
                self.settings.recommendation_cache_ttl,
            )

        recently_seen = await self.cache.members(f"seen:{user_id}")
        page: list[dict] = []
        index = offset
        while index < len(ranked) and len(page) < limit:
            item = ranked[index]
            index += 1
            if candidate_id(item) in recently_seen:
                continue
            page.append(item)

        returned_ids = [candidate_id(item) for item in page if candidate_id(item)]
        await self.cache.add_to_set(
            f"seen:{user_id}",
            returned_ids,
            self.settings.seen_songs_ttl,
        )
        has_more = index < len(ranked)
        return RecommendationPage(
            data=page,
            next_cursor=self.cursor.encode(seed, index) if has_more else None,
            has_more=has_more,
        )

    @staticmethod
    def _is_explicit(candidate: dict) -> bool:
        value = candidate.get(
            "explicit_content",
            candidate.get("is_explicit", candidate.get("explicit")),
        )
        return value is True or str(value).casefold() in {
            "1",
            "true",
            "yes",
            "explicit",
        }
