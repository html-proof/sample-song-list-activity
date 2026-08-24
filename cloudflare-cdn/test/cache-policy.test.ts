import { describe, expect, it } from "vitest";

import { cacheDecision } from "../src/cache-policy";

const request = (
  path: string,
  init: RequestInit = {},
): Request => new Request(`https://cdn.example.test${path}`, init);

describe("cacheDecision", () => {
  it("caches only explicitly public routes", () => {
    expect(cacheDecision(request("/openapi.json"))).toEqual({
      cacheable: true,
      reason: "public-route",
      ttlSeconds: 300,
    });
    expect(cacheDecision(request("/api/v1/home")).cacheable).toBe(false);
  });

  it("bypasses authenticated and cookie-bearing requests", () => {
    expect(
      cacheDecision(
        request("/openapi.json", {
          headers: { authorization: "Bearer firebase-token" },
        }),
      ).reason,
    ).toBe("authorization");
    expect(
      cacheDecision(
        request("/docs", { headers: { cookie: "session=value" } }),
      ).reason,
    ).toBe("cookie");
  });

  it("bypasses mutations, range requests, and query variants", () => {
    expect(cacheDecision(request("/", { method: "POST" })).reason).toBe(
      "method",
    );
    expect(
      cacheDecision(request("/", { headers: { range: "bytes=0-100" } })).reason,
    ).toBe("range");
    expect(cacheDecision(request("/docs?theme=dark")).reason).toBe("query");
  });

  it("never caches health or readiness checks", () => {
    expect(cacheDecision(request("/health")).reason).toBe("private-route");
    expect(cacheDecision(request("/ready")).reason).toBe("private-route");
  });
});
