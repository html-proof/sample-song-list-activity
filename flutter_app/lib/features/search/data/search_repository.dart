import 'dart:async';

import 'package:dio/dio.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

/// The search tabs, and the value each one sends as the `type` query
/// parameter. Kept as an enum so a tab can never be compared against a typo'd
/// string, and so the tab filter and the request always agree.
enum SearchCategory { all, songs, artists, albums, playlists }

extension SearchCategoryX on SearchCategory {
  String get wire => name;

  String get label => switch (this) {
    SearchCategory.all => 'All',
    SearchCategory.songs => 'Songs',
    SearchCategory.artists => 'Artists',
    SearchCategory.albums => 'Albums',
    SearchCategory.playlists => 'Playlists',
  };

  /// The content type this tab shows, or null for the mixed tab.
  MusicItemType? get itemType => switch (this) {
    SearchCategory.all => null,
    SearchCategory.songs => MusicItemType.song,
    SearchCategory.artists => MusicItemType.artist,
    SearchCategory.albums => MusicItemType.album,
    SearchCategory.playlists => MusicItemType.playlist,
  };
}

/// Results are held in one list per content type rather than a single mixed
/// list, so nothing downstream ever has to work out what a result is.
class SearchResults {
  const SearchResults({
    this.query = '',
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.topResult,
  });

  final String query;
  final List<MusicItem> songs;
  final List<MusicItem> artists;
  final List<MusicItem> albums;
  final List<MusicItem> playlists;

  /// The single strongest match, whatever type it turned out to be. Never
  /// assumed to be a song.
  final MusicItem? topResult;

  bool get isEmpty =>
      songs.isEmpty &&
      artists.isEmpty &&
      albums.isEmpty &&
      playlists.isEmpty;

  List<MusicItem> of(MusicItemType type) => switch (type) {
    MusicItemType.song => songs,
    MusicItemType.artist => artists,
    MusicItemType.album => albums,
    MusicItemType.playlist => playlists,
    MusicItemType.unknown => const [],
  };

  /// True when the given tab has nothing to show, used to pick between the
  /// "no results" copy and a per-category empty state.
  bool isEmptyFor(SearchCategory category) {
    final type = category.itemType;
    return type == null ? isEmpty : of(type).isEmpty;
  }
}

class SearchRepository {
  SearchRepository(this._api, this._store);

  final ApiClient _api;
  final LocalStore _store;

  List<String> recent() => _store.recentSearches();

  Future<SearchResults> search(
    String query,
    SearchCategory category, {
    CancelToken? cancelToken,
  }) async {
    final response = await _api.getMap(
      ApiEndpoints.search,
      query: {'q': query, 'type': category.wire, 'limit': 20},
      cancelToken: cancelToken,
    );
    await _store.addRecentSearch(query);
    // Each group is filtered by the type the backend declared, so a
    // mis-grouped result is dropped rather than shown under the wrong heading.
    return SearchResults(
      query: (response['query'] ?? query).toString(),
      songs: _items(response['songs'], MusicItemType.song),
      artists: _items(response['artists'], MusicItemType.artist),
      albums: _items(response['albums'], MusicItemType.album),
      playlists: _items(response['playlists'], MusicItemType.playlist),
      topResult: _topResult(response['top_result']),
    );
  }

  Future<void> removeRecent(String query) => _store.removeRecentSearch(query);

  void recordClick(String query, MusicItem item) {
    unawaited(
      _api
          .post(
            ApiEndpoints.searchEvents,
            data: {
              'query': query,
              'result_type': item.type.name,
              'clicked_result_id': item.id,
            },
          )
          .catchError((_) => null),
    );
  }

  List<MusicItem> _items(dynamic value, MusicItemType expected) => value is List
      ? value
            .whereType<Map>()
            .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
            .where((item) => item.type == expected)
            .toList(growable: false)
      : const [];

  MusicItem? _topResult(dynamic value) {
    if (value is! Map) return null;
    final item = MusicItem.fromJson(value.cast<String, dynamic>());
    return item.type == MusicItemType.unknown ? null : item;
  }
}
