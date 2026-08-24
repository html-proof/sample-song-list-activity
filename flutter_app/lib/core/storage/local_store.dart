import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

class LocalStore {
  LocalStore._(this._cache, this._queue, this._downloads, this._settings);

  final Box<dynamic> _cache;
  final Box<dynamic> _queue;
  final Box<dynamic> _downloads;
  final Box<dynamic> _settings;

  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    final boxes = await Future.wait<Box<dynamic>>([
      Hive.openBox<dynamic>('metadata_cache'),
      Hive.openBox<dynamic>('player_queue'),
      Hive.openBox<dynamic>('downloads'),
      Hive.openBox<dynamic>('settings'),
    ]);
    return LocalStore._(boxes[0], boxes[1], boxes[2], boxes[3]);
  }

  Future<void> putCached(String key, Object value, {required Duration ttl}) {
    return _cache.put(key, {
      'expiresAt': DateTime.now().add(ttl).millisecondsSinceEpoch,
      'value': jsonEncode(value),
    });
  }

  dynamic readCached(String key) {
    final entry = _cache.get(key);
    if (entry is! Map) return null;
    final expiry = entry['expiresAt'];
    if (expiry is! int || DateTime.now().millisecondsSinceEpoch > expiry) {
      _cache.delete(key);
      return null;
    }
    final value = entry['value'];
    return value is String ? jsonDecode(value) : null;
  }

  Future<void> saveQueue(
    List<Map<String, dynamic>> queue,
    int index, {
    int positionMs = 0,
    bool shuffle = false,
    String repeatMode = 'off',
  }) {
    return _queue.put('active', {
      'items': queue,
      'index': index,
      'position_ms': positionMs,
      'shuffle': shuffle,
      'repeat_mode': repeatMode,
    });
  }

  Map<String, dynamic>? readQueue() {
    final value = _queue.get('active');
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  List<Map<String, dynamic>> downloads() => _downloads.values
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList(growable: false);

  Future<void> saveDownload(Map<String, dynamic> item) {
    return _downloads.put(item['id'].toString(), item);
  }

  Map<String, dynamic>? readDownload(String id) {
    final value = _downloads.get(id);
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  Future<void> removeDownload(String id) => _downloads.delete(id);

  T readSetting<T>(String key, T fallback) {
    final value = _settings.get(key);
    return value is T ? value : fallback;
  }

  Future<void> saveSetting(String key, Object? value) =>
      _settings.put(key, value);

  Map<String, dynamic>? readSettingsSnapshot() {
    final value = _settings.get('app_settings_snapshot');
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  Future<void> saveSettingsSnapshot(Map<String, dynamic> value) =>
      _settings.put('app_settings_snapshot', value);

  int get metadataCacheEntries => _cache.length;

  Future<void> clearMetadataCache() => _cache.clear();

  Future<void> clearPrivateSession() async {
    await _cache.clear();
    await _queue.clear();
    await _settings.delete('recent_searches');
    await _settings.delete('app_settings_snapshot');
  }

  List<String> recentSearches() {
    final value = _settings.get('recent_searches');
    return value is List
        ? value.map((item) => item.toString()).toList()
        : const [];
  }

  Future<void> addRecentSearch(String query) {
    final values = [
      query,
      ...recentSearches().where((item) => item != query),
    ].take(10).toList();
    return _settings.put('recent_searches', values);
  }

  Future<void> removeRecentSearch(String query) {
    return _settings.put(
      'recent_searches',
      recentSearches().where((item) => item != query).toList(),
    );
  }
}
