import 'package:firebase_core/firebase_core.dart';

abstract final class AppConfig {
  // API base URL — override at build time with --dart-define=API_BASE_URL=...
  // Defaults to the app's own origin: the music-hub-web worker serves these
  // static files AND proxies the backend API, so app and API share one origin.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://music-hub-web.imeseban.workers.dev',
  );

  // ── Firebase (music-hub-d7489 project) ───────────────────────────────────
  static const _apiKey        = 'AIzaSyCNsEjYqDhlQcckNY2IsWD2R52AP5fOE_M';
  static const _appId         = '1:668570569113:android:cd085423f982d547bceb08';
  static const _projectId     = 'music-hub-d7489';
  static const _senderId      = '668570569113';
  static const _storageBucket = 'music-hub-d7489.firebasestorage.app';
  static const _authDomain    = 'music-hub-d7489.firebaseapp.com';

  // Android OAuth client (type 1) — from google-services.json oauth_client
  static const googleClientId       = '668570569113-9c1fqjln7ke4r981brh6js9kdp9rjmuc.apps.googleusercontent.com';
  // Web/server OAuth client (type 3) — used as serverClientId for backend token verification
  static const googleServerClientId = '668570569113-itb66bm22jlh693nogqhebiqu20tod8p.apps.googleusercontent.com';

  static FirebaseOptions get firebaseOptions => const FirebaseOptions(
    apiKey:            _apiKey,
    appId:             _appId,
    messagingSenderId: _senderId,
    projectId:         _projectId,
    authDomain:        _authDomain,
    storageBucket:     _storageBucket,
  );
}
