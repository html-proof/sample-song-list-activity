import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/cache/active_request_registry.dart';
import 'package:music_hub/cache/audio_cache.dart';
import 'package:music_hub/cache/segment_downloader.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/network_policy.dart';
import 'package:music_hub/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => methodCall.method == 'init'
          ? {'id': '1'}
          : <String, dynamic>{},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('data_usage_test_');
    ActiveRequestRegistry.instance.clear();
  });

  tearDown(() async {
    ActiveRequestRegistry.instance.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PlaybackSession & Bitrate Calculations', () {
    test('Calculates expected file size accurately for various bitrates and durations', () {
      // 4-minute song (240s) at High (160 kbps) -> 160 * 240 / 8 / 1000 = 4.80 MB
      final sessionHigh = PlaybackSession(
        trackId: 'track_1',
        title: 'Test Track',
        streamUrl: 'https://cdn.example.com/audio/128.mp4',
        lockedBitrate: 160,
        lockedQuality: 'high',
        duration: const Duration(minutes: 4),
        cacheKey: 'user_track_1_high_1',
        requestId: 'req_1',
      );
      expect(sessionHigh.expectedFileSizeBytes, closeTo(4.8, 0.01));

      // 4-minute song at Normal (128 kbps) -> 128 * 240 / 8 / 1000 = 3.84 MB
      final sessionNormal = PlaybackSession(
        trackId: 'track_2',
        title: 'Normal Track',
        streamUrl: 'https://cdn.example.com/audio/128.mp4',
        lockedBitrate: 128,
        lockedQuality: 'normal',
        duration: const Duration(minutes: 4),
        cacheKey: 'user_track_2_normal_1',
        requestId: 'req_2',
      );
      expect(sessionNormal.expectedFileSizeBytes, closeTo(3.84, 0.01));

      // 4-minute song at Very High (320 kbps) -> 320 * 240 / 8 / 1000 = 9.60 MB
      final sessionVeryHigh = PlaybackSession(
        trackId: 'track_3',
        title: 'Very High Track',
        streamUrl: 'https://cdn.example.com/audio/320.mp4',
        lockedBitrate: 320,
        lockedQuality: 'very_high',
        duration: const Duration(minutes: 4),
        cacheKey: 'user_track_3_very_high_1',
        requestId: 'req_3',
      );
      expect(sessionVeryHigh.expectedFileSizeBytes, closeTo(9.6, 0.01));

      // 4-minute song at Low (64 kbps) -> 64 * 240 / 8 / 1000 = 1.92 MB
      final sessionLow = PlaybackSession(
        trackId: 'track_4',
        title: 'Low Track',
        streamUrl: 'https://cdn.example.com/audio/64.mp4',
        lockedBitrate: 64,
        lockedQuality: 'low',
        duration: const Duration(minutes: 4),
        cacheKey: 'user_track_4_low_1',
        requestId: 'req_4',
      );
      expect(sessionLow.expectedFileSizeBytes, closeTo(1.92, 0.01));
    });

    test('Detects suspicious data consumption (>25% above expected)', () {
      final session = PlaybackSession(
        trackId: 'track_1',
        title: 'Test Track',
        streamUrl: 'https://cdn.example.com/audio/128.mp4',
        lockedBitrate: 160,
        lockedQuality: 'high',
        duration: const Duration(minutes: 4),
        cacheKey: 'key_1',
        requestId: 'req_1',
        // 4.8 MB expected. 4.9 MB downloaded -> normal
        networkBytesDownloaded: (4.9 * 1024 * 1024).round(),
      );
      expect(session.isSuspiciousConsumption, isFalse);

      // 14 MB downloaded for a 4.8 MB expected track -> suspicious
      final suspiciousSession = session.copyWith(
        networkBytesDownloaded: (14.0 * 1024 * 1024).round(),
      );
      expect(suspiciousSession.isSuspiciousConsumption, isTrue);

      final report = suspiciousSession.generateTrackDataReport();
      expect(report, contains('TRACK DATA REPORT'));
      expect(report, contains('WARNING: Data consumption exceeds expected size by >25%!'));
    });
  });

  group('ActiveRequestRegistry Deduplication', () {
    test('Reuses in-flight network request for identical key without duplicating transfer', () async {
      final registry = ActiveRequestRegistry.instance;
      const key = 'song123_high_aac_0_524287';

      var executionCount = 0;
      var duplicatePrevented = false;

      Future<SegmentDownloadResult?> mockDownload() async {
        executionCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return const SegmentDownloadResult(
          statusCode: 206,
          byteStart: 0,
          byteEnd: 524287,
          totalContentLength: 4800000,
          bytes: [1, 2, 3, 4, 5],
        );
      }

      // Simulate simultaneous requests from player and preloader
      final future1 = registry.runOrAttach(key, mockDownload);
      final future2 = registry.runOrAttach(
        key,
        mockDownload,
        onDuplicatePrevented: () {
          duplicatePrevented = true;
        },
      );

      final results = await Future.wait([future1, future2]);

      expect(executionCount, equals(1)); // Only executed ONCE
      expect(duplicatePrevented, isTrue);
      expect(registry.duplicateCount, equals(1));
      expect(results[0]?.bytes, equals([1, 2, 3, 4, 5]));
      expect(results[1]?.bytes, equals([1, 2, 3, 4, 5]));
    });
  });

  group('AudioCache Contiguous Range Support', () {
    test('getContiguousAvailableRange returns exact available slice', () async {
      final cache = AudioCache(cacheDirectory: tempDir);
      await cache.initialize();

      const key = 'guest_test_track_high_1';
      final testBytes = Uint8List.fromList(List.generate(500, (i) => i % 256));

      // Write bytes 0 to 499
      await cache.writeSegment(
        key: key,
        songId: 'test_track',
        userId: 'guest',
        audioQuality: 'high',
        streamVersion: '1',
        byteStart: 0,
        byteEnd: 499,
        totalContentLength: 5000,
        bytes: testBytes,
      );

      // Check contiguous range starting at 0
      final rangeFromZero = cache.getContiguousAvailableRange(key, 0);
      expect(rangeFromZero, isNotNull);
      expect(rangeFromZero!.start, equals(0));
      expect(rangeFromZero.end, equals(499));

      // Check contiguous range starting at 200
      final rangeFromMid = cache.getContiguousAvailableRange(key, 200);
      expect(rangeFromMid, isNotNull);
      expect(rangeFromMid!.start, equals(200));
      expect(rangeFromMid.end, equals(499));

      // Check contiguous range starting beyond cached data
      final rangeBeyond = cache.getContiguousAvailableRange(key, 600);
      expect(rangeBeyond, isNull);
    });
  });

  group('Strict Quality Lock in PlayerController', () {
    test('Quality is locked on track start and pendingQuality applies to NEXT song only', () async {
      final policy = DataUsagePolicy();
      final monitor = ConnectionMonitor();
      final controller = PlayerController(
        policy: policy,
        connection: monitor,
      );

      final track1 = const Track(
        seokey: 'song-1',
        title: 'Song One',
        durationSeconds: 240,
        streamUrl: 'https://cdn.example.com/audio/128.mp4',
        streamUrls: {
          'high_quality': 'https://cdn.example.com/audio/128.mp4',
          'medium_quality': 'https://cdn.example.com/audio/64.mp4',
          'low_quality': 'https://cdn.example.com/audio/16.mp4',
        },
      );

      final track2 = const Track(
        seokey: 'song-2',
        title: 'Song Two',
        durationSeconds: 200,
        streamUrl: 'https://cdn.example.com/audio/128.mp4',
        streamUrls: {
          'high_quality': 'https://cdn.example.com/audio/128.mp4',
          'medium_quality': 'https://cdn.example.com/audio/64.mp4',
          'low_quality': 'https://cdn.example.com/audio/16.mp4',
        },
      );

      controller.queue = [track1, track2];

      // Start playing track 1
      await controller.play(track1, autoPlay: false);

      expect(controller.currentSession, isNotNull);
      expect(controller.currentSession!.lockedQuality, equals('high'));
      expect(controller.currentSession!.lockedBitrate, equals(128));
      expect(controller.currentSession!.streamUrl, contains('128.mp4'));

      // While track 1 is playing, simulate network downgrade or settings change to 'low'
      controller.policy?.setValue('streaming_quality_wifi', 'low');

      // VERIFY: The currently playing track MUST NOT change quality
      expect(controller.currentSession!.lockedQuality, equals('high'));
      expect(controller.currentSession!.lockedBitrate, equals(128));
      expect(controller.pendingQuality, equals('low'));

      // When advancing to the next song, pendingQuality ('low') must now be applied
      await controller.play(track2, autoPlay: false);

      expect(controller.currentSession!.lockedQuality, equals('low'));
      expect(controller.currentSession!.lockedBitrate, equals(64));
      expect(controller.currentSession!.streamUrl, contains('16.mp4'));
      expect(controller.pendingQuality, isNull);

      controller.dispose();
    });
  });
}
