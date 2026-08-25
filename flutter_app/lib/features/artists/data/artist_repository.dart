import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/config/app_config.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

/// One page of recommended artists plus the cursor that continues it.
class ArtistPage {
  const ArtistPage({this.artists = const [], this.nextCursor});

  final List<MusicItem> artists;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Artist recommendations and artist search.
///
/// These are two different questions and are kept on separate paths: search
/// must return the artist that was typed, recommendation must return artists
/// the listener is likely to enjoy. They share nothing but this class.
class ArtistRepository {
  ArtistRepository(this._api, this._store);

  static const _cacheKey = 'artist_recommendations';

  /// Recommendations stay usable well past their refresh window, because
  /// showing slightly stale artists instantly beats showing a spinner.
  static const _cacheTtl = Duration(hours: 6);

  final ApiClient _api;
  final LocalStore _store;

  /// The last recommendations written to disk, for painting before the network
  /// answers. Returns null when nothing has been cached yet.
  List<MusicItem>? cachedRecommendations() {
    final entry = _store.readCacheEntry(_cacheKey);
    final value = entry?.value;
    if (value is! List || value.isEmpty) return null;
    final artists = _items(value);
    return artists.isEmpty ? null : artists;
  }

  Future<ArtistPage> recommended({String? cursor, int limit = 30}) async {
    final json = await _api.getMap(
      ApiEndpoints.artistsRecommended,
      query: {'limit': limit, 'cursor': ?cursor},
    );
    final data = json['data'];
    // Only the first page is cached. Later pages belong to a cursor that will
    // not be valid on the next launch.
    if (cursor == null && data is List && data.isNotEmpty) {
      await _store.putCached(_cacheKey, data, ttl: _cacheTtl);
    }
    return ArtistPage(
      artists: _items(data),
      nextCursor: json['next_cursor']?.toString(),
    );
  }

  /// Artist-only search. The dedicated endpoint ranks by name match, so an
  /// exact name comes back first instead of being buried under songs.
  Future<List<MusicItem>> search(String query, {int limit = 25}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final json = await _api.getMap(
      ApiEndpoints.searchArtists,
      query: {'q': trimmed, 'limit': limit},
    );
    return _items(json['data']);
  }

  Future<List<MusicItem>> related(String artistId, {int limit = 20}) async {
    if (artistId.isEmpty) return const [];
    try {
      final json = await _api.getMap(
        '${ApiEndpoints.artists}/id/$artistId/related',
        query: {'limit': limit},
      );
      return _items(json['data']);
    } catch (_) {
      // Related artists are supporting content and must never fail the page.
      return const [];
    }
  }

  static List<MusicItem> _items(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
        .where((item) => item.title.isNotEmpty && item.title != 'Unknown')
        .toList(growable: false);
  }
}

/// Kept for the cache TTL used above to stay in step with the rest of the app.
const artistMetadataTtl = AppConfig.metadataCacheTtl;
