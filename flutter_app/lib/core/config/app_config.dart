import 'package:flutter/foundation.dart';

class AppConfig {
  static const _configuredApi = String.fromEnvironment('API_BASE_URL');
  static const productionApiBaseUrl =
      'https://music-hub-cdn.imeseban.workers.dev';
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static String get apiBaseUrl {
    if (_configuredApi.isNotEmpty) return _configuredApi;
    if (kReleaseMode) return productionApiBaseUrl;
    return kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000';
  }

  // 180ms still absorbs the keystrokes of a fast typist while removing 120ms
  // from the gap between the last key and the first result.
  static const searchDebounce = Duration(milliseconds: 180);

  // Discover fans out to four provider searches per request, so it waits a
  // little longer than the single-purpose lookups above before spending one.
  static const discoverSearchDebounce = Duration(milliseconds: 300);
  static const metadataCacheTtl = Duration(minutes: 5);
}
