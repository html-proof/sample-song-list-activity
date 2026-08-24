# Music Hub production backend

The production backend lives beside the original GaanaPy API. It does not
replace or duplicate Gaana's complete catalog. GaanaPy is used only through a
provider adapter; PostgreSQL stores application and user data.

## Architecture

```text
Flutter app
    │ Firebase Google ID token
    ▼
FastAPI /api/v1
    ├── Firebase token verification
    ├── Firebase UID → internal user UUID
    ├── application services and repositories
    ├── weighted recommendation engine
    ├── Supabase PostgreSQL
    ├── Redis / Upstash cache and seen-song sets
    └── MusicProvider
            └── GaanaProvider → existing GaanaPy → Gaana
```

Important boundaries:

- Firebase proves identity; it is not the application's database identity.
- The backend generates the internal UUID and resolves it on authenticated requests.
- Supabase stores users, preferences, history, events, likes, follows, and playlists.
- Gaana remains the live catalog source.
- Redis is optional. A Redis outage disables distributed cache/rate limiting but
  does not intentionally stop the API.

## Project layout

```text
music_hub/
├── main.py                 FastAPI lifecycle and application
├── config.py               environment configuration
├── container.py            dependency composition
├── dependencies.py         authenticated-user resolution
├── api/v1/                 HTTP routes
├── auth/                   Firebase verification
├── cache/                  Redis/Upstash client
├── database/               PostgreSQL client and migration
├── providers/              provider interface and Gaana adapter
├── recommendations/        candidates, scoring, diversity, cursors
├── repositories/           SQL persistence operations
├── schemas/                request and response contracts
└── services/               business use cases
```

The legacy API still runs from `app.py`. This separation permits a gradual
Flutter migration and preserves existing integrations.

## 1. Create the Supabase database

Create a Supabase project and run the migrations in filename order in the SQL editor:

```text
music_hub/database/migrations/001_initial.sql
music_hub/database/migrations/002_song_seokeys.sql
music_hub/database/migrations/003_grouped_settings.sql
```

Or apply every pending migration from the configured `DATABASE_URL`:

```bash
python -m music_hub.database.migrate
```

The migration creates:

- `users`
- `user_languages`
- `user_artists`
- `user_preferences`
- `listening_history`
- `music_events`
- `search_history`
- `liked_songs`
- `followed_artists`
- `playlists`
- `playlist_tracks`
- `downloads`
- `notification_preferences`
- `recommendation_profiles`

It also creates indexes, timestamp triggers, the event enum, foreign keys, and
row-level-security boundaries.

Because authentication is performed with Firebase rather than Supabase Auth,
no direct client-side Supabase policies are created. The Flutter app must call
FastAPI. FastAPI should connect with a trusted server-side PostgreSQL role.
Never put the PostgreSQL connection string in the Flutter application.

For hosted deployments, prefer Supabase's transaction-pooler connection string.

## 2. Configure Firebase Google authentication

In Firebase Console:

1. Create or select the Firebase project.
2. Enable Authentication → Sign-in method → Google.
3. Configure Android and/or iOS application identifiers for Flutter.
4. Set `FIREBASE_PROJECT_ID` on the deployment. This alone is enough to
   authenticate users: ID tokens are verified against Google's published
   signing certificates, which need no credentials.
5. A service account is only required for privileged Admin operations --
   token revocation checks (`FIREBASE_CHECK_REVOKED`) and account deletion.
   Provide it with **one** of:
   - `FIREBASE_CREDENTIALS_JSON` - the whole service-account JSON on one line.
     Use this on Render, Fly, and Heroku, where a file cannot be mounted.
   - `FIREBASE_CREDENTIALS_PATH` - a path to a securely mounted JSON file.
   - Application Default Credentials in the environment.

`/ready` reports which mode is active as `"firebase": "public"` or
`"firebase": "admin"`.

Do not commit the service-account file. `.env` is ignored by Git.

Only tokens whose Firebase `sign_in_provider` is `google.com` are accepted.

## 3. Configure environment variables

Copy `.env.example` to `.env` and replace every placeholder:

```powershell
Copy-Item .env.example .env
```

Required for authenticated endpoints:

```text
DATABASE_URL
FIREBASE_PROJECT_ID
```

Required only for revocation checks and account deletion (choose one):

```text
FIREBASE_CREDENTIALS_JSON
FIREBASE_CREDENTIALS_PATH
```

Recommended for production:

```text
REDIS_URL
CURSOR_SECRET
CORS_ORIGINS
```

`CURSOR_SECRET` must be a long random deployment secret because it signs feed
cursors. `CORS_ORIGINS` must contain only trusted web frontends.

## 4. Install and run

Development:

```sh
python -m venv .venv
pip install -r requirements-dev.txt
python -m uvicorn music_hub.main:app --reload
```

Production container:

```sh
docker compose -f docker-compose.backend.yml up --build
```

Open:

```text
http://127.0.0.1:8000/docs
```

System probes:

- `GET /health` confirms the process is running.
- `GET /ready` confirms that PostgreSQL is available and reports Redis state.

