import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'cache_index.dart';
import 'cache_models.dart';

class AudioCache {
  AudioCache({
    Directory? cacheDirectory,
    this.maxSizeBytes = 500 * 1024 * 1024, // 500 MB
    this.defaultTtl = const Duration(hours: 24),
  }) : _customCacheDir = cacheDirectory;

  final Directory? _customCacheDir;
  int maxSizeBytes;
  final Duration defaultTtl;

  Directory? _cacheDir;
  CacheIndexRepository? _index;
  final Set<String> _protectedKeys = {};
  final CacheMetrics metrics = CacheMetrics();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (_customCacheDir != null) {
        _cacheDir = _customCacheDir;
      } else {
        final baseDir = await getApplicationSupportDirectory();
        _cacheDir = Directory('${baseDir.path}/audio_cache');
      }
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      final indexFile = File('${_cacheDir!.path}/cache_index.json');
      _index = CacheIndexRepository(indexFile);
      await _index!.load();
      await cleanupExpired();
      await enforceCacheLimit();
    } catch (e) {
      debugPrint('AudioCache initialization error: $e');
    } finally {
      _initialized = true;
    }
  }

  static String generateKey({
    required String userId,
    required String songId,
    String audioQuality = 'automatic',
    String streamVersion = '1',
  }) {
    final u = userId.trim().isEmpty ? 'guest' : userId.trim();
    final s = songId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final q = audioQuality.trim().toLowerCase();
    final v = streamVersion.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${u}_${s}_${q}_$v';
  }

  void protect(String key) {
    _protectedKeys.add(key);
  }

  void unprotect(String key) {
    _protectedKeys.remove(key);
  }

  bool isProtected(String key) => _protectedKeys.contains(key);

  CacheEntry? getEntry(String key) => _index?.get(key);

  File _getCacheFile(String fileName) => File('${_cacheDir!.path}/$fileName');

  /// Get the complete cached audio file if it is fully downloaded on disk.
  File? getCompleteFile(String key) {
    final entry = _index?.get(key);
    if (entry == null || !entry.isComplete) return null;
    final file = _getCacheFile(entry.fileName);
    return file.existsSync() ? file : null;
  }

  /// Returns the maximum available contiguous cached range starting at [start],
  /// or null if [start] is not cached.
  ByteRange? getContiguousAvailableRange(String key, int start) {
    final entry = _index?.get(key);
    if (entry == null) return null;
    final file = _getCacheFile(entry.fileName);
    if (!file.existsSync()) return null;

    if (entry.isComplete && entry.totalBytes > start) {
      return ByteRange(start, entry.totalBytes - 1);
    }

    for (final range in entry.cachedRanges) {
      if (range.start <= start && range.end >= start) {
        return ByteRange(start, range.end);
      }
    }
    return null;
  }

  /// Check if a byte range is already fully cached locally on disk.
  bool hasRange(String key, int start, int end) {
    final entry = _index?.get(key);
    if (entry == null) return false;
    final file = _getCacheFile(entry.fileName);
    if (!file.existsSync()) return false;

    if (entry.isComplete && entry.totalBytes > 0 && end < entry.totalBytes) {
      return true;
    }

    for (final range in entry.cachedRanges) {
      if (range.start <= start && range.end >= end) {
        return true;
      }
    }
    return false;
  }

  /// Read byte range from disk cache.
  Future<Uint8List?> readRange(String key, int start, int end) async {
    final available = getContiguousAvailableRange(key, start);
    if (available == null) {
      metrics.recordMiss(end - start + 1);
      return null;
    }
    final effectiveEnd = end < available.end ? end : available.end;
    final length = effectiveEnd - start + 1;
    if (length <= 0) {
      metrics.recordMiss(end - start + 1);
      return null;
    }

    final entry = _index!.get(key)!;
    final file = _getCacheFile(entry.fileName);
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(length);
        await _index!.touch(key, ttl: defaultTtl);
        metrics.recordHit(bytes.length);
        return bytes;
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('Error reading range $start-$effectiveEnd from cache file: $e');
      return null;
    }
  }

  /// Save downloaded segment into cache file and update index atomically.
  Future<void> writeSegment({
    required String key,
    required String songId,
    required String userId,
    required String audioQuality,
    required String streamVersion,
    required int byteStart,
    required int byteEnd,
    required int totalContentLength,
    required List<int> bytes,
    String? etag,
    String mimeType = 'audio/mp4',
  }) async {
    if (_cacheDir == null || _index == null) await initialize();
    if (bytes.isEmpty) return;

    final fileName = '$key.audio';
    final targetFile = _getCacheFile(fileName);
    final now = DateTime.now();

    try {
      RandomAccessFile raf;
      if (!await targetFile.exists()) {
        final tmpFile = File('${targetFile.path}.tmp');
        await tmpFile.create(recursive: true);
        raf = await tmpFile.open(mode: FileMode.write);
        await raf.setPosition(byteStart);
        await raf.writeFrom(bytes);
        await raf.close();
        await tmpFile.rename(targetFile.path);
      } else {
        raf = await targetFile.open(mode: FileMode.append);
        await raf.setPosition(byteStart);
        await raf.writeFrom(bytes);
        await raf.close();
      }

      final existing = _index!.get(key);
      final newRange = ByteRange(byteStart, byteEnd);
      final updatedRanges = <ByteRange>[];

      if (existing != null) {
        var merged = false;
        for (final r in existing.cachedRanges) {
          if (r.overlapsOrAdjacent(newRange)) {
            updatedRanges.add(r.merge(newRange));
            merged = true;
          } else {
            updatedRanges.add(r);
          }
        }
        if (!merged) {
          updatedRanges.add(newRange);
        }
      } else {
        updatedRanges.add(newRange);
      }

      // Compact ranges
      updatedRanges.sort((a, b) => a.start.compareTo(b.start));
      final compacted = <ByteRange>[];
      for (final r in updatedRanges) {
        if (compacted.isEmpty) {
          compacted.add(r);
        } else {
          final last = compacted.last;
          if (last.overlapsOrAdjacent(r)) {
            compacted[compacted.length - 1] = last.merge(r);
          } else {
            compacted.add(r);
          }
        }
      }

      final totalBytes = totalContentLength > 0
          ? totalContentLength
          : (existing?.totalBytes ?? 0);
      final isComplete = totalBytes > 0 &&
          compacted.isNotEmpty &&
          compacted.first.start == 0 &&
          compacted.first.end >= totalBytes - 1;

      final entry = CacheEntry(
        key: key,
        songId: songId,
        userId: userId,
        audioQuality: audioQuality,
        streamVersion: streamVersion,
        fileName: fileName,
        totalBytes: totalBytes,
        cachedRanges: compacted,
        etag: etag ?? existing?.etag,
        mimeType: mimeType,
        lastAccessedAt: now,
        expiresAt: now.add(defaultTtl),
        isComplete: isComplete,
      );

      await _index!.put(entry);
      await enforceCacheLimit();
    } catch (e) {
      debugPrint('Error writing segment to cache: $e');
    }
  }

  /// Evict least recently used entries when cache size exceeds limit.
  Future<void> enforceCacheLimit() async {
    if (_index == null) return;
    final entries = _index!.all();
    var currentSize = _index!.totalBytes();

    if (currentSize <= maxSizeBytes) return;

    // Sort by last accessed time (oldest first)
    entries.sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));

    for (final entry in entries) {
      if (currentSize <= maxSizeBytes) break;
      if (isProtected(entry.key)) continue; // Never evict active playing track

      final file = _getCacheFile(entry.fileName);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      currentSize -= entry.cachedBytes;
      await _index!.remove(entry.key);
      metrics.evictionCount++;
    }
  }

  /// Remove expired cache entries (TTL > 24 hours).
  Future<void> cleanupExpired() async {
    if (_index == null) return;
    final now = DateTime.now();
    final entries = _index!.all();

    for (final entry in entries) {
      if (entry.isExpired(now) && !isProtected(entry.key)) {
        final file = _getCacheFile(entry.fileName);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
        await _index!.remove(entry.key);
      }
    }
  }

  /// Clear entire temporary audio cache (without touching offline downloads).
  Future<void> clearCache() => clear();

  Future<void> clear() async {
    if (_cacheDir == null || _index == null) await initialize();
    try {
      final entries = _index!.all();
      final protectedFiles = <String>{};
      for (final entry in entries) {
        if (_protectedKeys.contains(entry.key)) {
          protectedFiles.add(entry.fileName);
          continue;
        }
        final file = _getCacheFile(entry.fileName);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
        await _index!.remove(entry.key);
      }
      // Also delete any remaining .tmp or .audio files in directory not protected
      if (await _cacheDir!.exists()) {
        final files = _cacheDir!.listSync();
        for (final entity in files) {
          if (entity is File &&
              (entity.path.endsWith('.audio') ||
                  entity.path.endsWith('.tmp') ||
                  entity.path.endsWith('.part'))) {
            final fileName = entity.uri.pathSegments.last;
            if (!protectedFiles.contains(fileName)) {
              try {
                entity.deleteSync();
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing audio cache: $e');
    }
  }

  /// Return total size in bytes of the temporary audio cache.
  Future<int> calculateCacheSize() async {
    if (_cacheDir == null || _index == null) await initialize();
    try {
      var total = 0;
      if (await _cacheDir!.exists()) {
        final files = _cacheDir!.listSync();
        for (final entity in files) {
          if (entity is File && !entity.path.endsWith('cache_index.json')) {
            total += entity.lengthSync();
          }
        }
      }
      return total;
    } catch (_) {
      return _index?.totalBytes() ?? 0;
    }
  }
}
