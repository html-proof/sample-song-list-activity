import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/features/search/data/search_repository.dart';
import 'package:music_hub_app/features/search/presentation/search_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

/// Returns whatever the test hands it, so repository parsing can be exercised
/// without a network.
class FakeApiClient implements ApiClient {
  FakeApiClient(this.response);

  Map<String, dynamic> response;
  Map<String, dynamic>? lastQuery;

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    lastQuery = query;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeLocalStore implements LocalStore {
  final List<String> searches = [];

  @override
  List<String> recentSearches() => searches;

  @override
  Future<void> addRecentSearch(String query) async => searches.add(query);

  @override
  Future<void> removeRecentSearch(String query) async => searches.remove(query);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Holds every search open so a test can choose the order they resolve in.
class FakeSearchRepository implements SearchRepository {
  final List<String> calls = [];
  final List<SearchCategory> categories = [];
  final Map<String, Completer<SearchResults>> pending = {};

  @override
  Future<SearchResults> search(
    String query,
    SearchCategory category, {
    CancelToken? cancelToken,
  }) {
    calls.add(query);
    categories.add(category);
    final completer = Completer<SearchResults>();
    pending[query] = completer;
    return completer.future;
  }

  void resolve(String query, SearchResults results) =>
      pending.remove(query)!.complete(results);

  void fail(String query, Object error) =>
      pending.remove(query)!.completeError(error, StackTrace.empty);

  @override
  List<String> recent() => const [];

  @override
  Future<void> removeRecent(String query) async {}

  @override
  void recordClick(String query, MusicItem item) {}
}

SearchResults resultsWith({List<MusicItem> songs = const []}) =>
    SearchResults(songs: songs);

MusicItem song(String id, String title) => MusicItem.fromJson({
  'type': 'song',
  'track_id': id,
  'title': title,
});

void main() {
  group('classification', () {
    test('the declared type wins over the fields that happen to be present', () {
      // An album carries an artist just as a song does, and a song carries an
      // album id just as an album does. Only the declared type separates them.
      final album = MusicItem.fromJson({
        'type': 'album',
        'album_id': '10',
        'track_id': '99',
        'title': 'Roja',
        'artists': 'A. R. Rahman',
      });
      final track = MusicItem.fromJson({
        'type': 'song',
        'track_id': '1',
        'album_id': '10',
        'title': 'Pattalam',
        'artists': 'Vidyasagar',
      });

      expect(album.type, MusicItemType.album);
      expect(track.type, MusicItemType.song);
    });

    test('a playlist is not read as an album because it has a track count', () {
      final playlist = MusicItem.fromJson({
        'type': 'playlist',
        'playlist_id': '4',
        'title': 'Malayalam Hits',
        'track_count': '50',
      });

      expect(playlist.type, MusicItemType.playlist);
      expect(playlist.songCount, 50);
      expect(playlist.typeLabel, 'Playlist');
    });

    test('an artist is never read as a song', () {
      final artist = MusicItem.fromJson({
        'type': 'artist',
        'artist_id': '3',
        'name': 'A. R. Rahman',
      });

      expect(artist.type, MusicItemType.artist);
      expect(artist.typeLabel, 'Artist');
    });

    test('field inference still covers endpoints that declare no type', () {
      final legacy = MusicItem.fromJson({'track_id': '1', 'title': 'Legacy'});

      expect(legacy.type, MusicItemType.song);
    });
  });

  group('repository', () {
    test('each group keeps only results of its own type', () async {
      final api = FakeApiClient({
        'query': 'pattalam',
        'songs': [
          {'type': 'song', 'track_id': '1', 'title': 'Pattalam'},
          // A mis-grouped album must not be shown under Songs.
          {'type': 'album', 'album_id': '2', 'title': 'Pattalam'},
        ],
        'artists': [
          {'type': 'artist', 'artist_id': '3', 'name': 'Vidyasagar'},
        ],
        'albums': [
          {'type': 'album', 'album_id': '4', 'title': 'Pattalam'},
        ],
        'playlists': [
          {'type': 'playlist', 'playlist_id': '5', 'title': 'Hits'},
        ],
      });
      final repository = SearchRepository(api, FakeLocalStore());

      final results = await repository.search('pattalam', SearchCategory.all);

      expect(results.songs.map((item) => item.id), ['1']);
      expect(results.artists.map((item) => item.id), ['3']);
      expect(results.albums.map((item) => item.id), ['4']);
      expect(results.playlists.map((item) => item.id), ['5']);
      expect(api.lastQuery!['type'], 'all');
    });

    test('the top result keeps whatever type it came back as', () async {
      final api = FakeApiClient({
        'top_result': {
          'type': 'artist',
          'artist_id': '3',
          'name': 'Arijit Singh',
        },
      });
      final repository = SearchRepository(api, FakeLocalStore());

      final results = await repository.search(
        'arijit singh',
        SearchCategory.all,
      );

      expect(results.topResult!.type, MusicItemType.artist);
    });

    test('a tab asks the backend for that category', () async {
      final api = FakeApiClient({});
      final repository = SearchRepository(api, FakeLocalStore());

      await repository.search('hits', SearchCategory.playlists);

      expect(api.lastQuery!['type'], 'playlists');
    });
  });

  group('result grouping', () {
    final results = SearchResults(
      songs: [song('1', 'Pattalam')],
      artists: [
        MusicItem.fromJson({'type': 'artist', 'artist_id': '2', 'name': 'V'}),
      ],
    );

    test('a category reads only its own list', () {
      expect(results.of(MusicItemType.song).length, 1);
      expect(results.of(MusicItemType.album), isEmpty);
    });

    test('emptiness is judged per tab, not across everything', () {
      expect(results.isEmptyFor(SearchCategory.all), isFalse);
      expect(results.isEmptyFor(SearchCategory.songs), isFalse);
      expect(results.isEmptyFor(SearchCategory.albums), isTrue);
      expect(results.isEmptyFor(SearchCategory.playlists), isTrue);
    });
  });

  group('controller', () {
    test('a slow earlier response never replaces a newer one', () {
      fakeAsync((async) {
        final repository = FakeSearchRepository();
        final controller = SearchController(repository);

        controller.queryChanged('ari');
        async.elapse(const Duration(milliseconds: 400));
        controller.queryChanged('arijit');
        async.elapse(const Duration(milliseconds: 400));

        expect(repository.calls, ['ari', 'arijit']);

        // The newer query answers first, then the stale one arrives.
        repository.resolve('arijit', resultsWith(songs: [song('2', 'Newer')]));
        async.flushMicrotasks();
        repository.resolve('ari', resultsWith(songs: [song('1', 'Stale')]));
        async.flushMicrotasks();

        expect(
          controller.state.results.requireValue.songs.single.title,
          'Newer',
        );
        controller.dispose();
      });
    });

    test('results stay on screen while the next query loads', () {
      fakeAsync((async) {
        final repository = FakeSearchRepository();
        final controller = SearchController(repository);

        controller.queryChanged('arij');
        async.elapse(const Duration(milliseconds: 400));
        repository.resolve('arij', resultsWith(songs: [song('1', 'First')]));
        async.flushMicrotasks();

        controller.queryChanged('arijit');
        async.elapse(const Duration(milliseconds: 400));

        // Mid-flight: still loading, but the previous results are intact so the
        // list does not blank out between keystrokes.
        expect(controller.state.results.isLoading, isTrue);
        expect(controller.state.refreshing, isTrue);
        expect(
          controller.state.results.requireValue.songs.single.title,
          'First',
        );
        controller.dispose();
      });
    });

    test('rapid typing spends one request, not one per character', () {
      fakeAsync((async) {
        final repository = FakeSearchRepository();
        final controller = SearchController(repository);

        for (final query in ['ar', 'ari', 'arij', 'ariji', 'arijit']) {
          controller.queryChanged(query);
          async.elapse(const Duration(milliseconds: 50));
        }
        async.elapse(const Duration(milliseconds: 400));

        expect(repository.calls, ['arijit']);
        controller.dispose();
      });
    });

    test('clearing the query restores the landing state', () {
      fakeAsync((async) {
        final repository = FakeSearchRepository();
        final controller = SearchController(repository);

        controller.queryChanged('arijit');
        async.elapse(const Duration(milliseconds: 400));
        controller.queryChanged('');
        async.flushMicrotasks();

        expect(controller.state.results.requireValue.isEmpty, isTrue);

        // A response for the abandoned query must not repopulate the landing
        // screen behind the user's back.
        repository.resolve('arijit', resultsWith(songs: [song('1', 'Late')]));
        async.flushMicrotasks();

        expect(controller.state.results.requireValue.isEmpty, isTrue);
        controller.dispose();
      });
    });

    test('switching tabs re-runs the query for that category', () {
      fakeAsync((async) {
        final repository = FakeSearchRepository();
        final controller = SearchController(repository);

        controller.queryChanged('arijit');
        async.elapse(const Duration(milliseconds: 400));
        repository.resolve('arijit', resultsWith());
        async.flushMicrotasks();

        controller.selectCategory(SearchCategory.artists);
        async.flushMicrotasks();

        expect(repository.categories, [
          SearchCategory.all,
          SearchCategory.artists,
        ]);
        controller.dispose();
      });
    });

    test('a failed search surfaces an error and can be retried', () {
      fakeAsync((async) {
        final repository = FakeSearchRepository();
        final controller = SearchController(repository);

        controller.queryChanged('arijit');
        async.elapse(const Duration(milliseconds: 400));
        repository.fail('arijit', StateError('provider down'));
        async.flushMicrotasks();

        expect(controller.state.results.hasError, isTrue);

        controller.retry();
        async.flushMicrotasks();

        expect(repository.calls, ['arijit', 'arijit']);
        controller.dispose();
      });
    });
  });
}