## 5. Flutter authentication lifecycle

After Google sign-in, retrieve the Firebase ID token and send it on every
authenticated request:

```http
Authorization: Bearer <firebase-id-token>
```

On application sign-in or token refresh, call:

```http
POST /api/v1/auth/session
Authorization: Bearer <firebase-id-token>
```

The backend verifies the token, resolves or creates the user, and returns the
internal UUID:

```json
{
  "id": "f54a4512-65e2-4d38-bda1-c83de9c7f633",
  "display_name": "Sebastian",
  "email": "user@example.com",
  "photo_url": "https://example.com/photo.jpg",
  "onboarding_completed": false,
  "created_at": "2026-08-24T12:00:00Z"
}
```

The Flutter application must not create or persist a replacement UUID. The ID
returned by FastAPI is the canonical application user ID.

Minimal Dart request shape:

```dart
final token = await FirebaseAuth.instance.currentUser!.getIdToken();
final response = await http.post(
  Uri.parse('$apiBase/api/v1/auth/session'),
  headers: {'Authorization': 'Bearer $token'},
);
```

## 6. Onboarding

Search artists dynamically:

```http
GET /api/v1/onboarding/artists?q=arijit&limit=20
```

Complete onboarding:

```http
PUT /api/v1/onboarding
Content-Type: application/json

{
  "languages": [
    {"language_code": "Malayalam", "priority": 3},
    {"language_code": "Tamil", "priority": 2},
    {"language_code": "English", "priority": 1}
  ],
  "artists": [
    {
      "provider": "gaana",
      "provider_artist_id": "12345",
      "artist_name": "Selected artist",
      "artist_image": "https://example.com/artist.jpg",
      "preference_score": 1.0
    }
  ]
}
```

The operation replaces the current onboarding selections atomically and marks
the user as onboarded.

## 7. API v1 map

Authentication and profile:

- `POST /api/v1/auth/session`
- `GET /api/v1/users/me`
- `GET|PUT /api/v1/onboarding`
- `GET|PATCH /api/v1/preferences`

Catalog and discovery:

- `GET /api/v1/search`
- `POST /api/v1/search/events`
- `GET /api/v1/songs/{seokey}`
- `GET /api/v1/artists/{seokey}`
- `GET /api/v1/artists/id/{artist_id}/tracks`
- `GET /api/v1/artists/id/{artist_id}/similar`
- `GET /api/v1/albums/{seokey}`
- `GET /api/v1/albums/id/{album_id}/similar`
- `GET /api/v1/home/trending`
- `GET /api/v1/home/new-releases`
- `GET /api/v1/home/charts`

Personal application data:

- `GET|PUT|DELETE /api/v1/library/likes...`
- `GET|PUT|DELETE /api/v1/library/artists...`
- `GET|POST|PATCH|DELETE /api/v1/playlists...`
- `POST /api/v1/history/listens`
- `POST /api/v1/history/events`
- `GET /api/v1/history/recent`
- `GET /api/v1/history/continue`

Feeds:

- `GET /api/v1/recommendations?cursor=...`
- `GET /api/v1/home?cursor=...`

## 8. Recommendation engine

The first version is deterministic, explainable weighted ranking rather than a
machine-learning model. It combines:

- preferred languages
- selected and followed artists
- likes and playlist additions
- completed and repeated plays
- recent searches
- song, artist, and language skips
- trending, new releases, and selected-artist tracks

Every ranked item includes `recommendation_score` and
`recommendation_reasons`. Diversity rules cap artist and language dominance.
An HMAC-signed cursor identifies the feed and offset. Redis caches the ranked
candidate pool and keeps a short-lived `seen:{user_id}` set so refreshes avoid
recently returned songs.

The home endpoint aggregates recommendations, trending, new releases, history,
continue-listening, language mixes, and artist discovery in one response.

## 9. Cache policy

Defaults are configured in `music_hub/config.py`:

- Search: 3 minutes
- Rich artist and album responses: 60 seconds because they currently include
  tokenized track playback URLs
- Trending: 5 minutes
- New releases: 10 minutes
- Recommendation pool: 5 minutes
- Seen-song set: 6 hours
- Playback-containing song objects: 60 seconds

Playback objects deliberately have the shortest cache because Gaana stream URLs
may contain expiring tokens.

## 10. Production checklist

- Apply the SQL migration.
- Set a strong `CURSOR_SECRET`.
- Restrict `CORS_ORIGINS`.
- Configure Firebase credentials outside the repository.
- Use the Supabase pooler and a trusted backend role.
- Configure Upstash/Redis with TLS.
- Put the API behind HTTPS.
- Add centralized logs and error reporting.
- Add provider contract monitoring.
- Review Gaana's terms and music playback rights before public distribution.
- Keep the provider interface so Gaana can be replaced without rewriting the
  user, library, or recommendation layers.

## Legacy API

The original API and its routes are still available:

```sh
python -m uvicorn app:app --reload
```

The production backend is the recommended entry point for the Flutter app:

```sh
python -m uvicorn music_hub.main:app --reload
```
