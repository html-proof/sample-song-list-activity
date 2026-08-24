import 'dart:async';

import 'package:dio/dio.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class SearchResults {
  const SearchResults({
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
  });

  final List<MusicItem> songs;
  final List<MusicItem> artists;
  final List<MusicItem> albums;

  bool get isEmpty => songs.isEmpty && artists.isEmpty && albums.isEmpty;
}

class SearchRepository {
  SearchRepository(this._api, this._store);

  final ApiClient _api;
  final LocalStore _store;

  List<String> recent() => _store.recentSearches();

  Future<SearchResults> search(
    String query,
    String type, {
    CancelToken? cancelToken,
  }) async {
    final response = await _api.getMap(
      ApiEndpoints.search,
      query: {'q': query, 'type': type, 'limit': 20},
      cancelToken: cancelToken,
    );
    await _store.addRecentSearch(query);
    return SearchResults(
      songs: _items(response['songs']),
      artists: _items(response['artists']),
      albums: _items(response['albums']),
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

  List<MusicItem> _items(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false)
      : const [];
}
