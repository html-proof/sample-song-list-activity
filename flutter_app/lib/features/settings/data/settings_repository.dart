import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/features/settings/data/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._api, this._store);

  final ApiClient _api;
  final LocalStore _store;

  AppSettings? readCached() {
    final value = _store.readSettingsSnapshot();
    return value == null ? null : AppSettings.fromJson(value);
  }

  Future<AppSettings> fetch() async {
    final value = await _api.getMap(ApiEndpoints.settings);
    final settings = AppSettings.fromJson(value);
    await save(settings);
    return settings;
  }

  Future<void> save(AppSettings settings) =>
      _store.saveSettingsSnapshot(settings.toJson());

  Future<Map<String, dynamic>> update(
    String group,
    Map<String, dynamic> changes,
  ) async {
    final endpoints = {
      'general': ApiEndpoints.settingsGeneral,
      'playback': ApiEndpoints.settingsPlayback,
      'downloads': ApiEndpoints.settingsDownloads,
      'recommendations': ApiEndpoints.settingsRecommendations,
      'notifications': ApiEndpoints.settingsNotifications,
      'privacy': ApiEndpoints.settingsPrivacy,
    };
    final endpoint = endpoints[group];
    if (endpoint == null) throw ArgumentError.value(group, 'group');
    final response = await _api.patch(endpoint, data: changes);
    if (response is Map) return response.cast<String, dynamic>();
    throw StateError('The server returned invalid settings data');
  }

  Future<AppSettings> reset() async {
    final response = await _api.post(ApiEndpoints.settingsReset);
    if (response is! Map) throw StateError('The server returned invalid data');
    final settings = AppSettings.fromJson(response.cast<String, dynamic>());
    await save(settings);
    return settings;
  }

  Future<void> clearListeningHistory() =>
      _api.post(ApiEndpoints.clearListeningHistory);

  Future<void> clearSearchHistory() =>
      _api.post(ApiEndpoints.clearSearchHistory);

  Future<void> resetRecommendations() =>
      _api.post(ApiEndpoints.resetRecommendations);
}
