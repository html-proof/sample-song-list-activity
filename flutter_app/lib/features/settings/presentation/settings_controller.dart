import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/settings/data/app_settings.dart';
import 'package:music_hub_app/features/settings/data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
  );
});

final settingsSyncErrorProvider = StateProvider<String?>((_) => null);

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AsyncValue<AppSettings>>((ref) {
      ref.watch(authStateProvider);
      return SettingsController(ref, ref.watch(settingsRepositoryProvider));
    });

final appThemeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref
      .watch(settingsControllerProvider)
      .value
      ?.general['theme_mode']
      ?.toString();
  return switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

class SettingsController extends StateNotifier<AsyncValue<AppSettings>> {
  SettingsController(this._ref, this._repository)
    : super(AsyncData(_repository.readCached() ?? AppSettings.defaults())) {
    unawaited(_applyDeviceState(state.value!));
    if (_ref.read(firebaseAuthProvider).currentUser != null) {
      unawaited(refresh(silent: true));
    }
  }

  final Ref _ref;
  final SettingsRepository _repository;
  int _revision = 0;

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    try {
      final settings = await _repository.fetch();
      state = AsyncData(settings);
      await _applyDeviceState(settings);
      _ref.read(settingsSyncErrorProvider.notifier).state = null;
    } catch (error, stack) {
      if (!silent) state = AsyncError(error, stack);
      _ref.read(settingsSyncErrorProvider.notifier).state = error.toString();
    }
  }

  Future<void> update(String group, Map<String, dynamic> changes) async {
    final previous = state.value ?? AppSettings.defaults();
    final optimistic = previous.mergeGroup(group, changes);
    final revision = ++_revision;
    state = AsyncData(optimistic);
    await _repository.save(optimistic);
    for (final entry in changes.entries) {
      await _ref
          .read(localStoreProvider)
          .saveSetting('${group}_${entry.key}', entry.value);
    }
    if (group == 'playback') {
      await _ref.read(audioHandlerProvider).applyPlaybackSettings(changes);
    }
    _ref.read(settingsSyncErrorProvider.notifier).state = null;

    try {
      final remote = await _repository.update(group, changes);
      if (revision != _revision) return;
      final confirmed = optimistic.mergeGroup(group, remote);
      state = AsyncData(confirmed);
      await _repository.save(confirmed);
    } catch (error) {
      _ref.read(settingsSyncErrorProvider.notifier).state = error.toString();
      if (revision != _revision) return;
      state = AsyncData(previous);
      await _repository.save(previous);
      await _applyDeviceState(previous);
    }
  }

  Future<void> reset() async {
    state = const AsyncLoading();
    try {
      final settings = await _repository.reset();
      await _applyDeviceState(settings);
      state = AsyncData(settings);
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  Future<void> clearListeningHistory() => _repository.clearListeningHistory();

  Future<void> clearSearchHistory() => _repository.clearSearchHistory();

  Future<void> resetRecommendations() => _repository.resetRecommendations();

  Future<void> _applyDeviceState(AppSettings settings) async {
    final store = _ref.read(localStoreProvider);
    for (final group in [
      'general',
      'playback',
      'downloads',
      'recommendations',
      'notifications',
      'privacy',
    ]) {
      for (final entry in settings.group(group).entries) {
        await store.saveSetting('${group}_${entry.key}', entry.value);
      }
    }
    await _ref
        .read(audioHandlerProvider)
        .applyPlaybackSettings(settings.playback);
  }
}
