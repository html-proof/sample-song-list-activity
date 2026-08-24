# Music Hub Cloudflare CDN

This Worker fronts `https://sample-song-list-activity.onrender.com` with a
Cloudflare edge endpoint.

It caches only exact, unauthenticated public documentation routes. Every
authenticated request, cookie-bearing request, mutation, query variant, range
request, health check, and application API route is streamed directly to the
origin without caching. This prevents one user's Firebase-protected response
from ever being served to another user.

Response headers expose the decision:

- `x-music-hub-cache: HIT|MISS|BYPASS`
- `x-music-hub-cache-reason: <policy reason>`

## Commands

```sh
npm install
npm run types
npm run check
npm run deploy
```

After deployment, set Flutter's production API base URL to the Worker URL:

```sh
flutter build apk --dart-define=API_BASE_URL=https://<worker>.workers.dev
```
