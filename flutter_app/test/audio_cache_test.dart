import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/cache/audio_cache.dart';
import 'package:music_hub/cache/cache_index.dart';
import 'package:music_hub/cache/cache_models.dart';
import 'package:music_hub/cache/prefetch_manager.dart';
import 'package:music_hub/cache/segment_downloader.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/network_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('music_cache_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('AudioCache.generateKey creates stable deterministic keys', () {
    final key1 = AudioCache.generateKey(
      userId: 'user_123',
      songId: 'song_456',
      audioQuality: 'high',
      streamVersion: '1',
    );
    final key2 = AudioCache.generateKey(
      userId: 'user_123',
      songId: 'song_456',
      audioQuality: 'high',
      streamVersion: '1',
    );
    expect(key1, equals(key2));
    expect(key1, equals('user_123_song_456_high_1'));

    final guestKey = AudioCache.generateKey(
      userId: '',
      songId: 'malayalam-track-1',
      audioQuality: 'automatic',
    );
    expect(guestKey, equals('guest_malayalam-track-1_automatic_1'));
  });

  test('CacheIndexRepository saves, loads, and persists entries', () async {
    final indexFile = File('${tempDir.path}/cache_index.json');
    final repo = CacheIndexRepository(indexFile);
    await repo.load();

    final now = DateTime.now();
    final entry = CacheEntry(
      key: 'u1_s1_high_1',
      songId: 's1',
      userId: 'u1',
      audioQuality: 'high',
      streamVersion: '1',
      fileName: 'u1_s1_high_1.audio',
      totalBytes: 10000,
      cachedRanges: const [ByteRange(0, 4999)],
      lastAccessedAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      isComplete: false,
    );

    await repo.put(entry);
    expect(repo.get('u1_s1_high_1'), isNotNull);
    expect(repo.get('u1_s1_high_1')!.cachedBytes, equals(5000));

    // Reload from file to verify persistence
    final repo2 = CacheIndexRepository(indexFile);
    await repo2.load();
    final loaded = repo2.get('u1_s1_high_1');
    expect(loaded, isNotNull);
    expect(loaded!.songId, equals('s1'));
    expect(loaded.cachedRanges.first.start, equals(0));
    expect(loaded.cachedRanges.first.end, equals(4999));
  });

  test('AudioCache writes segments and reads back byte ranges', () async {
    final cache = AudioCache(cacheDirectory: tempDir);
    await cache.initialize();

    final testBytes = Uint8List.fromList(List.generate(100, (i) => i));
    const key = 'guest_track1_auto_1';

    await cache.writeSegment(
      key: key,
      songId: 'track1',
      userId: 'guest',
      audioQuality: 'automatic',
      streamVersion: '1',
      byteStart: 0,
      byteEnd: 99,
      totalContentLength: 100,
      bytes: testBytes,
    );

    expect(cache.hasRange(key, 0, 99), isTrue);
    expect(cache.hasRange(key, 0, 50), isTrue);
    expect(cache.hasRange(key, 50, 99), isTrue);
    expect(cache.hasRange(key, 0, 150), isFalse);

    final readBytes = await cache.readRange(key, 10, 19);
    expect(readBytes, isNotNull);
    expect(readBytes!.length, equals(10));
    expect(readBytes[0], equals(10));
    expect(readBytes[9], equals(19));

    final entry = cache.getEntry(key);
    expect(entry, isNotNull);
    expect(entry!.isComplete, isTrue);
  });

  test('AudioCache LRU eviction obeys size limits and protects active track', () async {
    // 300 bytes limit
    final cache = AudioCache(cacheDirectory: tempDir, maxSizeBytes: 300);
    await cache.initialize();

    // Write track 1 (150 bytes)
    await cache.writeSegment(
      key: 'track1',
      songId: 't1',
      userId: 'guest',
      audioQuality: 'high',
      streamVersion: '1',
      byteStart: 0,
      byteEnd: 149,
      totalContentLength: 150,
      bytes: List.filled(150, 1),
    );

    // Write track 2 (150 bytes)
    await cache.writeSegment(
      key: 'track2',
      songId: 't2',
      userId: 'guest',
      audioQuality: 'high',
      streamVersion: '1',
      byteStart: 0,
      byteEnd: 149,
      totalContentLength: 150,
      bytes: List.filled(150, 2),
    );

    expect(cache.hasRange('track1', 0, 149), isTrue);
    expect(cache.hasRange('track2', 0, 149), isTrue);

    // Protect track1 (as currently playing song)
    cache.protect('track1');

    // Write track 3 (150 bytes) -> Total 450 > 300 limit -> track2 should be evicted first!
    await cache.writeSegment(
      key: 'track3',
      songId: 't3',
      userId: 'guest',
      audioQuality: 'high',
      streamVersion: '1',
      byteStart: 0,
      byteEnd: 149,
      totalContentLength: 150,
      bytes: List.filled(150, 3),
    );

    // track1 was protected, so track2 was evicted
    expect(cache.hasRange('track1', 0, 149), isTrue);
    expect(cache.hasRange('track2', 0, 149), isFalse);
    expect(cache.hasRange('track3', 0, 149), isTrue);
  });

  test('AudioCache.clearCache clears temporary files without deleting offline downloads', () async {
    final cache = AudioCache(cacheDirectory: tempDir);
    await cache.initialize();

    await cache.writeSegment(
      key: 'cache_track',
      songId: 'c1',
      userId: 'guest',
      audioQuality: 'high',
      streamVersion: '1',
      byteStart: 0,
      byteEnd: 99,
      totalContentLength: 100,
      bytes: List.filled(100, 1),
    );

    // Create an offline downloads directory simulated outside cache directory
    final offlineDir = Directory('${tempDir.parent.path}/offline_test_downloads');
    await offlineDir.create(recursive: true);
    final offlineFile = File('${offlineDir.path}/downloaded_song.mp3');
    await offlineFile.writeAsString('offline audio data');

    expect(cache.hasRange('cache_track', 0, 99), isTrue);
    expect(await offlineFile.exists(), isTrue);

    await cache.clearCache();

    expect(cache.hasRange('cache_track', 0, 99), isFalse);
    expect(await offlineFile.exists(), isTrue); // Offline download intact!

    await offlineDir.delete(recursive: true);
  });

  test('QueuePrefetchManager cancels prefetch and respects Data Saver policy', () async {
    final cache = AudioCache(cacheDirectory: tempDir);
    await cache.initialize();

    final policy = DataUsagePolicy();
    await policy.setValue('data_saver_enabled', true);
    await policy.setValue('preload_next_song', false);

    final monitor = ConnectionMonitor();
    final prefetcher = QueuePrefetchManager(
      audioCache: cache,
      downloader: SegmentDownloader(),
      policy: policy,
      connection: monitor,
    );

    const nextTrack = Track(
      seokey: 'next-track-1',
      title: 'Next Track',
      artist: 'Artist',
      album: 'Album',
      streamUrl: 'https://example.com/audio.mp3',
    );

    // Should skip prefetching when policy forbids preload
    await prefetcher.prefetchNextTrack(nextTrack, userId: 'guest');
    final key = AudioCache.generateKey(userId: 'guest', songId: 'next-track-1');
    expect(cache.hasRange(key, 0, 100), isFalse);
  });
}
