import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/home/data/home_repository.dart';
import 'package:music_hub_app/shared/models/home_feed.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
  );
});

final homeControllerProvider =
    StateNotifierProvider<HomeController, AsyncValue<HomeFeed>>((ref) {
      return HomeController(ref.watch(homeRepositoryProvider))..load();
    });

class HomeController extends StateNotifier<AsyncValue<HomeFeed>> {
  HomeController(this._repository) : super(const AsyncLoading()) {
    // Paint whatever the last session cached before the first request lands,
    // so a cold start shows Home immediately and never blocks on the network.
    final cached = _repository.cached();
    if (cached.sections.isNotEmpty) state = AsyncData(cached);
  }

  /// Rows that grow as the user scrolls. Everything else is a fixed-size row
  /// served whole by the feed.
  static const _paginatedSectionIds = [
    'more_for_you',
    'recommended_for_you',
    'trending',
  ];

  final HomeRepository _repository;
  bool loadingMore = false;

  /// Guards against a slow response overwriting a newer one.
  int _generation = 0;

  Future<void> load({bool refresh = false}) async {
    final generation = ++_generation;
    final previous = state.value;
    // Stale-while-revalidate: the rows already on screen stay on screen while
    // the refresh runs, so pull-to-refresh never blanks Home.
    state = previous == null
        ? const AsyncLoading<HomeFeed>()
        : AsyncLoading<HomeFeed>().copyWithPrevious(AsyncData(previous));

    final result = await AsyncValue.guard(
      () => _repository.load(refresh: refresh),
    );
    if (generation != _generation) return;
    if (result.hasError && previous != null) {
      // A failed refresh must not throw away rows the user can still use.
      state = AsyncData(previous);
      return;
    }
    state = result;
  }

  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || loadingMore) return;
    final target = _paginatedSectionIds
        .map(current.sectionById)
        .where((section) => section != null)
        .cast<HomeSection>()
        .firstOrNull;
    if (target == null) return;

    loadingMore = true;
    final generation = _generation;
    try {
      final (items, nextCursor) = await _repository.more(cursor);
      // A refresh that started after this page was requested owns the state.
      if (generation != _generation) return;
      final latest = state.value;
      final section = latest?.sectionById(target.id);
      if (latest == null || section == null) return;

      // Dedupe against what the row already holds, so a repeated cursor or an
      // overlapping page cannot duplicate the first page's cards.
      final merged = dedupeItems([
        ...section.items,
        ...items.where((item) => item.type == section.contentType),
      ]);
      if (merged.length == section.items.length && nextCursor == cursor) {
        // The page added nothing new and the cursor did not move: stop, rather
        // than spinning on the same request forever.
        state = AsyncData(
          HomeFeed(sections: latest.sections, nextCursor: null),
        );
        return;
      }
      final sections = latest.sections
          .map(
            (entry) =>
                entry.id == section.id ? entry.copyWith(items: merged) : entry,
          )
          .toList(growable: false);
      state = AsyncData(HomeFeed(sections: sections, nextCursor: nextCursor));
    } catch (_) {
      // Pagination failing leaves the rows already on screen untouched.
    } finally {
      loadingMore = false;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
