import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models.dart';

const _serviceId   = 'soundwaves-service';
const _connectorId = 'soundwaves-connector';
const _location    = 'us-central1';
const _projectId   = 'personal-songs';

String get _baseUrl =>
    'https://firebasedataconnect.googleapis.com/v1beta/projects/$_projectId'
    '/locations/$_location/services/$_serviceId'
    '/connectors/$_connectorId';

// ─── Value objects ────────────────────────────────────────────────────────────

class UserPreferences {
  final List<String> languages;
  final List<String> favoriteArtistIds;   // UUID strings
  final List<String> favoriteGenreIds;    // UUID strings

  const UserPreferences({
    this.languages = const [],
    this.favoriteArtistIds = const [],
    this.favoriteGenreIds = const [],
  });

  factory UserPreferences.empty() => const UserPreferences();
}

class RecommendedTrack {
  final String id;
  final String externalId;
  final String title;
  final String artistName;
  final String language;
  final String imageUrl;
  final String streamUrl;
  final int durationSeconds;
  final double popularity;

  const RecommendedTrack({
    required this.id,
    required this.externalId,
    required this.title,
    required this.artistName,
    required this.language,
    required this.imageUrl,
    required this.streamUrl,
    required this.durationSeconds,
    required this.popularity,
  });

  factory RecommendedTrack.fromRow(Map<String, dynamic> row) => RecommendedTrack(
    id:              row['id'] as String? ?? '',
    externalId:      row['externalId'] as String? ?? '',
    title:           row['title'] as String? ?? '',
    artistName:      row['artistName'] as String? ?? row['artist'] as String? ?? '',
    language:        row['language'] as String? ?? '',
    imageUrl:        row['coverUrl'] as String? ?? row['imageUrl'] as String? ?? '',
    streamUrl:       row['streamUrl'] as String? ?? row['stream_url'] as String? ?? '',
    durationSeconds: (row['durationSeconds'] as num?)?.toInt() ?? 0,
    popularity:      (row['popularity'] as num?)?.toDouble() ?? 0.0,
  );

  Track toTrack() => Track(
    seokey:          externalId.isNotEmpty ? externalId : id,
    trackId:         id,
    title:           title,
    artist:          artistName,
    language:        language,
    imageUrl:        imageUrl,
    streamUrl:       streamUrl,
    durationSeconds: durationSeconds,
  );
}

// ─── Service ──────────────────────────────────────────────────────────────────

class RecommendationService {
  final FirebaseAuth _auth;

