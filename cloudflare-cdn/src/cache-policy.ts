const PUBLIC_CACHE_TTL_SECONDS = new Map<string, number>([
  ["/", 60],
  ["/docs", 300],
  ["/redoc", 300],
  ["/openapi.json", 300],
]);

export type CacheDecision = Readonly<{
  cacheable: boolean;
  reason: string;
  ttlSeconds: number;
}>;

export function cacheDecision(request: Request): CacheDecision {
  if (request.method !== "GET") {
    return bypass("method");
  }
  if (request.headers.has("authorization")) {
    return bypass("authorization");
  }
  if (request.headers.has("cookie")) {
    return bypass("cookie");
  }
  if (request.headers.has("range")) {
    return bypass("range");
  }

  const url = new URL(request.url);
  if (url.search) {
    return bypass("query");
  }
  const ttlSeconds = PUBLIC_CACHE_TTL_SECONDS.get(url.pathname);
  if (ttlSeconds === undefined) {
    return bypass("private-route");
  }
  return { cacheable: true, reason: "public-route", ttlSeconds };
}

function bypass(reason: string): CacheDecision {
  return { cacheable: false, reason, ttlSeconds: 0 };
}
