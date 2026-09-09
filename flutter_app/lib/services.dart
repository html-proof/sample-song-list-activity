import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'models.dart';
import 'audio_handler.dart';
import 'network_policy.dart';
import 'offline.dart';
import 'cache/audio_cache.dart';
import 'cache/cached_audio_source.dart';
import 'cache/prefetch_manager.dart';
import 'cache/segment_downloader.dart';
import 'search/search_engine.dart';
import 'streaming/adaptive_quality_manager.dart';
import 'streaming/playback_watchdog.dart';
import 'streaming/throughput_estimator.dart';

String formatDuration(Duration value) {
  final totalSeconds = value.inSeconds.clamp(0, 359999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class AuthService extends ChangeNotifier {
  User? _user;
  bool _available = false;
  bool _busy = false;
  String? _error;
  StreamSubscription<User?>? _subscription;
  User? get user => _user;
  bool get available => _available;
  bool get busy => _busy;
  bool get isSignedIn => _user != null;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      // Firebase.initializeApp is already called in main(); just mark available.
      _available = true;
      _user = FirebaseAuth.instance.currentUser;
      _subscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        _user = user;
        notifyListeners();
      });
      // GoogleSignIn.initialize requires a valid OAuth client ID.
      // Skip when not yet configured (empty string) to avoid a crash.
      if (!kIsWeb && AppConfig.googleClientId.isNotEmpty) {
        await GoogleSignIn.instance.initialize(
          clientId: AppConfig.googleClientId,
          serverClientId: AppConfig.googleServerClientId,
        );
      }
    } catch (error) {
      _available = false;
      _error = 'Firebase initialisation failed: $error';
    }
  }

  Future<bool> signInWithGoogle() async {
    if (!_available) {
      _error = 'Add Firebase settings to enable Google sign-in.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (kIsWeb) {
        final credential = await FirebaseAuth.instance.signInWithPopup(
          GoogleAuthProvider(),
        );
        _user = credential.user;
      } else {
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw StateError('Google did not return an ID token.');
        }
        final credential = await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
        _user = credential.user;
      }
      notifyListeners();
      return true;
    } catch (error) {
      _error = 'Google sign-in could not be completed.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String?> idToken({bool forceRefresh = false}) async =>
      await _user?.getIdToken(forceRefresh);
  Future<void> signOut() async {
    if (_available) await FirebaseAuth.instance.signOut();
    if (!kIsWeb) await GoogleSignIn.instance.signOut();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class NotificationService {
  // Attach this key to MaterialApp so showSnackBar works from outside the tree.
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> initialize() async {
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setAutoInitEnabled(true);

    // Show an in-app banner when a notification arrives while the app is open.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // User tapped a notification while the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    // User tapped a notification that launched the app from terminated state.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _onNotificationTap(initial);
  }

  /// Call this once the user is authenticated so the token reaches the backend.
  Future<void> registerWithBackend(MusicApi api) async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await api.registerDevice(token);
      // Keep the token current when FCM rotates it.
      FirebaseMessaging.instance.onTokenRefresh.listen(api.registerDevice);
    } catch (_) {
      // Non-fatal — push notifications are best-effort.
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.title != null)
              Text(
                n.title!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (n.body != null) Text(n.body!),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onNotificationTap(RemoteMessage message) {
    // Route based on payload type when navigation is wired up.
    // e.g. message.data['type'] == 'pulse_like' -> open Pulse tab
  }

  Future<String?> token() async =>
      kIsWeb ? null : FirebaseMessaging.instance.getToken();
}

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Strip common parenthetical/bracketed suffixes so "Song Name (feat. X)"
/// and "Song Name" compare as equal during stream resolution.
String _normalizeTrackTitle(String title) {
  return title
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\(feat\.?[^)]*\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\[feat\.?[^\]]*\]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*ft\.?\s+\S+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(from[^)]*\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\[from[^\]]*\]', caseSensitive: false), '')
      .replaceAll(
          RegExp(
              r'\s*[\(\[]\s*(?:edm version|version|reprise|remix|remaster|remastered|acoustic|live|radio edit|extended|instrumental|soundtrack|ost|original motion picture soundtrack)[^\)\]]*[\)\]]',
              caseSensitive: false),
          '')
      .replaceAll(
          RegExp(
              r'\s*[-–]\s*(reprise|remix|remaster|remastered|acoustic|live|radio edit|extended|instrumental|edm version).*$',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Pick the best title match from [candidates] for [targetTitle].
/// Tries exact → normalized → prefix/contains → word overlap → single candidate in that order.
Track? _findBestTitleMatch(List<Track> candidates, String targetTitle) {
  if (candidates.isEmpty || targetTitle.isEmpty) return null;
  final exact = targetTitle.toLowerCase().trim();
  final norm = _normalizeTrackTitle(targetTitle);

  // 1. Exact case-insensitive title match
  for (final t in candidates) {
    if (t.title.toLowerCase().trim() == exact) return t;
  }
  // 2. Normalized title match (strips feat., remix, version suffixes, etc.)
  if (norm.isNotEmpty) {
    for (final t in candidates) {
      if (_normalizeTrackTitle(t.title) == norm) return t;
    }
  }
  // 3. Normalized prefix or contains match
  if (norm.isNotEmpty) {
    for (final t in candidates) {
      final tn = _normalizeTrackTitle(t.title);
      if (tn.isNotEmpty &&
          (norm.startsWith(tn) ||
              tn.startsWith(norm) ||
              norm.contains(tn) ||
              tn.contains(norm))) {
        return t;
      }
    }
  }
  // 4. One raw title starts with the other
  for (final t in candidates) {
    final tl = t.title.toLowerCase().trim();
    if (tl.startsWith(exact) || exact.startsWith(tl)) return t;
  }
  // 5. Word / keyword overlap (>= 50% overlap of significant words)
  if (norm.isNotEmpty) {
    final targetWords = norm.split(' ').where((w) => w.length > 2).toSet();
    if (targetWords.isNotEmpty) {
      Track? bestOverlapTrack;
      double bestOverlapRatio = 0.0;
      for (final t in candidates) {
        final tn = _normalizeTrackTitle(t.title);
        final candWords = tn.split(' ').where((w) => w.length > 2).toSet();
        final common = targetWords.intersection(candWords);
        final ratio = common.length / targetWords.length;
        if (ratio >= 0.5 && ratio > bestOverlapRatio) {
          bestOverlapRatio = ratio;
          bestOverlapTrack = t;
        }
      }
      if (bestOverlapTrack != null) return bestOverlapTrack;
    }
  }
  // 6. Fallback: single candidate with playable stream
  if (candidates.length == 1) return candidates.first;
  return null;
}

class MusicApi {
  MusicApi(this.auth, {http.Client? client, this.policy, this.connection})
    : _customClient = client,
      _client = client ?? http.Client() {
    connection?.addListener(_onNetworkChanged);
  }

  final AuthService auth;
  final http.Client? _customClient;
  http.Client _client;
  final DataUsagePolicy? policy;
  final ConnectionMonitor? connection;
  final _inFlight = <String, Future<dynamic>>{};
  final _etags = <String, String>{};
  final _memoryCache = <String, dynamic>{};
  SharedPreferences? _local;
  Future<Map<String, dynamic>>? _accountExchange;

  http.Client get client => _client;

  void resetClient() {
    if (_customClient != null) return;
    try {
      _client.close();
    } catch (_) {}
    _client = http.Client();
  }

  void _onNetworkChanged() {
    if (_customClient == null && connection?.state.connected == true) {
      resetClient();
    }
  }

  Future<Map<String, dynamic>> ensureAccount() {
    if (_accountExchange != null) return _accountExchange!;
    final request = _ensureAccountUncached();
    _accountExchange = request;
    return request.whenComplete(() => _accountExchange = null);
  }

  Future<Map<String, dynamic>> _ensureAccountUncached() async => _data(
    await _request('/api/v1/auth/google', method: 'POST', authenticated: true),
  );

  Map<String, dynamic> _data(dynamic response) {
    if (response is! Map) return <String, dynamic>{};
    final map = Map<String, dynamic>.from(response);
    final data = map['data'];
    return data is Map ? Map<String, dynamic>.from(data) : map;
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    Object? body,
    bool authenticated = false,
  }) async {
    final cacheable = method == 'GET';
    final cacheKey =
        '$method|$path|${query ?? const <String, dynamic>{}}|$authenticated';
    if (cacheable && _inFlight.containsKey(cacheKey)) {
      return _inFlight[cacheKey]!;
    }
    if (cacheable && _memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey];
      unawaited(
        _refresh(
          cacheKey,
          path,
          method: method,
          query: query,
          authenticated: authenticated,
        ),
      );
      return cached;
    }
    final request = _requestUncached(
      cacheKey,
      path,
      method: method,
      query: query,
      body: body,
      authenticated: authenticated,
    );
    if (!cacheable) return request;
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<dynamic> _refresh(
    String cacheKey,
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) async {
    try {
      await _requestUncached(
        cacheKey,
        path,
        method: method,
        query: query,
        authenticated: authenticated,
      );
    } catch (_) {}
  }

  Future<dynamic> _requestUncached(
    String cacheKey,
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    Object? body,
    bool authenticated = false,
  }) async {
    final cacheable = method == 'GET';
    _local ??= await SharedPreferences.getInstance();
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final uri = base.replace(
      path: '${base.path}${path.startsWith('/') ? path : '/$path'}',
      queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    String? token;
    if (authenticated) {
      token = await auth.idToken();
      if (token == null) {
        throw const ApiException('Sign in to use this feature.', 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }
    final etag = _etags[cacheKey] ?? _local!.getString('etag_$cacheKey');
    if (etag != null) headers['If-None-Match'] = etag;
    late http.Response response;
    var attempt = 0;
    const maxAttempts = 3;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        Future<http.Response> send() => switch (method) {
          'POST' => _client.post(uri, headers: headers, body: jsonEncode(body)),
          'PATCH' => _client.patch(uri, headers: headers, body: jsonEncode(body)),
          'PUT' => _client.put(uri, headers: headers, body: jsonEncode(body)),
          'DELETE' => _client.delete(uri, headers: headers),
          _ => _client.get(uri, headers: headers),
        };

        response = await send().timeout(const Duration(seconds: 15));

        // Firebase ID tokens expire and can also be revoked server-side. Refresh
        // once before surfacing a 401 so startup/resume requests recover without
        // forcing the user to sign in again.
        if (authenticated && response.statusCode == 401 && attempt == 1) {
          String? refreshed;
          try {
            refreshed = await auth.idToken(forceRefresh: true);
          } catch (_) {
            // Keep the original API response if Firebase cannot refresh locally.
          }
          if (refreshed != null && refreshed != token) {
            headers['Authorization'] = 'Bearer $refreshed';
            response = await send().timeout(const Duration(seconds: 15));
          }
        }
        break;
      } catch (error) {
        if (attempt >= maxAttempts) {
          if (error is TimeoutException) {
            throw const ApiException(
              'The request timed out. Showing saved content where available.',
            );
          }
          rethrow;
        }

        // On network error / interface change (e.g. WiFi -> Mobile data),
        // wait for connection to settle and reset client before retrying
        if (connection != null && !connection!.state.connected) {
          await connection!.waitForConnection(timeout: const Duration(seconds: 2));
        }
        resetClient();
        final delay = Duration(milliseconds: 300 * attempt);
        await Future.delayed(delay);
      }
    }

    if (response.statusCode == 304 && _memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map
          ? decoded['detail'] ?? decoded['error']
          : null;
      throw ApiException(
        detail is String ? detail : 'Request failed (${response.statusCode}).',
        response.statusCode,
      );
    }
    if (cacheable) {
      _memoryCache[cacheKey] = decoded;
      final responseTag = response.headers['etag'];
      if (responseTag != null) {
        _etags[cacheKey] = responseTag;
        await _local!.setString('etag_$cacheKey', responseTag);
      }
      if (path == '/api/home' && decoded != null) {
        await _local!.setString('cached_home', jsonEncode(decoded));
      }
    }
    return decoded;
  }

  Future<Map<String, dynamic>?> cachedHome() async {
    _local ??= await SharedPreferences.getInstance();
    final raw = _local!.getString('cached_home');
    if (raw == null) return null;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final data = decoded['data'];
      return data is Map ? Map<String, dynamic>.from(data) : decoded;
    } catch (_) {
      return null;
    }
  }

  Future<List<Track>> trending({
    required String language,
    int limit = 12,
  }) async => Track.list(
    await _request('/trending', query: {'language': language, 'limit': limit}),
  );
  Future<List<Track>> searchTracks(String query, {int limit = 20}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    // 1. Try modern /api/search with type=song
    try {
      final response = await _request(
        '/api/search',
        query: {'q': cleanQuery, 'type': 'song', 'limit': limit},
      );
      if (response is List) {
        final list = Track.list(response);
        if (list.isNotEmpty) return list;
      } else {
        final data = _data(response);
        final rawList = (data['items'] ?? data['songs'] ?? data['tracks']);
        if (rawList is List) {
          final list = Track.list(rawList);
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}

    // 2. Fallback to /songs/search/ with sanitized query
    final sanitizedQuery = cleanQuery
        .replaceAll(RegExp(r"[^a-zA-Z0-9\s\-'.&]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fallbackQuery =
        sanitizedQuery.isNotEmpty ? sanitizedQuery : cleanQuery;
    return Track.list(
      await _request(
        '/songs/search/',
        query: {'query': fallbackQuery, 'limit': limit},
      ),
    );
  }
  final _lyricsCache = <String, Lyrics>{};

  Future<Lyrics> lyrics(String trackId, {String? title, String? artist}) async {
    final key = trackId.trim();
    if (_lyricsCache.containsKey(key)) {
      final cached = _lyricsCache[key]!;
      if (cached.status != 'not_found' || (title == null && artist == null)) {
        return cached;
      }
    }
    final query = <String, dynamic>{};
    if (title != null && title.trim().isNotEmpty) query['title'] = title.trim();
    if (artist != null && artist.trim().isNotEmpty) query['artist'] = artist.trim();
    try {
      final res = await _request(
        '/api/v1/tracks/$trackId/lyrics',
        query: query.isNotEmpty ? query : null,
      );
      final lyricsObj = Lyrics.fromJson(Map<String, dynamic>.from(res as Map));
      _lyricsCache[key] = lyricsObj;
      return lyricsObj;
    } catch (_) {
      if (_lyricsCache.containsKey(key)) return _lyricsCache[key]!;
      rethrow;
    }
  }

  void preloadLyrics(String trackId, {String? title, String? artist}) {
    final key = trackId.trim();
    if (key.isEmpty || (_lyricsCache.containsKey(key) && _lyricsCache[key]!.status != 'not_found')) {
      return;
    }
    unawaited(lyrics(key, title: title, artist: artist).catchError((_) => const Lyrics.empty()));
  }

  Future<List<Album>> searchAlbums(String query, {int limit = 12}) async =>
      Album.list(
        await _request(
          '/albums/search/',
          query: {'query': query, 'limit': limit},
        ),
      );
  Future<List<Artist>> searchArtists(String query, {int limit = 12}) async =>
      (await _request(
            '/artists/search/',
            query: {'query': query, 'limit': limit},
          ) as List)
          .whereType<Map>()
          .map((item) => Artist.fromJson(Map<String, dynamic>.from(item)))
          .toList();

  Future<Map<String, dynamic>> artistDetails(String artistId, {int limit = 20}) async {
    final cleanId = artistId.trim();
    if (cleanId.isEmpty) return const <String, dynamic>{};
    try {
      final encoded = Uri.encodeComponent(cleanId);
      final data = _data(await _request('/api/artists/$encoded', query: {'limit': limit}));
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('Artist details failed for $artistId: $e');
      return const <String, dynamic>{};
    }
  }

  Future<Album> albumDetails(String albumId) async {
    final cleanId = albumId.trim();
    final encoded = Uri.encodeComponent(cleanId);
    try {
      final data = _data(await _request('/api/albums/$encoded'));
      return Album.fromJson(data);
    } on ApiException catch (error) {
      debugPrint('Album API failed: statusCode=${error.statusCode} albumId=$albumId');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> albumRecommendations(String albumId) async {
    try {
      final data = _data(await _request('/api/albums/$albumId/recommendations'));
      final rawRecs = data['recommendations'] as List? ?? const [];
      final rawMoreBy = data['moreByArtist'] as List? ?? const [];
      final rawYouMightLike = data['youMightAlsoLike'] as List? ?? const [];

      return {
        'albumId': '${data['albumId'] ?? albumId}',
        'primaryArtist': '${data['primaryArtist'] ?? ''}',
        'recommendations': rawRecs
            .whereType<Map>()
            .map((item) => AlbumRecommendation.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        'moreByArtist': rawMoreBy
            .whereType<Map>()
            .map((item) => AlbumRecommendation.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
        'youMightAlsoLike': rawYouMightLike
            .whereType<Map>()
            .map((item) => AlbumRecommendation.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      };
    } catch (e) {
      debugPrint('Album recommendations failed for $albumId: $e');
      return {
        'albumId': albumId,
        'primaryArtist': '',
        'recommendations': <AlbumRecommendation>[],
        'moreByArtist': <AlbumRecommendation>[],
        'youMightAlsoLike': <AlbumRecommendation>[],
      };
    }
  }

  Future<List<CollectionItem>> charts({int limit = 12}) async =>
      (await _request('/charts', query: {'limit': limit}) as List)
          .whereType<Map>()
          .map(
            (item) => CollectionItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
  Future<List<Track>> playlist(String seokey) async =>
      Track.list(await _request('/playlists/info/', query: {'seokey': seokey}));
  Future<Map<String, dynamic>> profile() async => Map<String, dynamic>.from(
    await _request('/me/profile', authenticated: true) as Map,
  );
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(
        await _request(
          '/me/profile',
          method: 'PATCH',
          body: data,
          authenticated: true,
        ) as Map,
      );
  Future<List<Track>> favorites() async {
    if (!auth.isSignedIn) return [];
    try {
      return Track.list(await _request('/me/favorites', authenticated: true));
    } catch (_) {
      return [];
    }
  }

  Future<List<Track>> history({int limit = 20}) async {
    if (!auth.isSignedIn) return [];
    try {
      return Track.list(
        await _request(
          '/me/history',
          query: {'limit': limit},
          authenticated: true,
        ),
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<Track>> recommendations({
    int limit = 20,
    int refreshGeneration = 0,
    String? sessionId,
    List<String>? excludeIds,
    int cursor = 0,
  }) async {
    if (!auth.isSignedIn) {
      try {
        List<Track> candidateTracks = await trending(
          language: 'hindi',
          limit: limit + (excludeIds?.length ?? 0) + cursor + 10,
        );
        if (candidateTracks.isEmpty) {
          candidateTracks = await trending(
            language: 'english',
            limit: limit + (excludeIds?.length ?? 0) + cursor + 10,
          );
        }
        final excludeSet = excludeIds?.toSet() ?? const <String>{};
        final filtered = candidateTracks
            .where((t) => !excludeSet.contains(t.id) && !excludeSet.contains(t.seokey))
            .toList();
        if (cursor < filtered.length) {
          return filtered.skip(cursor).take(limit).toList();
        }
        return filtered.take(limit).toList();
      } catch (_) {
        return [];
      }
    }
    try {
      return Track.list(
        await _request(
          '/me/recommendations',
          query: {
            'limit': limit,
            if (refreshGeneration > 0) 'refresh_generation': refreshGeneration,
            if (sessionId != null && sessionId.isNotEmpty)
              'session_id': sessionId,
            if (excludeIds != null && excludeIds.isNotEmpty)
              'exclude_ids': excludeIds.take(100).join(','),
            if (cursor > 0) 'cursor': cursor,
          },
          authenticated: true,
        ),
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> addFavorite(Track track) async {
    if (!auth.isSignedIn) return;
    try {
      await _request(
        '/me/favorites',
        method: 'POST',
        body: track.toPersonalizationJson(),
        authenticated: true,
      );
    } catch (_) {}
  }

  Future<void> removeFavorite(String seokey) async {
    if (!auth.isSignedIn) return;
    try {
      await _request(
        '/me/favorites/$seokey',
        method: 'DELETE',
        authenticated: true,
      );
    } catch (_) {}
  }

  Future<void> addHistory(Track track) async {
    if (!auth.isSignedIn) return;
    try {
      await _request(
        '/me/history',
        method: 'POST',
        body: {...track.toPersonalizationJson(), 'source': 'flutter-player'},
        authenticated: true,
      );
    } catch (_) {}
  }

  Future<void> deleteAccount() async =>
      _request('/me/account', method: 'DELETE', authenticated: true);

  Future<List<Map<String, dynamic>>> userPlaylists() async {
    if (!auth.isSignedIn) return [];
    try {
      final res = await _request('/me/playlists', authenticated: true);
      if (res is! List) return [];
      return res
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createPlaylist(String name) async =>
      Map<String, dynamic>.from(
        await _request(
          '/me/playlists',
          method: 'POST',
          body: {'name': name},
          authenticated: true,
        ) as Map,
      );

  Future<void> registerDevice(String fcmToken) async => _request(
    '/me/devices',
    method: 'POST',
    body: {
      'token': fcmToken,
      'platform': defaultTargetPlatform.name.toLowerCase(),
    },
    authenticated: true,
  );

  Future<List<Map<String, dynamic>>> languages() async {
    final data = _data(await _request('/api/languages'));
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Artist>> onboardingArtists(List<String> languageIds) async {
    final data = await onboardingArtistPage(languageIds);
    return data['items'] as List<Artist>? ?? const [];
  }

  Future<Map<String, dynamic>> onboardingArtistPage(
    List<String> languageIds, {
    String? cursor,
    int limit = 40,
  }) async {
    final data = _data(
      await _request(
        '/api/artists',
        query: {
          'languages': languageIds.join(','),
          'limit': limit,
          'cursor': ?cursor,
        },
      ),
    );
    final artists = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Artist.fromJson(Map<String, dynamic>.from(item)))
        .where((artist) => artist.seokey.isNotEmpty && artist.name.isNotEmpty)
        .toList();
    return {
      'items': artists,
      'next_cursor': data['next_cursor'],
      'has_more': data['has_more'] == true,
    };
  }

  Future<Map<String, dynamic>> saveLanguageIds(List<String> ids) async {
    await ensureAccount();
    return _data(
      await _request(
        '/api/me/preferences/languages',
        method: 'PUT',
        body: {'language_ids': ids},
        authenticated: true,
      ),
    );
  }

  Future<Map<String, dynamic>> saveArtistIds(List<String> ids) async {
    await ensureAccount();
    return _data(
      await _request(
        '/api/me/preferences/artists',
        method: 'PUT',
        body: {'artist_ids': ids},
        authenticated: true,
      ),
    );
  }

  Future<Map<String, dynamic>> me() async =>
      _data(await _request('/api/me', authenticated: true));

  Future<Map<String, dynamic>> home({
    bool refresh = false,
    int refreshGeneration = 0,
    String? sessionId,
    List<String>? excludeIds,
    int cursor = 0,
    int limit = 24,
  }) async => _data(
    await _request(
      '/api/home',
      query: {
        'refresh': refresh,
        if (refreshGeneration > 0) 'refresh_generation': refreshGeneration,
        if (sessionId != null && sessionId.isNotEmpty)
          'session_id': sessionId,
        if (excludeIds != null && excludeIds.isNotEmpty)
          'exclude_ids': excludeIds.take(100).join(','),
        if (cursor > 0) 'cursor': cursor,
        'limit': limit,
      },
      authenticated: true,
    ),
  );

  final Map<String, (DateTime, Map<String, dynamic>)> _searchCache = {};
  final Map<String, (DateTime, List<dynamic>)> _typedSearchCache = {};

  Future<Map<String, dynamic>> categorizedSearch(String query) async {
    final cleanQ = query.trim().toLowerCase();
    final cached = _searchCache[cleanQ];
    if (cached != null && DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      final cachedData = cached.$2;
      final hasItems = (cachedData['songs'] is List && (cachedData['songs'] as List).isNotEmpty) ||
          (cachedData['artists'] is List && (cachedData['artists'] as List).isNotEmpty) ||
          (cachedData['albums'] is List && (cachedData['albums'] as List).isNotEmpty) ||
          (cachedData['playlists'] is List && (cachedData['playlists'] as List).isNotEmpty);
      if (hasItems) {
        return cachedData;
      }
    }

    Map<String, dynamic> result = <String, dynamic>{};
    try {
      final response = await _request(
        '/api/search',
        query: {'q': query, 'limit': 50},
      );

      if (response is List) {
        result = <String, dynamic>{'songs': response};
      } else {
        final data = _data(response);
        if (data['items'] is List &&
            data['songs'] == null &&
            data['artists'] == null &&
            data['albums'] == null &&
            data['playlists'] == null) {
          result = <String, dynamic>{'songs': data['items']};
        } else if (data['tracks'] is List && data['songs'] == null) {
          result = <String, dynamic>{'songs': data['tracks']};
        } else {
          result = data;
        }
      }
    } catch (_) {}

    // Resilient fallback: If /api/search returned empty results, query songs, albums, and artists endpoints directly
    final songsList = result['songs'] as List? ?? const [];
    final albumsList = result['albums'] as List? ?? const [];
    final artistsList = result['artists'] as List? ?? const [];
    if (songsList.isEmpty && albumsList.isEmpty && artistsList.isEmpty) {
      try {
        final fallbackResults = await Future.wait([
          searchTracks(query, limit: 30).catchError((_) => <Track>[]),
          searchAlbums(query, limit: 20).catchError((_) => <Album>[]),
          searchArtists(query, limit: 15).catchError((_) => <Artist>[]),
        ]);
        final fallbackSongs = (fallbackResults[0] as List<Track>).map((t) => t.toJson()).toList();
        final fallbackAlbums = (fallbackResults[1] as List<Album>).map((a) => a.toJson()).toList();
        final fallbackArtists = (fallbackResults[2] as List<Artist>).map((a) => a.toJson()).toList();

        if (fallbackSongs.isNotEmpty || fallbackAlbums.isNotEmpty || fallbackArtists.isNotEmpty) {
          result = <String, dynamic>{
            'songs': fallbackSongs,
            'albums': fallbackAlbums,
            'artists': fallbackArtists,
            'playlists': const [],
          };
        }
      } catch (_) {}
    }

    final hasContent = (result['songs'] is List && (result['songs'] as List).isNotEmpty) ||
        (result['artists'] is List && (result['artists'] as List).isNotEmpty) ||
        (result['albums'] is List && (result['albums'] as List).isNotEmpty);
    if (hasContent) {
      final parsedTracks = Track.list(result['songs']);
      final parsedAlbums = (result['albums'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Album.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final parsedArtists = (result['artists'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Artist.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final parsedPlaylists = (result['playlists'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      LocalSearchEngine.instance.indexTracks(parsedTracks);
      LocalSearchEngine.instance.indexAlbums(parsedAlbums);
      LocalSearchEngine.instance.indexArtists(parsedArtists);
      LocalSearchEngine.instance.indexPlaylists(parsedPlaylists);

      _searchCache[cleanQ] = (DateTime.now(), result);
      if (_searchCache.length > 100) {
        _searchCache.remove(_searchCache.keys.first);
      }
    }
    return result;
  }

  Future<List<dynamic>> typedSearch(
    String query,
    String type, {
    int page = 1,
  }) async {
    final cleanKey = '$query:$type:$page'.trim().toLowerCase();
    final cached = _typedSearchCache[cleanKey];
    if (cached != null &&
        cached.$2.isNotEmpty &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      return cached.$2;
    }

    final apiType = type == 'songs'
        ? 'song'
        : type == 'artists'
        ? 'artist'
        : type == 'albums'
        ? 'album'
        : 'playlist';
    List<dynamic> result = [];
    try {
      final response = await _request(
        '/api/search',
        query: {'q': query, 'type': apiType, 'limit': 50, 'page': page},
      );
      if (response is List) {
        result = response;
      } else {
        final data = _data(response);
        if (data['items'] is List) {
          result = data['items'] as List<dynamic>;
        } else if (data['songs'] is List) {
          result = data['songs'] as List<dynamic>;
        } else if (data['tracks'] is List) {
          result = data['tracks'] as List<dynamic>;
        } else if (data['artists'] is List) {
          result = data['artists'] as List<dynamic>;
        } else if (data['albums'] is List) {
          result = data['albums'] as List<dynamic>;
        } else if (data['playlists'] is List) {
          result = data['playlists'] as List<dynamic>;
        }
      }
    } catch (_) {}

    if (result.isEmpty) {
      try {
        if (type == 'songs') {
          final fallback = await searchTracks(query, limit: 30);
          result = fallback.map((t) => t.toJson()).toList();
        } else if (type == 'albums') {
          final fallback = await searchAlbums(query, limit: 20);
          result = fallback.map((a) => a.toJson()).toList();
        } else if (type == 'artists') {
          final fallback = await searchArtists(query, limit: 20);
          result = fallback.map((a) => a.toJson()).toList();
        }
      } catch (_) {}
    }

    if (result.isNotEmpty) {
      _typedSearchCache[cleanKey] = (DateTime.now(), result);
      if (_typedSearchCache.length > 100) {
        _typedSearchCache.remove(_typedSearchCache.keys.first);
      }
    }
    return result;
  }

  static bool isStreamExpired(String url) {
    if (url.isEmpty) return true;
    final match = RegExp(r'exp=(\d+)').firstMatch(url);
    if (match == null) return false;
    final expSec = int.tryParse(match.group(1) ?? '');
    if (expSec == null) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expSec <= (nowSec + 60);
  }

  /// Resolve the exact catalog record before playback when the selected
  /// result has no stream or an expired token.
  Future<Track?> resolvePlayableTrack(
    Track track, {
    bool forceFresh = false,
  }) async {
    final expired = isStreamExpired(track.streamUrl);
    if (!forceFresh && track.streamUrl.isNotEmpty && !expired) return track;

    if (connection != null && !connection!.state.connected) {
      await connection!.waitForConnection(timeout: const Duration(seconds: 2));
    }

    final candidates = [
      track.seokey.trim(),
      track.trackId.trim(),
      track.id.trim(),
    ].where((k) => k.isNotEmpty).toSet();

    for (final key in candidates) {
      try {
        final exact = await trackInfo(
          key,
          refresh: forceFresh || expired,
        );
        if (exact != null && exact.streamUrl.isNotEmpty) {
          final targetQuality = policy?.qualityFor(connection?.state ?? const NetworkState()) ?? 'automatic';
          final preferredUrl = exact.getStreamUrlForQuality(targetQuality);
          return track.copyWith(
            seokey: exact.seokey.isNotEmpty ? exact.seokey : track.seokey,
            trackId: exact.trackId.isNotEmpty ? exact.trackId : track.trackId,
            streamUrl: preferredUrl.isNotEmpty ? preferredUrl : exact.streamUrl,
            streamUrls: exact.streamUrls.isNotEmpty ? exact.streamUrls : track.streamUrls,
            durationSeconds: exact.durationSeconds > 0
                ? exact.durationSeconds
                : track.durationSeconds,
            imageUrl: track.imageUrl.isNotEmpty ? track.imageUrl : exact.imageUrl,
            artist: track.artist.isNotEmpty ? track.artist : exact.artist,
            album: track.album.isNotEmpty ? track.album : exact.album,
            title: track.title.isNotEmpty ? track.title : exact.title,
          );
        }
      } catch (_) {}
    }

    // Secondary fallback: search by title (and optionally artist+title) with
    // tiered matching — exact → normalized (strips feat./remix suffixes) → prefix.
    if (track.title.isNotEmpty) {
      final coreTitle = _normalizeTrackTitle(track.title);
      final rawCoreTitle = track.title
          .replaceAll(RegExp(r'\s*\[[^\]]*\]', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*\([^)]*\)', caseSensitive: false), '')
          .trim();
      final searchQueries = [
        track.title,
        if (rawCoreTitle.isNotEmpty &&
            rawCoreTitle.toLowerCase() != track.title.toLowerCase())
          rawCoreTitle,
        if (coreTitle.isNotEmpty &&
            coreTitle != track.title.toLowerCase() &&
            coreTitle != rawCoreTitle.toLowerCase())
          coreTitle,
        if (track.artist.isNotEmpty) '${track.title} ${track.artist}',
        if (track.artist.isNotEmpty && rawCoreTitle.isNotEmpty)
          '$rawCoreTitle ${track.artist}',
      ];
      for (final searchQuery in searchQueries) {
        try {
          final searchResults = await searchTracks(searchQuery, limit: 12);
          final withStream = searchResults.where((t) => t.streamUrl.isNotEmpty).toList();
          final match = _findBestTitleMatch(withStream, track.title);
          if (match != null) {
            final targetQuality = policy?.qualityFor(connection?.state ?? const NetworkState()) ?? 'automatic';
            final preferredUrl = match.getStreamUrlForQuality(targetQuality);
            return track.copyWith(
              streamUrl: preferredUrl.isNotEmpty ? preferredUrl : match.streamUrl,
              streamUrls: match.streamUrls.isNotEmpty ? match.streamUrls : track.streamUrls,
              seokey: match.seokey.isNotEmpty ? match.seokey : track.seokey,
              trackId: match.trackId.isNotEmpty ? match.trackId : track.trackId,
              durationSeconds: match.durationSeconds > 0
                  ? match.durationSeconds
                  : track.durationSeconds,
            );
          }
        } catch (_) {}
      }
    }

    return track.streamUrl.isNotEmpty ? track : null;
  }

  /// Fetch one song by its provider seokey or track ID. This is deliberately separate
  /// from search so playback cannot rematch a selected result by title.
  Future<Track?> trackInfo(String seokey, {bool refresh = false}) async {
    final trimmed = seokey.trim();
    if (trimmed.isEmpty) return null;
    try {
      final value = await _request(
        '/songs/info/',
        query: {'seokey': trimmed, 'refresh': refresh},
      );
      final tracks = Track.list(value);
      if (tracks.isEmpty) return null;
      return tracks.firstWhere(
        (item) =>
            item.seokey.toLowerCase() == trimmed.toLowerCase() ||
            item.id.toLowerCase() == trimmed.toLowerCase() ||
            item.trackId == trimmed,
        orElse: () => tracks.first,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> recentSearches() async {
    if (!auth.isSignedIn) return [];
    final data = _data(
      await _request('/api/me/recent-searches', authenticated: true),
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> saveRecentSearch(
    String query, {
    String? type,
    String? itemId,
  }) async {
    if (!auth.isSignedIn) return;
    await _request(
      '/api/me/recent-searches',
      method: 'POST',
      authenticated: true,
      body: {'query': query, 'type': type, 'item_id': itemId},
    );
  }

  Future<void> deleteRecentSearch(String searchId) async {
    if (!auth.isSignedIn) return;
    await _request(
      '/api/me/recent-searches/$searchId',
      method: 'DELETE',
      authenticated: true,
    );
  }

  Future<void> clearRecentSearches() async {
    if (!auth.isSignedIn) return;
    await _request(
      '/api/me/recent-searches',
      method: 'DELETE',
      authenticated: true,
    );
  }

  Future<List<Map<String, dynamic>>> searchDiscovery() async {
    final data = _data(await _request('/api/search/discover'));
    return (data['sections'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class PlayerController extends ChangeNotifier {
  MusicAudioHandler? _handler;
  AudioPlayer get _audio => _handler?.player ?? _fallback;
  final AudioPlayer _fallback = AudioPlayer();
  Track? current;
  List<Track> queue = [];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  String? error;
  bool autoplayEnabled = true;
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off;
  bool isShuffled = false;
  int currentIndex = 0;
  bool _isTransitioning = false;
  Future<List<Track>> Function(Track track)? loadRelatedTracks;
  List<Track> _originalQueue = [];
  List<Track> get originalQueue => List.unmodifiable(_originalQueue);
  final List<Track> _playbackHistory = [];
  List<Track> get playbackHistory => List.unmodifiable(_playbackHistory);

  bool isCurrentTrack(Track track) =>
      current != null && _isSameTrack(current!, track);

  bool _isSameTrack(Track a, Track b) {
    if (identical(a, b)) return true;
    if (a.id.isNotEmpty && b.id.isNotEmpty && a.id == b.id) return true;
    if (a.seokey.isNotEmpty && b.seokey.isNotEmpty && a.seokey == b.seokey) return true;
    if (a.trackId.isNotEmpty && b.trackId.isNotEmpty && a.trackId == b.trackId) return true;
    if (a.id.isNotEmpty && b.seokey.isNotEmpty && a.id == b.seokey) return true;
    if (a.seokey.isNotEmpty && b.id.isNotEmpty && a.seokey == b.id) return true;
    if (a.title.isNotEmpty &&
        b.title.isNotEmpty &&
        a.title.toLowerCase().trim() == b.title.toLowerCase().trim() &&
        a.artist.toLowerCase().trim() == b.artist.toLowerCase().trim()) {
      return true;
    }
    return false;
  }

  void _addToHistory(Track track) {
    if (_playbackHistory.isEmpty || !_isSameTrack(_playbackHistory.last, track)) {
      _playbackHistory.add(track);
      if (_playbackHistory.length > 50) {
        _playbackHistory.removeAt(0);
      }
    }
  }

  final DataUsagePolicy? policy;
  final ConnectionMonitor? connection;
  final DownloadManager? downloads;
  final AudioCache? audioCache;
  final QueuePrefetchManager? prefetchManager;
  String authUserId = 'guest';
  Timer? _sleepTimer;
  Timer? _saveThrottleTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  Future<void> _playOperation = Future<void>.value();
  Future<void>? _backgroundAudioInitialization;
  Future<Track?> Function(Track track, {bool forceFresh})? resolveTrack;
  int _playbackSession = 0;
  bool _disposed = false;
  int get playbackSessionId => _playbackSession;
  bool get isReady => duration > Duration.zero && current != null;

  late final AdaptiveQualityManager qualityManager;
  late final PlaybackWatchdog watchdog;
  StreamSubscription<String>? _qualitySubscription;
  CachedStreamAudioSource? _activeCachedSource;
  bool _hasPrefetchedNextForCurrent = false;

  /// Authoritative session tracking the active track's locked quality and data consumption.
  PlaybackSession? currentSession;

  /// Quality changes (manual or network-triggered) are stored here and applied
  /// strictly to the NEXT song, never altering the currently playing track.
  String? pendingQuality;

  PlayerController({
    this.policy,
    this.connection,
    this.downloads,
    this.audioCache,
    this.prefetchManager,
  }) {
    qualityManager = AdaptiveQualityManager(
      estimator: ThroughputEstimator.instance,
      connection: connection,
      policy: policy,
    );
    watchdog = PlaybackWatchdog(
      onStallDetected: _onPlaybackStallDetected,
    );
    _qualitySubscription = qualityManager.onQualityChanged.listen(_onAdaptiveQualityChanged);
    _bindAudio(_audio, _playbackSession);
    connection?.addListener(_onNetworkChanged);
    policy?.addListener(_onPolicyChanged);
  }

  static bool isHlsStream(String url) {
    if (url.isEmpty) return false;
    final clean = url.toLowerCase().split('?').first;
    return clean.endsWith('.m3u8') || clean.contains('/hls/') || clean.contains('.m3u8');
  }

  void _onAdaptiveQualityChanged(String newQuality) {
    // Once a song starts playing, its quality must remain locked and never change mid-track.
    // Quality adjustments will apply when transitioning to the next track.
    pendingQuality = (currentSession != null && newQuality == currentSession!.lockedQuality) ? null : newQuality;
  }

  Future<void> _onPlaybackStallDetected([Duration? stallPosition]) async {
    if (_disposed || !playing || current == null) return;
    final targetPos = stallPosition ?? position;
    debugPrint('Watchdog: playback stall detected for "${current?.title}" at $targetPos. Initiating silent recovery.');
    qualityManager.recordStall();
    currentSession?.retryCount = (currentSession?.retryCount ?? 0) + 1;

    final track = current!;
    final localPath = downloads?.localPathForTrack(track) ??
        downloads?.localPath(track.id) ??
        downloads?.localPath(track.seokey);
    if (localPath != null) {
      try {
        await seek(targetPos);
        await playResume();
      } catch (_) {}
      return;
    }

    try {
      Track freshTrack = track;
      if (resolveTrack != null && (freshTrack.streamUrl.isEmpty || MusicApi.isStreamExpired(freshTrack.streamUrl))) {
        final resolved = await resolveTrack!(freshTrack, forceFresh: true);
        if (resolved != null && resolved.streamUrl.isNotEmpty) {
          freshTrack = resolved;
        }
      }

      // Maintain the playing track's established locked stream URL so quality does NOT change
      final lockedQuality = currentSession?.lockedQuality ?? qualityManager.currentQuality;
      final activeUrl = (currentSession?.streamUrl.isNotEmpty == true)
          ? currentSession!.streamUrl
          : (freshTrack.streamUrl.isNotEmpty
              ? freshTrack.streamUrl
              : freshTrack.getStreamUrlForQuality(lockedQuality));
      if (activeUrl.isEmpty) return;

      freshTrack = freshTrack.copyWith(streamUrl: activeUrl);
      current = freshTrack;

      final currentQ = lockedQuality;

      AudioSource newSource;
      final isHls = isHlsStream(activeUrl);
      if (audioCache != null && !isHls) {
        final cacheKey = AudioCache.generateKey(
          userId: authUserId,
          songId: freshTrack.id.isNotEmpty ? freshTrack.id : freshTrack.seokey,
          audioQuality: currentQ,
        );
        audioCache!.protect(cacheKey);
        _activeCachedSource?.cancel();
        final cachedSource = CachedStreamAudioSource(
          audioCache: audioCache!,
          downloader: prefetchManager?.downloader ?? SegmentDownloader(),
          uri: Uri.parse(activeUrl),
          cacheKey: cacheKey,
          songId: freshTrack.id.isNotEmpty ? freshTrack.id : freshTrack.seokey,
          userId: authUserId,
          audioQuality: currentQ,
          tag: _handler?.toMediaItem(freshTrack),
          onNetworkDownloaded: (bytes) {
            currentSession?.networkBytesDownloaded += bytes;
          },
          onCacheRead: (bytes) {
            currentSession?.cacheBytesRead += bytes;
          },
          onDuplicatePrevented: () {
            currentSession?.duplicateRequestPrevented = true;
          },
        );
        _activeCachedSource = cachedSource;
        newSource = cachedSource;
      } else {
        _activeCachedSource?.cancel();
        _activeCachedSource = null;
        newSource = AudioSource.uri(
          Uri.parse(activeUrl),
          tag: _handler?.toMediaItem(freshTrack),
        );
      }

      if (_handler != null) {
        await _handler!.switchAudioSource(
          newSource,
          initialPosition: targetPos,
          autoPlay: true,
        );
      } else {
        await _audio.setAudioSource(newSource, initialPosition: targetPos);
        await _audio.play();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Silent stall recovery failed: $e');
    }
  }

  Future<void> _preloadNextTrack() async {
    if (prefetchManager == null || queue.isEmpty || current == null) return;
    Track? nextTrack;
    if (currentIndex >= 0 && currentIndex < queue.length - 1) {
      nextTrack = queue[currentIndex + 1];
    } else if (repeatMode == PlaybackRepeatMode.all && queue.isNotEmpty) {
      nextTrack = queue[0];
    }
    if (nextTrack != null) {
      final targetQuality = pendingQuality ?? qualityManager.currentQuality;
      await prefetchManager!.prefetchNextTrack(
        nextTrack,
        userId: authUserId,
        audioQuality: targetQuality,
      );
    }
  }

  void toggleRepeatMode() {
    repeatMode = switch (repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    notifyListeners();
    _scheduleSaveState(immediate: true);
  }

  void toggleShuffle() {
    isShuffled = !isShuffled;
    if (isShuffled) {
      // User enabled Shuffle:
      // Preserve original queue. Current track continues playing without restarting.
      if (_originalQueue.isEmpty && queue.isNotEmpty) {
        _originalQueue = List<Track>.from(queue);
      }
      if (current != null && _originalQueue.isNotEmpty) {
        final remaining = _originalQueue
            .where((t) => !_isSameTrack(t, current!))
            .toList()
          ..shuffle();
        queue = [current!, ...remaining];
        currentIndex = 0;
      } else if (queue.isNotEmpty) {
        queue = List<Track>.from(queue)..shuffle();
        if (current != null) {
          final idx = queue.indexWhere((t) => _isSameTrack(t, current!));
          currentIndex = idx >= 0 ? idx : 0;
        }
      }
    } else {
      // User disabled Shuffle:
      // Restore original album/playlist queue order without stopping current song.
      if (_originalQueue.isNotEmpty) {
        queue = List<Track>.from(_originalQueue);
        if (current != null) {
          final idx = queue.indexWhere((t) => _isSameTrack(t, current!));
          currentIndex = idx >= 0 ? idx : 0;
        }
      }
    }
    _handler?.publishQueue(queue);
    notifyListeners();
    _scheduleSaveState(immediate: true);
  }

  Future<void> playWithShuffle(List<Track> rawQueue, {Track? startTrack}) async {
    if (rawQueue.isEmpty) return;
    isShuffled = true;
    _originalQueue = List<Track>.from(rawQueue);
    _playbackHistory.clear();
    final start = startTrack ?? (List<Track>.from(rawQueue)..shuffle()).first;
    final remaining = rawQueue.where((t) => !_isSameTrack(t, start)).toList()..shuffle();
    queue = [start, ...remaining];
    currentIndex = 0;
    await play(start, fromQueue: queue, restart: true, keepQueueOrder: true);
  }

  void _onPolicyChanged() {
    if (connection != null && policy != null) {
      final newQ = policy!.qualityFor(connection!.state);
      pendingQuality = (currentSession != null && newQ == currentSession!.lockedQuality) ? null : newQ;
    }
    notifyListeners();
  }

  void _onNetworkChanged() {
    final netState = connection?.state;
    final isConnected = netState?.connected == true;

    if (isConnected && policy != null && netState != null) {
      final newQ = policy!.qualityFor(netState);
      pendingQuality = (currentSession != null && newQ == currentSession!.lockedQuality) ? null : newQ;
    }

    if (!isConnected) {
      if (playing &&
          _audio.playerState.processingState == ProcessingState.buffering &&
          qualityManager.bufferHealthSeconds <= 1.0) {
        error = 'Waiting for connection';
      }
      // Buffered audio keeps playing uninterrupted
    } else {
      if (error == 'Waiting for connection' ||
          error == 'Unavailable offline' ||
          error == 'Playback is unavailable for this track.') {
        error = null;
      }

      final isCellular = netState?.connectionType == ConnectionType.cellular;
      final isDisallowedCellular = isCellular &&
          policy != null &&
          !policy!.allowMobileStreaming &&
          downloads?.localPath(current?.seokey ?? '') == null &&
          downloads?.localPath(current?.id ?? '') == null;

      if (isDisallowedCellular) {
        if (playing) {
          unawaited(pause());
          error = 'Mobile data streaming is disabled in Settings.';
        }
      } else {
        // Network reconnected:
        // If buffered audio is still playing smoothly, do NOT restart or reload from 00:00!
        final mediaItemId = _handler?.mediaItem.value?.id;
        final currentTrackId = current?.id ?? current?.seokey;
        final isCorrectTrackPlaying = mediaItemId != null &&
            currentTrackId != null &&
            (mediaItemId == currentTrackId || mediaItemId == current?.trackId);

        final isAudioActive = _audio.playing &&
            _audio.playerState.processingState != ProcessingState.idle &&
            isCorrectTrackPlaying;

        if (current != null && playing && !isAudioActive) {
          error = null;
          // Silent stall recovery at current position rather than hard restart from 00:00
          unawaited(_onPlaybackStallDetected());
        }
      }
    }
    notifyListeners();
  }

  void _scheduleSaveState({bool immediate = false}) {
    if (immediate) {
      _saveThrottleTimer?.cancel();
      _saveThrottleTimer = null;
      unawaited(persistStateNow());
      return;
    }
    if (_saveThrottleTimer != null && _saveThrottleTimer!.isActive) return;
    _saveThrottleTimer = Timer(const Duration(seconds: 1), () {
      unawaited(persistStateNow());
    });
  }

  Future<void> persistStateNow() async {
    final track = current;
    if (track == null) return;
    try {
      final local = await SharedPreferences.getInstance();
      await local.setString(
        'player_state',
        jsonEncode({
          'track': {
            'id': track.id,
            'seokey': track.seokey,
            'track_id': track.trackId,
            'title': track.title,
            'artist': track.artist,
            'artists': track.artist,
            'artist_ids': track.artistIds,
            'album': track.album,
            'album_id': track.albumId,
            'album_seokey': track.albumSeokey,
            'genres': track.genres,
            'language': track.language,
            'duration': track.durationSeconds,
            'duration_seconds': track.durationSeconds,
            'image_url': track.imageUrl,
            'imageUrl': track.imageUrl,
            'stream_url': track.streamUrl,
            'streamUrl': track.streamUrl,
            'is_explicit': track.isExplicit,
            'reasons': track.reasons,
          },
          'queue': queue
              .map(
                (t) => {
                  'id': t.id,
                  'seokey': t.seokey,
                  'track_id': t.trackId,
                  'title': t.title,
                  'artist': t.artist,
                  'artist_ids': t.artistIds,
                  'album': t.album,
                  'album_id': t.albumId,
                  'album_seokey': t.albumSeokey,
                  'language': t.language,
                  'duration': t.durationSeconds,
                  'image_url': t.imageUrl,
                  'imageUrl': t.imageUrl,
                  'stream_url': t.streamUrl,
                  'stream_urls': t.streamUrls,
                },
              )
              .toList(),
          'current_index': currentIndex,
          'position_ms': position.inMilliseconds,
          'duration_ms': duration.inMilliseconds > 0
              ? duration.inMilliseconds
              : track.durationSeconds * 1000,
          'was_playing': playing,
          'repeat_mode': repeatMode.name,
          'is_shuffled': isShuffled,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  Future<void> restorePlaybackSession(
    Track track,
    List<Track> queue,
    Duration savedPosition, {
    bool wasPlaying = false,
    PlaybackRepeatMode repeat = PlaybackRepeatMode.off,
    bool shuffled = false,
    int? savedIndex,
  }) async {
    current = track;
    this.queue = queue.isNotEmpty ? queue : [track];
    _originalQueue = List<Track>.from(this.queue);
    _playbackHistory.clear();
    position = savedPosition;
    duration = Duration(seconds: track.durationSeconds);
    playing = wasPlaying;
    repeatMode = repeat;
    isShuffled = shuffled;
    if (savedIndex != null && savedIndex >= 0 && savedIndex < this.queue.length) {
      currentIndex = savedIndex;
    } else {
      final idx = this.queue.indexWhere((t) => _isSameTrack(t, track));
      currentIndex = idx >= 0 ? idx : 0;
    }
    notifyListeners();
    unawaited(
      play(
        track,
        // A non-null empty queue would erase the restored current track.
        fromQueue: this.queue,
        restart: true,
        initialPosition: savedPosition,
        autoPlay: wasPlaying,
        keepQueueOrder: true,
      ),
    );
  }

  Future<void> _unbindAudio() async {
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _stateSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription = null;
    _stateSubscription = null;
  }

  void _bindAudio(AudioPlayer audio, int session) {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _positionSubscription = audio.positionStream.listen((value) {
      if (_disposed || session != _playbackSession) return;
      if (value > Duration.zero || position == Duration.zero) {
        position = value;
        currentSession?.position = value;
        currentSession?.bufferedPosition = audio.bufferedPosition;
        qualityManager.updateBufferHealth(value, audio.bufferedPosition);
        qualityManager.recordPlaybackProgress();
        watchdog.updatePosition(value);
        watchdog.evaluate(
          isPlaying: playing,
          processingState: audio.processingState,
          position: value,
          bufferedPosition: audio.bufferedPosition,
        );

        // Preload next track when >= 75% or within last 30 seconds
        if (!_hasPrefetchedNextForCurrent && duration > Duration.zero) {
          final threshold = duration.inSeconds * 0.75;
          if (value.inSeconds >= threshold || (duration - value).inSeconds <= 30) {
            _hasPrefetchedNextForCurrent = true;
            unawaited(_preloadNextTrack());
          }
        }

        notifyListeners();
        _scheduleSaveState();
      }
    });
    _durationSubscription = audio.durationStream.listen((value) {
      if (_disposed || session != _playbackSession) return;
      if (value != null && value > Duration.zero) {
        duration = value;
        notifyListeners();
      }
    });
    _stateSubscription = audio.playerStateStream.listen((value) {
      if (_disposed || session != _playbackSession) return;
      playing = value.playing;
      if (value.playing) {
        watchdog.start();
        qualityManager.start();
      } else {
        watchdog.stop();
        qualityManager.stop();
      }
      watchdog.evaluate(
        isPlaying: value.playing,
        processingState: value.processingState,
        position: position,
        bufferedPosition: audio.bufferedPosition,
      );
      if (value.processingState == ProcessingState.buffering &&
          qualityManager.bufferHealthSeconds <= 0.5) {
        qualityManager.recordStall();
      }
      notifyListeners();
      _scheduleSaveState(immediate: true);
      if (value.processingState == ProcessingState.completed &&
          current != null &&
          !_isTransitioning) {
        unawaited(onSongCompleted());
      }
    });
  }

  Future<void> attachHandler(MusicAudioHandler handler) async {
    _handler = handler;
    handler.onNext = next;
    handler.onPrevious = previous;
    await _handler!.initialize();
    _bindAudio(handler.player, _playbackSession);
    notifyListeners();
  }

  /// Start the native media session before the first user play action.
  ///
  /// Initialising this lazily from `play` can race with the first audio load;
  /// in that case just_audio still plays, but Android has no media session to
  /// publish on the lock screen. The method is safe to call more than once.
  Future<void> initializeBackgroundAudio() async {
    if (kIsWeb || _handler != null || _disposed) return;
    final existing = _backgroundAudioInitialization;
    if (existing != null) return existing;
    final initialization = _initializeBackgroundAudio();
    _backgroundAudioInitialization = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_backgroundAudioInitialization, initialization)) {
        _backgroundAudioInitialization = null;
      }
    }
  }

  Future<void> _initializeBackgroundAudio() async {
    try {
      final handler = await initAudioHandler();
      if (_disposed) {
        await handler.dispose();
        return;
      }
      await attachHandler(handler);
    } catch (_) {
      // The foreground player remains a usable fallback on unsupported
      // platforms or when the native media service cannot be started.
    }
  }

  Future<void> play(
    Track track, {
    List<Track>? fromQueue,
    bool restart = false,
    Duration? initialPosition,
    bool autoPlay = true,
    // Pass true for all internal calls (next/previous/toggle/recovery/restore)
    // where the queue order is already correct and must not be reshuffled.
    // External callers (user picks a song from album/playlist UI) leave this
    // false so that a pending shuffle is applied to the incoming raw queue.
    bool keepQueueOrder = false,
  }) async {
    final mediaId = _handler?.mediaItem.value?.id;
    final isSameMediaLoaded = mediaId != null &&
        (mediaId == track.id || mediaId == track.seokey || mediaId == track.trackId);
    final isSameTrack = current?.id == track.id ||
        (track.seokey.isNotEmpty && current?.seokey == track.seokey);
    if (isSameTrack && isSameMediaLoaded && !restart && isReady) {
      queue = fromQueue ?? queue;
      if (initialPosition != null && initialPosition > Duration.zero) {
        await seek(initialPosition);
      }
      if (isSameTrack && !playing && autoPlay) {
        unawaited(_handler?.play() ?? _audio.play());
      }
      return;
    }

    // Instantly reset position and duration to zero within 0ms so the UI updates in real-time
    if (currentSession != null) {
      debugPrint(currentSession!.generateTrackDataReport());
    }
    prefetchManager?.cancel();
    final session = ++_playbackSession;
    _activeCachedSource?.cancel();
    _activeCachedSource = null;
    _hasPrefetchedNextForCurrent = false;
    current = track;
    position = initialPosition ?? Duration.zero;
    duration = Duration(seconds: track.durationSeconds);
    playing = autoPlay;
    error = null;
    if (fromQueue != null) {
      if (keepQueueOrder) {
        // The queue is already in the correct playback order (shuffled or not).
        // Never re-randomise it — doing so is what caused the same-song loop /
        // random-track bug where every completion reshuffled the remaining songs.
        queue = fromQueue;
        final idx = queue.indexWhere((t) => _isSameTrack(t, track));
        currentIndex = idx >= 0 ? idx : currentIndex;
        // Keep _originalQueue in sync only when shuffle is off; when shuffle
        // is on it was already set by toggleShuffle() and must not be overwritten.
        if (!isShuffled) {
          _originalQueue = List<Track>.from(fromQueue);
        }
      } else {
        // New external context (user picks a song from album/playlist UI).
        _originalQueue = List<Track>.from(fromQueue);
        _playbackHistory.clear();
        if (isShuffled && fromQueue.length > 1) {
          final remaining = fromQueue.where((t) => !_isSameTrack(t, track)).toList()..shuffle();
          queue = [track, ...remaining];
          currentIndex = 0;
        } else {
          queue = List<Track>.from(fromQueue);
          final idx = queue.indexWhere((t) => _isSameTrack(t, track));
          currentIndex = idx >= 0 ? idx : 0;
        }
      }
    } else if (queue.isEmpty) {
      queue = [track];
      _originalQueue = [track];
      currentIndex = 0;
    } else {
      final idx = queue.indexWhere((t) => _isSameTrack(t, track));
      if (idx >= 0) currentIndex = idx;
    }
    notifyListeners();
    _scheduleSaveState(immediate: true);

    // Stop and kill previous audio immediately (0ms) so old song stops playing instantly
    try {
      _handler?.player.pause();
      _handler?.player.seek(Duration.zero);
      _handler?.player.stop();
      _fallback.pause();
      _fallback.seek(Duration.zero);
      _fallback.stop();
    } catch (_) {}

    var localPath = downloads?.localPathForTrack(track) ??
        downloads?.localPath(track.id) ??
        downloads?.localPath(track.seokey);
    var state = connection?.state;
    if (policy?.offlineMode == true && localPath == null) {
      error = 'Unavailable offline';
      notifyListeners();
      return;
    }

    // If network appears disconnected (e.g. WiFi <-> Mobile Data handover),
    // wait briefly for the connection to establish before rejecting.
    if (localPath == null && state != null && !state.connected && policy?.offlineMode != true) {
      await connection?.waitForConnection(timeout: const Duration(milliseconds: 1800));
      state = connection?.state;
    }

    if (localPath == null &&
        state != null &&
        policy != null &&
        !policy!.canUseNetwork(state, forDownload: false) &&
        !(current?.id == track.id && isReady)) {
      if (state.connected && state.connectionType == ConnectionType.cellular && !policy!.allowMobileStreaming) {
        error = 'Mobile data streaming is disabled. Connect to Wi-Fi or enable it in Settings.';
      } else {
        error = 'Waiting for connection';
      }
      notifyListeners();
      return;
    }

    void updateTrackInQueue(Track updated) {
      if (currentIndex >= 0 && currentIndex < queue.length) {
        final q = List<Track>.from(queue);
        q[currentIndex] = updated;
        queue = q;
      } else {
        final idx = queue.indexWhere((t) => _isSameTrack(t, updated));
        if (idx != -1) {
          final q = List<Track>.from(queue);
          q[idx] = updated;
          queue = q;
        }
      }
      final uIdx = _originalQueue.indexWhere((t) => _isSameTrack(t, updated));
      if (uIdx != -1) {
        final uq = List<Track>.from(_originalQueue);
        uq[uIdx] = updated;
        _originalQueue = uq;
      }
    }

    if (localPath == null && track.streamUrl.isEmpty && resolveTrack != null) {
      try {
        final resolved = await resolveTrack!(track);
        if (resolved != null && resolved.streamUrl.isNotEmpty) {
          track = resolved;
          if (session == _playbackSession) {
            current = track;
            updateTrackInQueue(track);
            notifyListeners();
          }
        }
      } catch (_) {}
    }
    final String activeQuality;
    if (pendingQuality != null) {
      activeQuality = pendingQuality!;
      pendingQuality = null;
    } else {
      activeQuality = policy?.qualityFor(connection?.state ?? const NetworkState()) ??
          qualityManager.resolveQualityForTrack(track);
    }
    final preferredQualityUrl = track.getStreamUrlForQuality(activeQuality);
    final targetStreamUrl = preferredQualityUrl.isNotEmpty ? preferredQualityUrl : track.streamUrl;
    if (targetStreamUrl.isNotEmpty && targetStreamUrl != track.streamUrl) {
      track = track.copyWith(streamUrl: targetStreamUrl);
      if (session == _playbackSession) {
        current = track;
        updateTrackInQueue(track);
      }
    }

    final int lockedBitrate = track.getBitrateForQuality(activeQuality);
    final String codec = isHlsStream(targetStreamUrl) ? 'HLS' : 'AAC';
    final String cacheKey = AudioCache.generateKey(
      userId: authUserId,
      songId: track.id.isNotEmpty ? track.id : track.seokey,
      audioQuality: activeQuality,
    );
    final String requestId = '${track.id}_${session}_${DateTime.now().microsecondsSinceEpoch}';

    currentSession = PlaybackSession(
      trackId: track.id.isNotEmpty ? track.id : track.seokey,
      title: track.title,
      streamUrl: targetStreamUrl,
      codec: codec,
      lockedBitrate: lockedBitrate,
      lockedQuality: activeQuality,
      duration: Duration(seconds: track.durationSeconds),
      cacheKey: cacheKey,
      requestId: requestId,
      isPlaying: autoPlay,
    );
    pendingQuality = null;

    _playOperation = _playOperation.then((_) async {
      if (_disposed || session != _playbackSession) return;
      error = null;
      try {
        try {
          await _unbindAudio();
          await _audio.stop();
        } catch (_) {}
        if (session != _playbackSession) return;

        // Auto-resolve stream if empty or expired
        if (localPath == null &&
            (track.streamUrl.isEmpty || MusicApi.isStreamExpired(track.streamUrl)) &&
            resolveTrack != null) {
          try {
            final resolved = await resolveTrack!(track, forceFresh: true);
            if (resolved != null && resolved.streamUrl.isNotEmpty) {
              final q = currentSession?.lockedQuality ?? activeQuality;
              final targetUrl = resolved.getStreamUrlForQuality(q);
              track = resolved.copyWith(
                streamUrl: targetUrl.isNotEmpty ? targetUrl : resolved.streamUrl,
              );
              if (session == _playbackSession) {
                current = track;
                updateTrackInQueue(track);
                notifyListeners();
              }
            }
          } catch (_) {}
        }
        if (session != _playbackSession) return;

        if (localPath == null && track.streamUrl.isEmpty) {
          // One more attempt to resolve in case network just completed switch
          if (resolveTrack != null) {
            if (connection != null && !connection!.state.connected) {
              await connection!.waitForConnection(timeout: const Duration(seconds: 2));
            }
            try {
              final resolved = await resolveTrack!(track, forceFresh: true);
              if (resolved != null && resolved.streamUrl.isNotEmpty) {
                final q = currentSession?.lockedQuality ?? activeQuality;
                final targetUrl = resolved.getStreamUrlForQuality(q);
                track = resolved.copyWith(
                  streamUrl: targetUrl.isNotEmpty ? targetUrl : resolved.streamUrl,
                );
                if (session == _playbackSession) {
                  current = track;
                  updateTrackInQueue(track);
                  notifyListeners();
                }
              }
            } catch (_) {}
          }
        }
        if (session != _playbackSession) return;

        if (localPath == null && track.streamUrl.isEmpty) {
          throw StateError('This track has no playable stream.');
        }
        if (_handler == null && !kIsWeb) {
          await initializeBackgroundAudio();
        }
        if (session != _playbackSession) return;
        _bindAudio(_handler?.player ?? _audio, session);
        Duration? loadedDuration;

        Future<Duration?> attemptLoad({bool forceDirect = false}) async {
          final filePath = localPath ??
              downloads?.localPathForTrack(track) ??
              downloads?.localPath(track.id) ??
              downloads?.localPath(track.seokey);
          if (filePath != null) {
            try {
              return _handler != null
                  ? await _handler!.loadLocalTrack(track, filePath,
                      autoPlay: autoPlay)
                  : await _audio.setFilePath(filePath);
            } catch (localErr) {
              debugPrint('Local playback error for "${track.title}" from $filePath: $localErr. Falling back to online stream.');
              localPath = null;
            }
          }
          if (localPath == null) {
            AudioSource source;
            final isHls = isHlsStream(track.streamUrl);
            if (!forceDirect && audioCache != null && !isHls) {
              final cacheKey = AudioCache.generateKey(
                userId: authUserId,
                songId: track.id.isNotEmpty ? track.id : track.seokey,
                audioQuality: activeQuality,
              );
              audioCache!.protect(cacheKey);
              _activeCachedSource?.cancel();
              final cachedSource = CachedStreamAudioSource(
                audioCache: audioCache!,
                downloader: prefetchManager?.downloader ?? SegmentDownloader(),
                uri: Uri.parse(track.streamUrl),
                cacheKey: cacheKey,
                songId: track.id.isNotEmpty ? track.id : track.seokey,
                userId: authUserId,
                audioQuality: activeQuality,
                tag: _handler?.toMediaItem(track),
                onNetworkDownloaded: (bytes) {
                  currentSession?.networkBytesDownloaded += bytes;
                },
                onCacheRead: (bytes) {
                  currentSession?.cacheBytesRead += bytes;
                },
                onDuplicatePrevented: () {
                  currentSession?.duplicateRequestPrevented = true;
                },
              );
              _activeCachedSource = cachedSource;
              source = cachedSource;
            } else {
              _activeCachedSource?.cancel();
              _activeCachedSource = null;
              source = AudioSource.uri(
                Uri.parse(track.streamUrl),
                tag: _handler?.toMediaItem(track),
              );
            }

            if (_handler != null) {
              _handler!.publishQueue(queue);
              return await _handler!.loadAudioSource(track, source, autoPlay: autoPlay);
            } else {
              final dur = await _audio.setAudioSource(source);
              if (autoPlay) {
                unawaited(_audio.play().catchError((_) {}));
              }
              return dur;
            }
          }
          return null;
        }

        try {
          loadedDuration = await attemptLoad();
        } catch (loadError) {
          debugPrint('Audio stream load error for "${track.title}": $loadError');
          // If cached stream source failed, immediately fallback to direct AudioSource.uri
          if (_activeCachedSource != null && localPath == null && track.streamUrl.isNotEmpty) {
            try {
              debugPrint('Cached audio source failed ($loadError), falling back to direct stream URI for "${track.title}"');
              loadedDuration = await attemptLoad(forceDirect: true);
            } catch (directErr) {
              debugPrint('Direct load also failed for "${track.title}": $directErr');
            }
          }

          if (loadedDuration == null) {
            // If stream loading failed (e.g. network handover, expired Akamai token, or socket reset),
            // retry loading with fresh track resolution.
            var retried = false;
            for (var retryCount = 1; retryCount <= 2; retryCount++) {
              if (session != _playbackSession) return;
              await Future.delayed(Duration(milliseconds: 300 * retryCount));
              if (connection != null && !connection!.state.connected) {
                await connection!.waitForConnection(timeout: const Duration(seconds: 2));
              }
              try {
                currentSession?.retryCount = (currentSession?.retryCount ?? 0) + 1;
                Track? fresh;
                if (resolveTrack != null) {
                  fresh = await resolveTrack!(track, forceFresh: true);
                }
                final q = currentSession?.lockedQuality ?? activeQuality;
                final freshQualityUrl = fresh?.getStreamUrlForQuality(q) ?? '';
                final targetUrl = freshQualityUrl.isNotEmpty
                    ? freshQualityUrl
                    : (fresh != null && fresh.streamUrl.isNotEmpty)
                        ? fresh.streamUrl
                        : track.getStreamUrlForQuality(q);
                if (fresh != null) {
                  track = fresh.copyWith(streamUrl: targetUrl);
                  if (session == _playbackSession) {
                    current = track;
                    updateTrackInQueue(track);
                    notifyListeners();
                  }
                }
                if (targetUrl.isNotEmpty) {
                  AudioSource retrySource;
                  final isHls = isHlsStream(targetUrl);
                  if (audioCache != null && !isHls) {
                    final cacheKey = AudioCache.generateKey(
                      userId: authUserId,
                      songId: track.id.isNotEmpty ? track.id : track.seokey,
                      audioQuality: q,
                    );
                    audioCache!.protect(cacheKey);
                    _activeCachedSource?.cancel();
                    final cachedSource = CachedStreamAudioSource(
                      audioCache: audioCache!,
                      downloader: prefetchManager?.downloader ?? SegmentDownloader(),
                      uri: Uri.parse(targetUrl),
                      cacheKey: cacheKey,
                      songId: track.id.isNotEmpty ? track.id : track.seokey,
                      userId: authUserId,
                      audioQuality: q,
                      tag: _handler?.toMediaItem(track),
                      onNetworkDownloaded: (bytes) {
                        currentSession?.networkBytesDownloaded += bytes;
                      },
                      onCacheRead: (bytes) {
                        currentSession?.cacheBytesRead += bytes;
                      },
                      onDuplicatePrevented: () {
                        currentSession?.duplicateRequestPrevented = true;
                      },
                    );
                    _activeCachedSource = cachedSource;
                    retrySource = cachedSource;
                  } else {
                    _activeCachedSource?.cancel();
                    _activeCachedSource = null;
                    retrySource = AudioSource.uri(
                      Uri.parse(targetUrl),
                      tag: _handler?.toMediaItem(track),
                    );
                  }

                  try {
                    if (_handler != null) {
                      _handler!.publishQueue(queue);
                      loadedDuration = await _handler!.loadAudioSource(track, retrySource,
                          autoPlay: autoPlay);
                    } else {
                      loadedDuration = await _audio.setAudioSource(retrySource);
                      if (autoPlay) {
                        unawaited(_audio.play().catchError((_) {}));
                      }
                    }
                  } catch (retryErr) {
                    // If cached retry source failed, try direct AudioSource.uri
                    if (_activeCachedSource != null) {
                      _activeCachedSource?.cancel();
                      _activeCachedSource = null;
                      final directRetry = AudioSource.uri(
                        Uri.parse(targetUrl),
                        tag: _handler?.toMediaItem(track),
                      );
                      if (_handler != null) {
                        _handler!.publishQueue(queue);
                        loadedDuration = await _handler!.loadAudioSource(track, directRetry,
                            autoPlay: autoPlay);
                      } else {
                        loadedDuration = await _audio.setAudioSource(directRetry);
                        if (autoPlay) {
                          unawaited(_audio.play().catchError((_) {}));
                        }
                      }
                    } else {
                      rethrow;
                    }
                  }
                  retried = true;
                  break;
                }
              } catch (_) {}
            }

            if (!retried) {
              if (loadError.toString().contains('MissingPluginException')) {
                loadedDuration = Duration(seconds: track.durationSeconds);
              } else {
                rethrow;
              }
            }
          }
        }
        if (session != _playbackSession) return;

        duration = loadedDuration ?? Duration(seconds: track.durationSeconds);
        if (initialPosition != null && initialPosition > Duration.zero) {
          position = initialPosition;
          try {
            await (_handler?.seek(initialPosition) ??
                _audio.seek(initialPosition));
          } catch (_) {}
        }
        if (session != _playbackSession) return;
        error = null;
        if (autoPlay) {
          playing = true;
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          unawaited((_handler?.play() ?? _audio.play()).catchError((_) {}));
        }
        notifyListeners();
        _scheduleSaveState(immediate: true);

        // Schedule prefetching of the next track in queue
        if (prefetchManager != null && queue.isNotEmpty) {
          final idx = queue.indexWhere((t) => _isSameTrack(t, track));
          if (idx >= 0 && idx + 1 < queue.length) {
            final nextTrack = queue[idx + 1];
            unawaited(
              prefetchManager!.prefetchNextTrack(
                nextTrack,
                userId: authUserId,
                audioQuality: qualityManager.currentQuality,
              ),
            );
          }
        }
      } catch (outerError) {
        if (session != _playbackSession) return;
        if (outerError.toString().contains('MissingPluginException')) {
          error = null;
        } else {
          // Re-bind audio player so player remains functional
          _bindAudio(_handler?.player ?? _audio, session);
          final isOffline = connection?.state.connected == false;
          playing = false;
          error = isOffline
              ? 'Waiting for connection'
              : (track.streamUrl.isEmpty
                  ? 'This track has no playable stream.'
                  : 'Playback is unavailable for this track.');
          notifyListeners();
        }
      }
    });
    await _playOperation;
  }

  Future<void> pause() => _handler?.pause() ?? _audio.pause();
  Future<void> playResume() => _handler?.play() ?? _audio.play();

  Future<void> toggle() {
    if (playing) {
      return pause();
    }
    if (current != null &&
        (error != null ||
            !isReady ||
            _audio.processingState == ProcessingState.idle)) {
      return play(
        current!,
        fromQueue: queue,
        initialPosition: position,
        autoPlay: true,
        keepQueueOrder: true,
      );
    }
    return playResume();
  }
  Future<void> seek(Duration value) async {
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds
        : ((current?.durationSeconds ?? 0) * 1000);
    final clampedMs = maxMs > 0
        ? value.inMilliseconds.clamp(0, maxMs)
        : value.inMilliseconds.clamp(0, 86400000);
    final target = Duration(milliseconds: clampedMs);
    position = target;
    currentSession?.position = target;
    currentSession?.bufferedPosition = _audio.bufferedPosition;
    watchdog.updatePosition(target);
    qualityManager.updateBufferHealth(target, _audio.bufferedPosition);
    notifyListeners();
    _scheduleSaveState(immediate: true);
    try {
      if (_handler != null) {
        await _handler!.seek(target);
      } else {
        await _audio.seek(target);
      }
    } catch (e) {
      debugPrint('Player seek error: $e');
    }
  }

  Future<void> clear() async {
    if (currentSession != null) {
      debugPrint(currentSession!.generateTrackDataReport());
    }
    prefetchManager?.cancel();
    ++_playbackSession;
    _activeCachedSource?.cancel();
    _activeCachedSource = null;
    currentSession = null;
    _hasPrefetchedNextForCurrent = false;
    current = null;
    queue = [];
    _originalQueue = [];
    _playbackHistory.clear();
    isShuffled = false;
    currentIndex = 0;
    position = Duration.zero;
    duration = Duration.zero;
    playing = false;
    error = null;
    _sleepTimer?.cancel();
    watchdog.stop();
    qualityManager.stop();
    await _unbindAudio();
    await _audio.stop();
    notifyListeners();
    try {
      final local = await SharedPreferences.getInstance();
      await local.remove('player_state');
    } catch (_) {}
  }

  Future<void> onSongCompleted() async {
    if (_isTransitioning || current == null || queue.isEmpty) return;
    if (currentSession != null) {
      debugPrint(currentSession!.generateTrackDataReport());
    }
    prefetchManager?.cancel();
    _isTransitioning = true;
    try {
      if (repeatMode == PlaybackRepeatMode.one) {
        position = Duration.zero;
        notifyListeners();
        try {
          await seek(Duration.zero);
          await playResume();
        } catch (_) {}
        return;
      }

      _addToHistory(current!);

      // If currentIndex is out of sync or invalid, attempt to find current in queue
      if (currentIndex < 0 || currentIndex >= queue.length || !_isSameTrack(queue[currentIndex], current!)) {
        final idx = queue.indexWhere((t) => _isSameTrack(t, current!));
        if (idx >= 0) {
          currentIndex = idx;
        }
      }

      if (currentIndex < queue.length - 1) {
        currentIndex++;
        final nextTrack = queue[currentIndex];
        await play(nextTrack, fromQueue: queue, restart: true, keepQueueOrder: true);
        return;
      }

      if (repeatMode == PlaybackRepeatMode.all) {
        currentIndex = 0;
        if (isShuffled && _originalQueue.isNotEmpty) {
          final reshuffled = List<Track>.from(_originalQueue)..shuffle();
          queue = reshuffled;
        }
        await play(queue[0], fromQueue: queue, restart: true, keepQueueOrder: true);
        return;
      }

      if (autoplayEnabled && loadRelatedTracks != null) {
        try {
          final related = await loadRelatedTracks!(current!);
          final unplayed = related
              .where((t) => !_isSameTrack(t, current!) && !queue.any((q) => _isSameTrack(q, t)))
              .toList();
          if (unplayed.isNotEmpty) {
            queue = [...queue, ...unplayed];
            _originalQueue = [..._originalQueue, ...unplayed];
            _handler?.publishQueue(queue);
            currentIndex++;
            await play(queue[currentIndex], fromQueue: queue, restart: true, keepQueueOrder: true);
            return;
          }
        } catch (_) {}
      }

      await stopPlayback();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> stopPlayback() async {
    if (currentSession != null) {
      debugPrint(currentSession!.generateTrackDataReport());
    }
    prefetchManager?.cancel();
    _activeCachedSource?.cancel();
    _activeCachedSource = null;
    ++_playbackSession;
    playing = false;
    position = Duration.zero;
    try {
      _handler?.player.pause();
      _handler?.player.seek(Duration.zero);
      _fallback.pause();
      _fallback.seek(Duration.zero);
    } catch (_) {}
    notifyListeners();
    _scheduleSaveState(immediate: true);
  }

  Future<void> next({bool fromAutoCompletion = false}) async {
    if (fromAutoCompletion) {
      await onSongCompleted();
      return;
    }
    if (current == null || queue.isEmpty) return;
    try {
      _handler?.player.pause();
      _handler?.player.stop();
      _fallback.pause();
      _fallback.stop();
    } catch (_) {}

    _addToHistory(current!);

    if (currentIndex < 0 || currentIndex >= queue.length || !_isSameTrack(queue[currentIndex], current!)) {
      final idx = queue.indexWhere((item) => _isSameTrack(item, current!));
      if (idx >= 0) currentIndex = idx;
    }

    if (currentIndex >= queue.length - 1) {
      // Last track in queue.
      if (repeatMode == PlaybackRepeatMode.all) {
        currentIndex = 0;
        if (isShuffled && _originalQueue.isNotEmpty) {
          final reshuffled = List<Track>.from(_originalQueue)..shuffle();
          queue = reshuffled;
        }
        await play(queue[0], fromQueue: queue, restart: true, keepQueueOrder: true);
        return;
      }
      if (autoplayEnabled && loadRelatedTracks != null) {
        try {
          final related = await loadRelatedTracks!(current!);
          final unplayed = related
              .where((t) => !_isSameTrack(t, current!) && !queue.any((q) => _isSameTrack(q, t)))
              .toList();
          if (unplayed.isNotEmpty) {
            queue = [...queue, ...unplayed];
            _originalQueue = [..._originalQueue, ...unplayed];
            _handler?.publishQueue(queue);
            currentIndex++;
            await play(queue[currentIndex], fromQueue: queue, restart: true, keepQueueOrder: true);
            return;
          }
        } catch (_) {}
      }
      // Manual skip past the last track: stay at the last track (no wrap).
      return;
    }
    // Mid-queue: advance by exactly one index.
    currentIndex++;
    final nextTrack = queue[currentIndex];
    await play(nextTrack, fromQueue: queue, restart: true, keepQueueOrder: true);
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) return;
    _sleepTimer = Timer(duration, () async {
      await _audio.stop();
      notifyListeners();
    });
  }

  Future<void> previous() async {
    if (current == null || queue.isEmpty) return;
    try {
      _handler?.player.pause();
      _handler?.player.stop();
      _fallback.pause();
      _fallback.stop();
    } catch (_) {}
    final currentSec = _audio.position.inSeconds > 0
        ? _audio.position.inSeconds
        : position.inSeconds;
    if (currentSec > 5) {
      position = Duration.zero;
      notifyListeners();
      await seek(Duration.zero);
      return;
    }
    if (_playbackHistory.isNotEmpty) {
      final prevTrack = _playbackHistory.removeLast();
      final pIdx = queue.indexWhere((t) => _isSameTrack(t, prevTrack));
      if (pIdx >= 0) currentIndex = pIdx;
      await play(prevTrack, fromQueue: queue, restart: true, keepQueueOrder: true);
      return;
    }
    if (currentIndex < 0 || currentIndex >= queue.length || !_isSameTrack(queue[currentIndex], current!)) {
      final idx = queue.indexWhere((item) => _isSameTrack(item, current!));
      if (idx >= 0) currentIndex = idx;
    }
    if (currentIndex > 0) {
      currentIndex--;
      final prevTrack = queue[currentIndex];
      await play(prevTrack, fromQueue: queue, restart: true, keepQueueOrder: true);
    } else {
      position = Duration.zero;
      notifyListeners();
      await seek(Duration.zero);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackSession++;
    if (currentSession != null) {
      debugPrint(currentSession!.generateTrackDataReport());
    }
    prefetchManager?.cancel();
    _saveThrottleTimer?.cancel();
    _sleepTimer?.cancel();
    _qualitySubscription?.cancel();
    _activeCachedSource?.cancel();
    watchdog.dispose();
    qualityManager.dispose();
    _unbindAudio();
    if (_handler == null) {
      _fallback.dispose();
    }
    super.dispose();
  }
}
