import asyncio
import aiohttp
from api.songs.songs import Songs
from api.albums.albums import Albums
from api.artists.artists import Artists
from api.trending.trending import Trending
from api.newreleases.newreleases import NewReleases
from api.charts.charts import Charts
from api.playlists.playlists import Playlists
from api import endpoints
from api.functions import Functions
from api.errors import Errors
from api.discovery.discovery import Discovery

class GaanaPy(Songs, Albums, Artists, Trending, NewReleases, Charts, Playlists, Discovery):
    def __init__(self):
        self.aiohttp = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=30)
        )
        self.api_endpoints = endpoints
        self.functions = Functions()
        self.errors = Errors()
        self._request_semaphore = asyncio.Semaphore(20)

    async def _safe_request(self, method: str, url: str, **kwargs) -> dict:
        for attempt in range(3):
            try:
                async with self._request_semaphore:
                    async with self.aiohttp.request(method, url, **kwargs) as response:
                        if response.status == 200:
                            result = await response.json()
                            if isinstance(result, dict):
                                return result
                            return await self.errors.no_results()
                        retryable = response.status == 429 or response.status >= 500
                if retryable and attempt < 2:
                    await asyncio.sleep(0.25 * (2 ** attempt))
                    continue
                return await self.errors.no_results()
            except (aiohttp.ClientError, asyncio.TimeoutError, ValueError, TypeError):
                if attempt < 2:
                    await asyncio.sleep(0.25 * (2 ** attempt))
                    continue
                return await self.errors.no_results()
        return await self.errors.no_results()
