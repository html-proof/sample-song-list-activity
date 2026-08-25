import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/config/app_config.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/home_feed.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class HomeRepository {
  HomeRepository(this._api, this._store);

  /// A cached feed older than this is treated as absent rather than shown, so
  /// a long-idle install never opens on yesterday's recommendations.
  static const _maxStaleAge = Duration(hours: 12);

  final ApiClient _api;
  final LocalStore _store;

  /// True when the last [load] painted from disk. The controller uses this to
  /// decide whether a silent refresh is worth running.
  bool servedStale = false;

  Future<HomeFeed> load({bool refresh = false}) async {
    servedStale = false;
    if (!refresh) {
      final entry = _store.readCacheEntry('home');
      final cached = entry?.value;
      if (cached is Map) {
        if (entry!.fresh) {
          return HomeFeed.fromJson(cached.cast<String, dynamic>());
        }
        // Stale but recent: paint it now and let the controller revalidate,
        // which turns the post-TTL open from a network wait into a disk read.
        if (canServeStale(expiresAt: entry.expiresAt, now: DateTime.now())) {
          servedStale = true;
          return HomeFeed.fromJson(cached.cast<String, dynamic>());
        }
      }
    }
    return _fetch(refresh: refresh, fallbackToCache: true);
  }

  /// Refreshes the cache behind an already-painted stale feed.
  Future<HomeFeed> revalidate() =>
      _fetch(refresh: false, fallbackToCache: false);

  Future<HomeFeed> _fetch({
    required bool refresh,
    required bool fallbackToCache,
  }) async {
    try {
      final json = await _api.getMap(
        ApiEndpoints.home,
        query: {'refresh': refresh},
      );
      await _store.putCached('home', json, ttl: AppConfig.metadataCacheTtl);
      return HomeFeed.fromJson(json);
    } catch (_) {
      if (fallbackToCache) {
        final cached = _store.readCacheEntry('home')?.value;
        if (cached is Map) {
          return HomeFeed.fromJson(cached.cast<String, dynamic>());
        }
      }
      rethrow;
    }
  }

  /// Whether an entry that lapsed at [expiresAt] is still recent enough to
  /// paint before revalidating. A clock that moved backwards leaves
  /// [expiredFor] negative, which reads as not-yet-expired and is safe.
  static bool canServeStale({required int expiresAt, required DateTime now}) {
    final expiredFor = now.millisecondsSinceEpoch - expiresAt;
    return expiredFor <= _maxStaleAge.inMilliseconds;
  }

  Future<(List<MusicItem>, String?)> more(String cursor) async {
    final json = await _api.getMap(
      ApiEndpoints.recommendations,
      query: {'cursor': cursor, 'limit': 25},
    );
    final data = json['data'];
    final items = data is List
        ? data
              .whereType<Map>()
              .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
        : const <MusicItem>[];
    return (items, json['next_cursor']?.toString());
  }
}
