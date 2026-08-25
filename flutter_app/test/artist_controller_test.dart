import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/features/artists/data/artist_repository.dart';
import 'package:music_hub_app/features/artists/presentation/artist_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

MusicItem artist(String id, String name) =>
    MusicItem.fromJson({'artist_id': id, 'artist_name': name, 'seokey': name});

/// Stands in for the network. Search calls are held open so a test can decide
/// the order in which they resolve.
class FakeArtistRepository implements ArtistRepository {
  FakeArtistRepository({this.cached, this.pages = const []});

  final List<MusicItem>? cached;
  final List<ArtistPage> pages;

  final List<String> searchCalls = [];
  final Map<String, Completer<List<MusicItem>>> pending = {};
  int recommendedCalls = 0;
  Object? recommendedError;

  @override
  List<MusicItem>? cachedRecommendations() => cached;

  @override
  Future<ArtistPage> recommended({String? cursor, int limit = 30}) async {
    if (recommendedError != null) throw recommendedError!;
    final page = pages.isEmpty
        ? const ArtistPage()
        : pages[recommendedCalls.clamp(0, pages.length - 1)];
    recommendedCalls++;
    return page;
  }

  @override
  Future<List<MusicItem>> search(String query, {int limit = 25}) {
    searchCalls.add(query);
    final completer = Completer<List<MusicItem>>();
    pending[query] = completer;
    return completer.future;
  }

  void resolve(String query, List<MusicItem> results) {
    pending.remove(query)!.complete(results);
  }

  @override
  Future<List<MusicItem>> related(String artistId, {int limit = 20}) async =>
      const [];
}

void main() {
  group('recommendations', () {
    test('cached artists are shown before the network answers', () {
      final repository = FakeArtistRepository(
        cached: [artist('1', 'Cached')],
        pages: [
          ArtistPage(artists: [artist('2', 'Fresh')]),
        ],
      );
      final controller = ArtistController(repository)..start();

      // No await: this is the first synchronous frame after opening.
      expect(controller.state.recommendations.single.title, 'Cached');
      expect(controller.state.loadingRecommendations, isFalse);
      controller.dispose();
    });

    test('a fresh list replaces the cached one once it arrives', () async {
      final repository = FakeArtistRepository(
        cached: [artist('1', 'Cached')],
        pages: [
          ArtistPage(artists: [artist('2', 'Fresh')]),
        ],
      );
      final controller = ArtistController(repository)..start();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.recommendations.single.title, 'Fresh');
      controller.dispose();
    });

    test('with nothing cached the screen reports that it is loading', () {
      final controller = ArtistController(FakeArtistRepository())..start();
      expect(controller.state.loadingRecommendations, isTrue);
      controller.dispose();
    });

    test(
      'a failed refresh keeps the cached list and raises no error',
      () async {
        final repository = FakeArtistRepository(cached: [artist('1', 'Cached')])
          ..recommendedError = StateError('offline');
        final controller = ArtistController(repository)..start();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.recommendations.single.title, 'Cached');
        expect(controller.state.error, isNull);
        controller.dispose();
      },
    );

    test('a failure with nothing cached surfaces the error', () async {
      final repository = FakeArtistRepository()
        ..recommendedError = StateError('offline');
      final controller = ArtistController(repository)..start();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.error, isNotNull);
      controller.dispose();
    });
  });

  group('paging', () {
    test('the next page is appended, never replacing what is shown', () async {
      final repository = FakeArtistRepository(
        pages: [
          ArtistPage(artists: [artist('1', 'One')], nextCursor: 'c1'),
          ArtistPage(artists: [artist('2', 'Two')]),
        ],
      );
      final controller = ArtistController(repository)..start();
      await Future<void>.delayed(Duration.zero);
      await controller.loadMore();

      expect(controller.state.recommendations.map((item) => item.title), [
        'One',
        'Two',
      ]);
      expect(controller.state.hasMore, isFalse);
      controller.dispose();
    });

    test('an artist already on screen is not appended twice', () async {
      final repository = FakeArtistRepository(
        pages: [
          ArtistPage(artists: [artist('1', 'One')], nextCursor: 'c1'),
          ArtistPage(artists: [artist('1', 'One'), artist('2', 'Two')]),
        ],
      );
      final controller = ArtistController(repository)..start();
      await Future<void>.delayed(Duration.zero);
      await controller.loadMore();

      expect(controller.state.recommendations.length, 2);
      controller.dispose();
    });

    test('loadMore does nothing without a cursor', () async {
      final repository = FakeArtistRepository(
        pages: [
          ArtistPage(artists: [artist('1', 'One')]),
        ],
      );
      final controller = ArtistController(repository)..start();
      await Future<void>.delayed(Duration.zero);
      final before = repository.recommendedCalls;
      await controller.loadMore();

      expect(repository.recommendedCalls, before);
      controller.dispose();
    });
  });

  group('search', () {
    test('typing is debounced into a single request', () {
      fakeAsync((async) {
        final repository = FakeArtistRepository();
        final controller = ArtistController(repository)..start();

        for (final value in ['a', 'ar', 'ari', 'arij', 'ariji', 'arijit']) {
          controller.onQueryChanged(value);
        }
        async.elapse(const Duration(milliseconds: 299));
        expect(repository.searchCalls, isEmpty);

        async.elapse(const Duration(milliseconds: 2));
        expect(repository.searchCalls, ['arijit']);
        controller.dispose();
      });
    });

    test('a stale reply never overwrites a newer one', () async {
      final repository = FakeArtistRepository();
      final controller = ArtistController(repository)..start();

      // Both requests are in flight; the older one finishes last.
      unawaited(controller.search('ari'));
      unawaited(controller.search('arijit'));

      repository.resolve('arijit', [artist('1', 'Arijit Singh')]);
      await Future<void>.delayed(Duration.zero);
      repository.resolve('ari', [artist('9', 'Stale result')]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.searchResults.single.title, 'Arijit Singh');
      controller.dispose();
    });

    test('clearing the query drops the old results immediately', () async {
      final repository = FakeArtistRepository();
      final controller = ArtistController(repository)..start();

      unawaited(controller.search('arijit'));
      repository.resolve('arijit', [artist('1', 'Arijit Singh')]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.searchResults, isNotEmpty);

      controller.onQueryChanged('   ');

      expect(controller.state.searchResults, isEmpty);
      expect(controller.state.mode, ArtistMode.recommendations);
      controller.dispose();
    });

    test(
      'an in-flight search cannot land after the query is cleared',
      () async {
        final repository = FakeArtistRepository();
        final controller = ArtistController(repository)..start();

        unawaited(controller.search('arijit'));
        controller.cancelSearch();
        repository.resolve('arijit', [artist('1', 'Arijit Singh')]);
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.searchResults, isEmpty);
        expect(controller.state.mode, ArtistMode.recommendations);
        controller.dispose();
      },
    );

    test(
      'recommendations survive a search and return when it is cleared',
      () async {
        final repository = FakeArtistRepository(
          pages: [
            ArtistPage(artists: [artist('1', 'Recommended')]),
          ],
        );
        final controller = ArtistController(repository)..start();
        await Future<void>.delayed(Duration.zero);

        unawaited(controller.search('arijit'));
        repository.resolve('arijit', [artist('2', 'Arijit Singh')]);
        await Future<void>.delayed(Duration.zero);
        controller.cancelSearch();

        expect(controller.state.recommendations.single.title, 'Recommended');
        controller.dispose();
      },
    );
  });
}
