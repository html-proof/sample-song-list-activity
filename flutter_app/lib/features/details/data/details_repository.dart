import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/config/app_config.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class MusicDetails {
  const MusicDetails({
    required this.item,
    this.tracks = const [],
    this.related = const [],
  });

  final MusicItem item;
  final List<MusicItem> tracks;
  final List<MusicItem> related;
}

class DetailsRepository {
  DetailsRepository(this._api, this._store);

  final ApiClient _api;
  final LocalStore _store;

  Future<MusicDetails> artist(String seokey) {
    return _details(
      cacheKey: 'artist_detail:$seokey',
      path: '${ApiEndpoints.artists}/$seokey',
      tracksKey: 'top_tracks',
    );
  }

  Future<MusicDetails> album(String seokey) {
    return _details(
      cacheKey: 'album_detail:$seokey',
      path: '${ApiEndpoints.albums}/$seokey',
      tracksKey: 'tracks',
    );
  }

  /// A provider playlist returns its tracks rather than a metadata object, so
  /// the header comes from the card the user tapped and only the track list is
  /// fetched. A playlist seokey is never a song or album id and must not be
  /// handed to those endpoints.
  Future<List<MusicItem>> playlistTracks(String seokey) async {
    final cacheKey = 'playlist_tracks:$seokey';
    final cached = _store.readCached(cacheKey);
    if (cached is List) return _items(cached);
    final response = await _api.getMap(
      '${ApiEndpoints.playlists}/provider/$seokey',
    );
    final data = response['data'];
    if (data is List) {
      await _store.putCached(cacheKey, data, ttl: AppConfig.metadataCacheTtl);
    }
    return _items(data);
  }

  /// Similar items are fetched separately because the endpoint needs the id
  /// from the primary response. Loading them inline made every detail page
  /// wait for two sequential round trips before it could paint anything.
  Future<List<MusicItem>> artistRelated(String id) {
    return _related(
      cacheKey: 'artist_related:$id',
      path: '${ApiEndpoints.artists}/id/$id/similar',
      id: id,
    );
  }

  Future<List<MusicItem>> albumRelated(String id) {
    return _related(
      cacheKey: 'album_related:$id',
      path: '${ApiEndpoints.albums}/id/$id/similar',
      id: id,
    );
  }

  Future<MusicDetails> _details({
    required String cacheKey,
    required String path,
    required String tracksKey,
  }) async {
    final cached = _store.readCached(cacheKey);
    if (cached is Map) {
      final body = cached.cast<String, dynamic>();
      return MusicDetails(
        item: MusicItem.fromJson(body),
        tracks: _items(body[tracksKey]),
      );
    }
    final body = await _api.getMap(path);
    await _store.putCached(cacheKey, body, ttl: AppConfig.metadataCacheTtl);
    return MusicDetails(
      item: MusicItem.fromJson(body),
      tracks: _items(body[tracksKey]),
    );
  }

  Future<List<MusicItem>> _related({
    required String cacheKey,
    required String path,
    required String id,
  }) async {
    if (id.isEmpty) return const [];
    final cached = _store.readCached(cacheKey);
    if (cached is List) return _items(cached);
    try {
      final response = await _api.getMap(path);
      final data = response['data'];
      if (data is List) {
        await _store.putCached(cacheKey, data, ttl: AppConfig.metadataCacheTtl);
      }
      return _items(data);
    } catch (_) {
      // Related content should never prevent the primary page from loading.
      return const [];
    }
  }

  List<MusicItem> _items(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => MusicItem.fromJson(entry.cast<String, dynamic>()))
            .toList(growable: false)
      : const [];
}
