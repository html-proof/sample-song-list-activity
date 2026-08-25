import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/config/app_config.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/search/data/search_repository.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
  );
});

final searchControllerProvider =
    StateNotifierProvider<SearchController, SearchState>((ref) {
      return SearchController(ref.watch(searchRepositoryProvider));
    });

/// Below this the landing screen is shown instead of results.
const _minimumQueryLength = 2;

class SearchState {
  const SearchState({
    this.query = '',
    this.category = SearchCategory.all,
    this.results = const AsyncData(SearchResults()),
    this.recent = const [],
  });

  final String query;
  final SearchCategory category;
  final AsyncValue<SearchResults> results;
  final List<String> recent;

  /// True while a request is in flight over results that are already on
  /// screen, so the view can show a thin progress hint instead of tearing the
  /// list down and rebuilding it.
  bool get refreshing => results.isLoading && results.hasValue;

  SearchState copyWith({
    String? query,
    SearchCategory? category,
    AsyncValue<SearchResults>? results,
    List<String>? recent,
  }) => SearchState(
    query: query ?? this.query,
    category: category ?? this.category,
    results: results ?? this.results,
    recent: recent ?? this.recent,
  );
}

class SearchController extends StateNotifier<SearchState> {
  SearchController(this._repository)
    : super(SearchState(recent: _repository.recent()));

  final SearchRepository _repository;
  Timer? _debounce;
  CancelToken? _cancelToken;

  /// Incremented for every search that is started or abandoned. A response
  /// whose generation is no longer current is dropped, so a slow "ari" can
  /// never land on top of a fast "arijit".
  int _generation = 0;

  void queryChanged(String query) {
    state = state.copyWith(query: query);
    _debounce?.cancel();
    if (query.trim().length < _minimumQueryLength) {
      // Clearing the field returns to the landing screen, and any request
      // still running is abandoned so it cannot repopulate it.
      _abandonInFlight();
      state = state.copyWith(results: const AsyncData(SearchResults()));
      return;
    }
    _debounce = Timer(AppConfig.discoverSearchDebounce, () => _search(query.trim()));
  }

  void selectCategory(SearchCategory category) {
    if (category == state.category) return;
    state = state.copyWith(category: category);
    final query = state.query.trim();
    if (query.length >= _minimumQueryLength) _search(query);
  }

  void submitRecent(String query) {
    _debounce?.cancel();
    state = state.copyWith(query: query);
    _search(query.trim());
  }

  void retry() {
    final query = state.query.trim();
    if (query.length >= _minimumQueryLength) _search(query);
  }

  void _abandonInFlight() {
    _generation++;
    _cancelToken?.cancel('Superseded by a newer search');
    _cancelToken = null;
  }

  Future<void> _search(String query) async {
    _cancelToken?.cancel('Superseded by a newer search');
    final generation = ++_generation;
    final token = CancelToken();
    _cancelToken = token;
    // The previous results stay on screen underneath the loading flag: tearing
    // them down on every keystroke is what makes a search field flicker.
    state = state.copyWith(
      results: const AsyncLoading<SearchResults>().copyWithPrevious(
        state.results,
      ),
    );
    try {
      final results = await _repository.search(
        query,
        state.category,
        cancelToken: token,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        results: AsyncData(results),
        recent: _repository.recent(),
      );
    } on DioException catch (error, stack) {
      if (generation != _generation || CancelToken.isCancel(error)) return;
      state = state.copyWith(results: AsyncError(error, stack));
    } catch (error, stack) {
      if (generation != _generation) return;
      state = state.copyWith(results: AsyncError(error, stack));
    }
  }

  void recordClick(MusicItem item) =>
      _repository.recordClick(state.query, item);

  Future<void> removeRecent(String query) async {
    await _repository.removeRecent(query);
    state = state.copyWith(recent: _repository.recent());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }
}
