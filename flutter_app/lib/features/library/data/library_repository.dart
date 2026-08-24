import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class LibraryData {
  const LibraryData({
    this.likedSongs = const [],
    this.artists = const [],
    this.playlists = const [],
    this.recent = const [],
  });

  final List<MusicItem> likedSongs;
  final List<MusicItem> artists;
  final List<Map<String, dynamic>> playlists;
  final List<MusicItem> recent;
}

class LibraryRepository {
  LibraryRepository(this._api);

  final ApiClient _api;

  Future<LibraryData> load() async {
    final values = await Future.wait<dynamic>([
      _api.get(ApiEndpoints.libraryLikes),
      _api.get(ApiEndpoints.libraryArtists),
      _api.get(ApiEndpoints.playlists),
      _api.get(ApiEndpoints.historyRecent),
    ]);
    return LibraryData(
      likedSongs: _items(_data(values[0])),
      artists: _items(_data(values[1])),
      playlists: values[2] is List
          ? (values[2] as List)
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList(growable: false)
          : const [],
      recent: _items(_data(values[3])),
    );
  }

  Future<void> like(MusicItem item) async {
    await _api.put(
      '${ApiEndpoints.libraryLikes}/${item.id}',
      data: {
        'provider': 'gaana',
        'song_id': item.id,
        'seokey': item.seokey,
        'song_name': item.title,
        'artist_id': item.raw['artist_ids']?.toString().split(',').first.trim(),
        'artist_name': item.subtitle,
        'album_id': item.raw['album_id']?.toString(),
        'language': item.raw['language']?.toString(),
        'artwork_url': item.imageUrl,
      },
    );
  }

  Future<void> unlike(String songId) =>
      _api.delete('${ApiEndpoints.libraryLikes}/$songId');

  Future<void> follow(MusicItem artist) async {
    await _api.put(
      '${ApiEndpoints.libraryArtists}/${artist.id}',
      data: {
        'provider': 'gaana',
        'artist_id': artist.id,
        'artist_name': artist.title,
        'artwork_url': artist.imageUrl,
        'notifications_enabled': true,
      },
    );
  }

  Future<void> createPlaylist(String name, String? description) async {
    await _api.post(
      ApiEndpoints.playlists,
      data: {'name': name, 'description': description, 'is_public': false},
    );
  }

  dynamic _data(dynamic response) => response is Map ? response['data'] : null;

  List<MusicItem> _items(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false)
      : const [];
}
