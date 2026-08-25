import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/artists/data/artist_repository.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

final artistRepositoryProvider = Provider<ArtistRepository>((ref) {
  return ArtistRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
  );
});

final artistControllerProvider =
    StateNotifierProvider<ArtistController, ArtistState>((ref) {
      return ArtistController(ref.watch(artistRepositoryProvider))..start();
    });

enum ArtistMode { recommendations, search }

class ArtistState {
  const ArtistState({
    this.mode = ArtistMode.recommendations,
    this.query = '',
    this.recommendations = const [],
    this.searchResults = const [],
    this.nextCursor,
    this.loadingRecommendations = false,
    this.loadingMore = false,
    this.searching = false,
    this.error,
  });

  final ArtistMode mode;
  final String query;
  final List<MusicItem> recommendations;
  final List<MusicItem> searchResults;
  final String? nextCursor;

  /// True only when there is nothing to show yet. A background refresh over
  /// existing content leaves this false so the list never flashes a spinner.
  final bool loadingRecommendations;
  final bool loadingMore;
  final bool searching;
  final String? error;

  bool get hasMore => nextCursor != null;

  ArtistState copyWith({
    ArtistMode? mode,
    String? query,
    List<MusicItem>? recommendations,
    List<MusicItem>? searchResults,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingRecommendations,
    bool? loadingMore,
    bool? searching,
    String? error,
    bool clearError = false,
  }) {
    return ArtistState(
      mode: mode ?? this.mode,
      query: query ?? this.query,
      recommendations: recommendations ?? this.recommendations,
      searchResults: searchResults ?? this.searchResults,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      loadingRecommendations:
          loadingRecommendations ?? this.loadingRecommendations,
      loadingMore: loadingMore ?? this.loadingMore,
      searching: searching ?? this.searching,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ArtistController extends StateNotifier<ArtistState> {
  ArtistController(this._repository) : super(const ArtistState());

  static const searchDebounce = Duration(milliseconds: 300);

  final ArtistRepository _repository;
  Timer? _debounce;

  /// Incremented on every search. A response whose generation no longer matches
  /// is discarded, so a slow reply for "ari" cannot overwrite "arijit".
  int _searchGeneration = 0;

  /// Same guard for recommendations, so a slow refresh cannot land on top of a
  /// list the user has already replaced by searching.
  int _recommendationGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Paints whatever was cached on disk, then refreshes behind it.
  void start() {
    final cached = _repository.cachedRecommendations();
    if (cached != null) {
      state = state.copyWith(recommendations: cached, clearError: true);
    } else {
      state = state.copyWith(loadingRecommendations: true);
    }
    unawaited(refreshRecommendations());
  }

  Future<void> refreshRecommendations() async {
    final generation = ++_recommendationGeneration;
    try {
      final page = await _repository.recommended();
      if (!mounted || generation != _recommendationGeneration) return;
      state = state.copyWith(
        recommendations: page.artists,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingRecommendations: false,
        clearError: true,
      );
    } catch (error) {
      if (!mounted || generation != _recommendationGeneration) return;
      state = state.copyWith(
        loadingRecommendations: false,
        // A failed refresh behind cached content is not worth an error banner.
        error: state.recommendations.isEmpty ? error.toString() : null,
        clearError: state.recommendations.isNotEmpty,
      );
    }
  }

  /// Appends the next page. The existing list is never cleared while loading.
  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loadingMore) return;
    state = state.copyWith(loadingMore: true);
    final generation = _recommendationGeneration;
    try {
      final page = await _repository.recommended(cursor: cursor, limit: 20);
      if (!mounted || generation != _recommendationGeneration) return;
      final seen = state.recommendations.map((item) => item.id).toSet();
      state = state.copyWith(
        recommendations: [
          ...state.recommendations,
          for (final artist in page.artists)
            if (artist.id.isEmpty || seen.add(artist.id)) artist,
        ],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false);
    }
  }

  void onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      cancelSearch();
      return;
    }
    state = state.copyWith(
      query: value,
      mode: ArtistMode.search,
      searching: true,
      clearError: true,
    );
    _debounce = Timer(searchDebounce, () => unawaited(search(trimmed)));
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      cancelSearch();
      return;
    }
    final generation = ++_searchGeneration;
    try {
      final results = await _repository.search(trimmed);
      // A newer keystroke has already been issued, so this reply is stale.
      if (!mounted || generation != _searchGeneration) return;
      state = state.copyWith(
        searchResults: results,
        searching: false,
        clearError: true,
      );
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      state = state.copyWith(searching: false, error: error.toString());
    }
  }

  /// Drops any in-flight search and returns to recommendations. Old results are
  /// cleared so they cannot briefly reappear under an empty query.
  void cancelSearch() {
    _debounce?.cancel();
    _searchGeneration++;
    if (!mounted) return;
    state = state.copyWith(
      mode: ArtistMode.recommendations,
      query: '',
      searchResults: const [],
      searching: false,
      clearError: true,
    );
  }
}
