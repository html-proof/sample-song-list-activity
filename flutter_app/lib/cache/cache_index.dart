import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'cache_models.dart';

class CacheIndexRepository {
  CacheIndexRepository(this.indexFile);

  final File indexFile;
  final Map<String, CacheEntry> _entries = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _entries.clear();
    try {
      if (await indexFile.exists()) {
        final raw = await indexFile.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              try {
                final item = CacheEntry.fromJson(
                  Map<String, dynamic>.from(entry.value as Map),
                );
                _entries[item.key] = item;
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading audio cache index: $e');
    } finally {
      _loaded = true;
    }
  }

  CacheEntry? get(String key) => _entries[key];

  List<CacheEntry> all() => _entries.values.toList();

  int totalBytes() {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.cachedBytes;
    }
    return total;
  }

  Future<void> put(CacheEntry entry) async {
    _entries[entry.key] = entry;
    await save();
  }

  Future<void> touch(String key, {Duration ttl = const Duration(hours: 24)}) async {
    final existing = _entries[key];
    if (existing == null) return;
    final now = DateTime.now();
    _entries[key] = existing.copyWith(
      lastAccessedAt: now,
      expiresAt: now.add(ttl),
    );
    await save();
  }

  Future<void> remove(String key) async {
    if (_entries.remove(key) != null) {
      await save();
    }
  }

  Future<void> clear() async {
    _entries.clear();
    await save();
  }

  Future<void> save() async {
    try {
      final data = <String, dynamic>{};
      for (final entry in _entries.entries) {
        data[entry.key] = entry.value.toJson();
      }
      final parentDir = indexFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      final tempFile = File('${indexFile.path}.tmp');
      await tempFile.writeAsString(jsonEncode(data), flush: true);
      if (await indexFile.exists()) {
        await indexFile.delete();
      }
      await tempFile.rename(indexFile.path);
    } catch (e) {
      debugPrint('Error saving audio cache index: $e');
    }
  }
}
