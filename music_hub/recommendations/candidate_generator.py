import asyncio

from music_hub.providers.base import MusicProvider


class CandidateGenerator:
    def __init__(self, provider: MusicProvider) -> None:
        self.provider = provider

    async def generate(self, raw_signals: dict) -> list[dict]:
        recommendation_settings = raw_signals.get("recommendation_settings", {})
        personalized = bool(raw_signals.get("personalized", True))
        languages = (
            list(raw_signals.get("languages", {}))[:3]
            if personalized
            else []
        ) or ["hindi"]
        if recommendation_settings.get("cross_language_discovery", True):
            for language in ("english", "hindi", "tamil", "telugu", "malayalam"):
                if language not in languages:
                    languages.append(language)
                if len(languages) >= 5:
                    break
        selected_artist_ids = {
            str(artist["provider_artist_id"])
            for artist in raw_signals.get("selected_artist_records", [])
            if artist.get("provider_artist_id")
        }
        interest_artist_ids = (
            list(raw_signals.get("interest_artists", []))[:8]
            if personalized
            else []
        )

        requests = []
        sources: list[str] = []
        for language in languages:
            requests.append(self.provider.trending([language.title()], 40))
            sources.append("trending")
        for language in languages:
            requests.append(self.provider.new_releases([language.title()], 30))
            sources.append("new_release")
        if (
            personalized
            and recommendation_settings.get("enabled", True)
            and recommendation_settings.get("discover_new_artists", True)
        ):
            for artist_id in interest_artist_ids:
                requests.append(self._artist_candidates(str(artist_id)))
                sources.append(
                    "selected_artist"
                    if artist_id in selected_artist_ids
                    else "interest_artist"
                )
        results = await asyncio.gather(*requests, return_exceptions=True)

        candidates: list[dict] = []
        for index, result in enumerate(results):
            if isinstance(result, Exception) or not isinstance(result, list):
                continue
            source = sources[index]
            for item in result:
                if isinstance(item, dict) and (item.get("track_id") or item.get("stream_urls")):
                    candidates.append({**item, "recommendation_source": source})
        return candidates

    async def _artist_candidates(self, artist_id: str) -> list[dict]:
        result = await self.provider.get_artist_tracks(artist_id, limit=25, page=1)
        return result.get("tracks", [])
