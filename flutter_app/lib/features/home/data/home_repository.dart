import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/config/app_config.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/home_feed.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class HomeRepository {
  HomeRepository(this._api, this._store);

  static const _indexKey = 'home:index';
  static String _sectionKey(String id) => 'home:section:$id';

  final ApiClient _api;
  final LocalStore _store;

  /// Whatever was cached last, rebuilt row by row so a cold start can paint
  /// Home before the network answers.
  HomeFeed cached() {
    final index = _store.readCached(_indexKey);
    if (index is! List) return HomeFeed.empty;
    final sections = <HomeSection>[];
    for (final id in index.map((value) => value.toString())) {
      final section = _readSection(id);
      if (section != null && section.items.isNotEmpty) sections.add(section);
    }
    return HomeFeed(sections: sections);
  }

  /// Always talks to the server. Callers paint [cached] first, so there is no
  /// reason to short-circuit here: that only froze Home until the cache TTL
  /// expired. [refresh] asks the backend to recompute rather than serve its
  /// own cached ranking.
  Future<HomeFeed> load({bool refresh = false}) async {
    final json = await _api.getMap(
      ApiEndpoints.home,
      query: {'refresh': refresh},
    );
    final fresh = HomeFeed.fromJson(json);
    final merged = _mergeWithCache(fresh);
    await _writeCache(merged);
    return merged;
  }

  /// Rows the response did not carry keep the copy we already had.
  ///
  /// The backend builds each row from an independent source and returns an
  /// empty list for the ones that failed, so an albums outage must not blank
  /// the albums row while songs and artists arrive fine.
  HomeFeed _mergeWithCache(HomeFeed fresh) {
    final stored = cached();
    if (stored.sections.isEmpty) return fresh;
    final sections = <HomeSection>[];
    final used = <String>{};
    for (final section in fresh.sections) {
      used.add(section.id);
      sections.add(section);
    }
    for (final section in stored.sections) {
      if (used.contains(section.id)) continue;
      sections.add(section);
    }
    return HomeFeed(
      sections: diversifySections(sections),
      nextCursor: fresh.nextCursor,
    );
  }

  Future<void> _writeCache(HomeFeed feed) async {
    for (final section in feed.sections) {
      if (section.items.isEmpty) continue;
      await _store.putCached(_sectionKey(section.id), {
        'id': section.id,
        'title': section.title,
        'content_type': section.contentType.name,
        'items': section.items
            .map((item) => item.toJson())
            .toList(growable: false),
      }, ttl: AppConfig.metadataCacheTtl);
    }
    await _store.putCached(
      _indexKey,
      feed.sections.map((section) => section.id).toList(growable: false),
      ttl: AppConfig.metadataCacheTtl,
    );
  }

  HomeSection? _readSection(String id) {
    final value = _store.readCached(_sectionKey(id));
    if (value is! Map) return null;
    final json = value.cast<String, dynamic>();
    final items = json['items'];
    if (items is! List) return null;
    return HomeSection.build(
      id: id,
      title: json['title']?.toString() ?? 'Music',
      contentType: musicItemTypeFrom(json['content_type']),
      items: items
          .whereType<Map>()
          .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
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
