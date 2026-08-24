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

class SearchState {
  const SearchState({
    this.query = '',
    this.type = 'all',
    this.results = const AsyncData(SearchResults()),
    this.recent = const [],
  });

  final String query;
  final String type;
  final AsyncValue<SearchResults> results;
  final List<String> recent;

  SearchState copyWith({
    String? query,
    String? type,
    AsyncValue<SearchResults>? results,
    List<String>? recent,
  }) => SearchState(
    query: query ?? this.query,
    type: type ?? this.type,
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

  void queryChanged(String query) {
    state = state.copyWith(query: query);
    _debounce?.cancel();
    _cancelToken?.cancel('Superseded by a newer search');
    if (query.trim().length < 2) {
      state = state.copyWith(results: const AsyncData(SearchResults()));
      return;
    }
    _debounce = Timer(AppConfig.searchDebounce, () => _search(query.trim()));
  }

  void selectType(String type) {
    if (type == state.type) return;
    state = state.copyWith(type: type);
    if (state.query.trim().length >= 2) _search(state.query.trim());
  }

  void submitRecent(String query) {
    state = state.copyWith(query: query);
    _search(query);
  }

  Future<void> _search(String query) async {
    _cancelToken = CancelToken();
    state = state.copyWith(results: const AsyncLoading());
    try {
      final results = await _repository.search(
        query,
        state.type,
        cancelToken: _cancelToken,
      );
      state = state.copyWith(
        results: AsyncData(results),
        recent: _repository.recent(),
      );
    } on DioException catch (error, stack) {
      if (!CancelToken.isCancel(error)) {
        state = state.copyWith(results: AsyncError(error, stack));
      }
    } catch (error, stack) {
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
