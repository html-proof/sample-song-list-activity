import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/config/app_config.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/home_feed.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class HomeRepository {
  HomeRepository(this._api, this._store);

  final ApiClient _api;
  final LocalStore _store;

  Future<HomeFeed> load({bool refresh = false}) async {
    if (!refresh) {
      final cached = _store.readCached('home');
      if (cached is Map) {
        return HomeFeed.fromJson(cached.cast<String, dynamic>());
      }
    }
    try {
      final json = await _api.getMap(
        ApiEndpoints.home,
        query: {'refresh': refresh},
      );
      await _store.putCached('home', json, ttl: AppConfig.metadataCacheTtl);
      return HomeFeed.fromJson(json);
    } catch (_) {
      final cached = _store.readCached('home');
      if (cached is Map) {
        return HomeFeed.fromJson(cached.cast<String, dynamic>());
      }
      rethrow;
    }
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
