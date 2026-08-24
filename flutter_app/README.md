# Music Hub Flutter client

Music Hub is the thin Flutter client for the GaanaPy-backed Music Hub API. Firebase handles identity, while all profiles, preferences, discovery, library state, listening history, and recommendations flow through the FastAPI backend. The app never connects directly to PostgreSQL.

## Included

- Firebase Google sign-in and backend session synchronization
- Language and artist onboarding
- Personalized, cache-backed home feed with cursor pagination
- Debounced and cancellable song, artist, and album search
- Liked songs, followed artists, playlists, and recent listening
- Persistent mini-player and full player with queue, seek, shuffle, and repeat
- Android/iOS background playback and media controls
- Mobile offline downloads for provider-supported direct audio files
- Artist, album, profile, playback, content, and privacy screens
- Offline status and resilient cached home data

## First-time setup

1. Enable **Developer Mode** in Windows settings. Flutter plugins use symbolic links during local builds.
2. Start the API from the repository root and expose its base URL to the device or browser.
3. The Android app `com.musichub.app` and web app are configured for Firebase project `personal-songs`. Register the iOS app separately before building for iPhone.
4. Run `flutterfire configure --project=personal-songs` when adding or replacing Firebase platforms.
5. For Google sign-in, enable the Google provider in Firebase Authentication. Add the Android SHA fingerprints and iOS URL scheme required by the Firebase console.

The backend needs Firebase Admin credentials or Application Default Credentials. The Flutter app needs only the public Firebase client configuration; never place the Supabase database URL or service credentials in this folder.

## Run

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000 `
  --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-oauth-client-id
```

For an Android emulator, the default API URL is `http://10.0.2.2:8000`. For web and desktop it is `http://localhost:8000`. A physical device needs the computer's LAN address or a secure hosted API URL.

Release builds default to the Cloudflare CDN endpoint:

```text
https://music-hub-cdn.imeseban.workers.dev
```

`API_BASE_URL` can still override it for staging or a custom domain. The CDN
streams authenticated application requests directly to Render without caching
them and edge-caches only explicitly public documentation routes.

For iOS add `FIREBASE_IOS_APP_ID` and, if different, `FIREBASE_IOS_BUNDLE_ID`. Production builds should always use HTTPS.

## Check

```powershell
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=https://music-hub-cdn.imeseban.workers.dev
```

Offline downloads intentionally reject HLS playlists. Shipping HLS offline support requires provider-authorized packaging and encryption, not merely saving a playlist URL.
