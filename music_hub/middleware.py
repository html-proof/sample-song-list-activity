from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


class RedisRateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path in {"/health", "/ready"} or request.url.path.startswith("/docs"):
            return await call_next(request)
        container = getattr(request.app.state, "container", None)
        if container is None or not container.cache.connected:
            return await call_next(request)
        client = request.client.host if request.client else "unknown"
        window = container.settings.rate_limit_window_seconds
        try:
            count = await container.cache.increment_window(f"rate:{client}", window)
        except Exception:
            # A cache outage should reduce protection, not take down the API.
            return await call_next(request)
        if count > container.settings.rate_limit_requests:
            return JSONResponse(
                status_code=429,
                content={"error": {"code": "rate_limited", "message": "Too many requests"}},
                headers={"Retry-After": str(window)},
            )
        return await call_next(request)
