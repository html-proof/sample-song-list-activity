import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
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
  DetailsRepository(this._api);

  final ApiClient _api;

  Future<MusicDetails> artist(String seokey) async {
    final body = await _api.getMap('${ApiEndpoints.artists}/$seokey');
    final item = MusicItem.fromJson(body);
    final tracks = _items(body['top_tracks']);
    var related = const <MusicItem>[];
    if (item.id.isNotEmpty) {
      try {
        final response = await _api.getMap(
          '${ApiEndpoints.artists}/id/${item.id}/similar',
        );
        related = _items(response['data']);
      } catch (_) {
        // Related content should never prevent the primary page from loading.
      }
    }
    return MusicDetails(item: item, tracks: tracks, related: related);
  }

  Future<MusicDetails> album(String seokey) async {
    final body = await _api.getMap('${ApiEndpoints.albums}/$seokey');
    final item = MusicItem.fromJson(body);
    final tracks = _items(body['tracks']);
    var related = const <MusicItem>[];
    if (item.id.isNotEmpty) {
      try {
        final response = await _api.getMap(
          '${ApiEndpoints.albums}/id/${item.id}/similar',
        );
        related = _items(response['data']);
      } catch (_) {
        // Related content is optional.
      }
    }
    return MusicDetails(item: item, tracks: tracks, related: related);
  }

  List<MusicItem> _items(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => MusicItem.fromJson(entry.cast<String, dynamic>()))
            .toList(growable: false)
      : const [];
}
