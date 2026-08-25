from urllib.parse import quote_plus


class Playlists:
    async def search_playlists(self, search_query: str, limit: int) -> list:
        """Playlist search results, built from the search payload alone.

        Gaana's search rows carry everything a playlist card needs except the
        track count, which only playlistDetail knows. Fetching detail per row
        would turn one search into `limit` extra round trips, so the count is
        left absent and the card renders without it.
        """
        endpoints = self.api_endpoints
        errors = self.errors
        result = await self._safe_request(
            "POST", endpoints.search_playlists_url + quote_plus(search_query)
        )
        if isinstance(result, dict) and "error" in result:
            return result
        rows = []
        for group in result.get("gr") or []:
            if isinstance(group, dict):
                rows.extend(item for item in (group.get("gd") or []) if isinstance(item, dict))
        playlists = []
        for row in rows[:limit]:
            formatted = await self.format_json_playlists(row)
            if "error" not in formatted:
                playlists.append(formatted)
        if not playlists:
            return await errors.no_results()
        return playlists

    async def format_json_playlists(self, results: dict) -> dict:
        errors = self.errors

        seokey = results.get("seo")
        if not seokey:
            return await errors.invalid_seokey()

        artwork = results.get("aw") or ""
        languages = results.get("lang")
        data = {
            "seokey": seokey,
            "playlist_id": str(results.get("id") or results.get("iid") or ""),
            "title": results.get("ti", ""),
            "artists": results.get("sti", ""),
            "language": results.get("language")
            or (languages[0] if isinstance(languages, list) and languages else ""),
            "playlist_url": f"https://gaana.com/playlist/{seokey}",
            "images": {
                "urls": {
                    "large_artwork": artwork.replace("size_m", "size_l"),
                    "medium_artwork": artwork,
                    "small_artwork": artwork.replace("size_m", "size_s"),
                }
            },
        }
        return data

    async def get_playlist_info(self, playlist_id: str) -> dict:
        endpoints = self.api_endpoints
        errors = self.errors
        result = await self._safe_request("POST", endpoints.playlist_details_url + playlist_id)
        if isinstance(result, dict) and "error" in result:
            return result
        track_count = result.get('count')
        if not track_count:
            return await errors.no_results()
        track_ids = []
        tracks = result.get('tracks', [])
        for i in range(min(int(track_count), len(tracks))):
            seo = tracks[i].get('seokey') if isinstance(tracks[i], dict) else None
            if seo:
                track_ids.append(seo)
        if len(track_ids) == 0:
            return await errors.no_results()
        track_data = await self.get_track_info(track_ids)
        return track_data
