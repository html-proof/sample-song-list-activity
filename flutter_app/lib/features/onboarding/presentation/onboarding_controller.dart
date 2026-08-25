import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/config/app_config.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/onboarding/data/onboarding_repository.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
  );
});

final availableLanguagesProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(onboardingRepositoryProvider).languages();
});

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
      return OnboardingController(ref.watch(onboardingRepositoryProvider));
    });

class OnboardingState {
  const OnboardingState({
    this.step = 0,
    this.languages = const [],
    this.artists = const [],
    this.results = const AsyncData([]),
    this.saving = false,
    this.error,
  });

  final int step;
  final List<String> languages;
  final List<MusicItem> artists;
  final AsyncValue<List<MusicItem>> results;
  final bool saving;
  final String? error;

  OnboardingState copyWith({
    int? step,
    List<String>? languages,
    List<MusicItem>? artists,
    AsyncValue<List<MusicItem>>? results,
    bool? saving,
    String? error,
    bool clearError = false,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      languages: languages ?? this.languages,
      artists: artists ?? this.artists,
      results: results ?? this.results,
      saving: saving ?? this.saving,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(this._repository) : super(const OnboardingState());

  final OnboardingRepository _repository;
  Timer? _debounce;

  void toggleLanguage(String language) {
    final selected = [...state.languages];
    selected.contains(language)
        ? selected.remove(language)
        : selected.add(language);
    state = state.copyWith(languages: selected, clearError: true);
  }

  void next() {
    if (state.languages.isEmpty) {
      state = state.copyWith(error: 'Choose at least one language');
      return;
    }
    state = state.copyWith(step: 1, clearError: true);
  }

  void back() => state = state.copyWith(step: 0, clearError: true);

  void searchArtists(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      state = state.copyWith(results: const AsyncData([]));
      return;
    }
    _debounce = Timer(AppConfig.searchDebounce, () async {
      state = state.copyWith(results: const AsyncLoading());
      try {
        final result = await _repository.artists(query.trim());
        state = state.copyWith(results: AsyncData(result));
      } catch (error, stack) {
        state = state.copyWith(results: AsyncError(error, stack));
      }
    });
  }

  void toggleArtist(MusicItem artist) {
    final selected = [...state.artists];
    final index = selected.indexWhere((item) => item.id == artist.id);
    index < 0 ? selected.add(artist) : selected.removeAt(index);
    state = state.copyWith(artists: selected, clearError: true);
  }

  Future<bool> finish() async {
    if (state.artists.length < 3) {
      state = state.copyWith(error: 'Choose at least three artists');
      return false;
    }
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _repository.complete(
        languages: state.languages,
        artists: state.artists,
      );
      state = state.copyWith(saving: false);
      return true;
    } catch (error) {
      state = state.copyWith(saving: false, error: error.toString());
      return false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
