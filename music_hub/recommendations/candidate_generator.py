import asyncio

from music_hub.providers.base import MusicProvider


class CandidateGenerator:
    def __init__(self, provider: MusicProvider) -> None:
        self.provider = provider

    async def generate(self, raw_signals: dict) -> list[dict]:
        recommendation_settings = raw_signals.get("recommendation_settings", {})
        languages = list(raw_signals.get("languages", {}))[:3] or ["hindi"]
        if recommendation_settings.get("cross_language_discovery", True):
            for language in ("english", "hindi", "tamil", "telugu", "malayalam"):
                if language not in languages:
                    languages.append(language)
                if len(languages) >= 5:
                    break
        artist_records = raw_signals.get("selected_artist_records", [])[:5]

        requests = [
            self.provider.trending([language.title()], 40)
            for language in languages
        ]
        requests.extend(
            self.provider.new_releases([language.title()], 30)
            for language in languages
        )
        if (
            recommendation_settings.get("enabled", True)
            and recommendation_settings.get("discover_new_artists", True)
        ):
            requests.extend(
                self._artist_candidates(str(artist["provider_artist_id"]))
                for artist in artist_records
                if artist.get("provider_artist_id")
            )
        results = await asyncio.gather(*requests, return_exceptions=True)

        candidates: list[dict] = []
        trending_count = len(languages)
        new_release_end = trending_count * 2
        for index, result in enumerate(results):
            if isinstance(result, Exception) or not isinstance(result, list):
                continue
            if index < trending_count:
                source = "trending"
            elif index < new_release_end:
                source = "new_release"
            else:
                source = "selected_artist"
            for item in result:
                if isinstance(item, dict) and (item.get("track_id") or item.get("stream_urls")):
                    candidates.append({**item, "recommendation_source": source})
        return candidates

    async def _artist_candidates(self, artist_id: str) -> list[dict]:
        result = await self.provider.get_artist_tracks(artist_id, limit=25, page=1)
        return result.get("tracks", [])