  RecommendationService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  Future<String> _idToken() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    return (await user.getIdToken())!;
  }

  Future<Map<String, dynamic>> _executeQuery(
    String operationName,
    Map<String, dynamic> variables,
  ) async {
    final token = await _idToken();
    final res = await http.post(
      Uri.parse('$_baseUrl:executeQuery'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Goog-Request-Params': 'location=$_location',
      },
      body: jsonEncode({'operationName': operationName, 'variables': variables}),
    );
    if (res.statusCode != 200) {
      throw Exception('Data Connect query failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _executeMutation(
    String operationName,
    Map<String, dynamic> variables,
  ) async {
    final token = await _idToken();
    final res = await http.post(
      Uri.parse('$_baseUrl:executeMutation'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Goog-Request-Params': 'location=$_location',
      },
      body: jsonEncode({'operationName': operationName, 'variables': variables}),
    );
    if (res.statusCode != 200) {
      throw Exception('Data Connect mutation failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Preferences ───────────────────────────────────────────────────────────

  Future<UserPreferences> loadPreferences(String userId) async {
    final results = await Future.wait([
      _executeQuery('GetUserLanguages', {'userId': userId}),
      _executeQuery('GetUserFavoriteArtists', {'userId': userId}),
      _executeQuery('GetUserFavoriteGenres', {'userId': userId}),
    ]);

    final langs = (results[0]['data']['userLanguages'] as List? ?? [])
        .map((r) => r['language'] as String)
        .toList();

    final artistIds = (results[1]['data']['userFavoriteArtists'] as List? ?? [])
        .map((r) => r['artist']['id'] as String)
        .toList();

    final genreIds = (results[2]['data']['userFavoriteGenres'] as List? ?? [])
        .map((r) => r['genre']['id'] as String)
        .toList();

    return UserPreferences(
      languages: langs,
      favoriteArtistIds: artistIds,
      favoriteGenreIds: genreIds,
    );
  }

  Future<void> saveLanguages(String userId, List<String> languages) =>
      _executeMutation('SetUserLanguages', {'userId': userId, 'languages': languages});

  Future<void> saveFavoriteArtists(String userId, List<String> artistIds) =>
      _executeMutation('SetUserFavoriteArtists', {
        'userId': userId,
        'artistIds': artistIds,
      });

  Future<void> saveFavoriteGenres(String userId, List<String> genreIds) =>
      _executeMutation('SetUserFavoriteGenres', {
        'userId': userId,
        'genreIds': genreIds,
      });

  // ── Recommendations ───────────────────────────────────────────────────────

  Future<List<RecommendedTrack>> getRecommendations(
    String userId, {
    int limit = 20,
  }) async {
    final body = await _executeQuery('GetRecommendations', {
      'userId': userId,
      'limit': limit,
    });
    final rows = body['data']['songs'] as List? ?? [];
    return rows.map((r) => RecommendedTrack.fromRow(r as Map<String, dynamic>)).toList();
  }

  Future<List<RecommendedTrack>> getCachedRecommendations(
    String userId, {
    int limit = 20,
  }) async {
    final body = await _executeQuery('GetCachedRecommendations', {
      'userId': userId,
      'limit': limit,
    });
    final rows = body['data']['recommendationCaches'] as List? ?? [];
    return rows
        .map((r) => RecommendedTrack.fromRow(r['song'] as Map<String, dynamic>))
        .toList();
  }

  // ── Play tracking ─────────────────────────────────────────────────────────

  Future<void> recordPlay(
    String userId,
    String songId, {
    required int completionPct,
    required int listenedSeconds,
    String source = 'app',
    bool skipped = false,
  }) async {
    await Future.wait([
      _executeMutation('RecordPlay', {
        'userId':          userId,
        'songId':          songId,
        'completionPct':   completionPct,
        'listenedSeconds': listenedSeconds,
        'source':          source,
        'device':          'mobile',
        'skipped':         skipped,
      }),
      _executeMutation('IncrementPlayCount', {'songId': songId}),
    ]);
  }

  // ── Liked songs ───────────────────────────────────────────────────────────

  Future<void> likeSong(String userId, String songId) =>
      _executeMutation('LikeSong', {'userId': userId, 'songId': songId});

  Future<void> unlikeSong(String userId, String songId) =>
      _executeMutation('UnlikeSong', {'userId': userId, 'songId': songId});

  Future<List<Track>> getLikedSongs(String userId, {int limit = 50}) async {
    final body = await _executeQuery('GetUserFavoriteSongs', {
      'userId': userId,
      'limit': limit,
    });
    final rows = body['data']['userFavoriteSongs'] as List? ?? [];
    return rows.map((r) {
      final s = r['song'] as Map<String, dynamic>;
      return Track(
        seokey:          s['externalId'] as String? ?? s['id'] as String? ?? '',
        trackId:         s['id'] as String? ?? '',
        title:           s['title'] as String? ?? '',
        artist:          s['artistName'] as String? ?? s['artist'] as String? ?? '',
        imageUrl:        s['coverUrl'] as String? ?? s['imageUrl'] as String? ?? '',
        streamUrl:       s['streamUrl'] as String? ?? s['stream_url'] as String? ?? '',
        durationSeconds: (s['durationSeconds'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  // ── Recent plays ──────────────────────────────────────────────────────────

  Future<List<Track>> getRecentPlays(String userId, {int limit = 20}) async {
    final body = await _executeQuery('GetRecentPlays', {
      'userId': userId,
      'limit': limit,
    });
    final rows = body['data']['playHistories'] as List? ?? [];
    return rows.map((r) {
      final s = r['song'] as Map<String, dynamic>;
      return Track(
        seokey:          s['externalId'] as String? ?? s['id'] as String? ?? '',
        trackId:         s['id'] as String? ?? '',
        title:           s['title'] as String? ?? '',
        artist:          s['artistName'] as String? ?? s['artist'] as String? ?? '',
        imageUrl:        s['coverUrl'] as String? ?? s['imageUrl'] as String? ?? '',
        streamUrl:       s['streamUrl'] as String? ?? s['stream_url'] as String? ?? '',
        durationSeconds: (s['durationSeconds'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }
}
