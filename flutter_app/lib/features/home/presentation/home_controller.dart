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
  HomeController(this._repository) : super(const AsyncLoading());

  final HomeRepository _repository;
  bool loadingMore = false;

  Future<void> load({bool refresh = false}) async {
    if (refresh || !state.hasValue) state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository.load(refresh: refresh));
  }

  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || loadingMore) return;
    loadingMore = true;
    try {
      final (items, nextCursor) = await _repository.more(cursor);
      final sections = [...current.sections];
      final index = sections.indexWhere(
        (section) => section.type == 'recommended_for_you',
      );
      if (index >= 0) {
        final old = sections[index];
        sections[index] = HomeSection(
          type: old.type,
          title: old.title,
          items: [...old.items, ...items],
        );
      }
      state = AsyncData(HomeFeed(sections: sections, nextCursor: nextCursor));
    } finally {
      loadingMore = false;
    }
  }
}
