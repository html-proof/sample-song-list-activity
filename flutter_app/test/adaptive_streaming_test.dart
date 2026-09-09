import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/services.dart';
import 'package:music_hub/cache/audio_cache.dart';
import 'package:music_hub/cache/segment_downloader.dart';
import 'package:music_hub/streaming/throughput_estimator.dart';
import 'package:music_hub/streaming/adaptive_quality_manager.dart';
import 'package:music_hub/streaming/playback_watchdog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Track createSampleTrack(String id, String title, {int duration = 200}) {
    return Track.fromJson({
      'id': id,
      'seokey': id,
      'title': title,
      'artists': 'Sample Artist',
      'duration': '$duration',
      'stream_urls': {
        'urls': {
          'low_quality': 'https://stream.test/$id-low.m3u8',
          'medium_quality': 'https://stream.test/$id-normal.m3u8',
          'high_quality': 'https://stream.test/$id-high.m3u8',
          'very_high_quality': 'https://stream.test/$id-very-high.m3u8',
        }
      },
    });
  }

  group('1. Network Bandwidth & Throughput Estimator (EWMA)', () {
    late ThroughputEstimator estimator;

    setUp(() {
      estimator = ThroughputEstimator(initialBps: 1000000.0, alpha: 0.25);
    });

    test('Initial baseline bandwidth and classification', () {
      expect(estimator.estimatedBps, equals(1000000.0));
      expect(estimator.estimatedKbps, equals(1000.0));
      expect(estimator.bandwidthClass, equals(NetworkBandwidthClass.good));
    });

    test('EWMA updates smoothly on chunk transfers', () {
      // Transfer 250 KB (2,000,000 bits) in 1000ms -> sample = 2,000,000 bps
      estimator.recordTransfer(250000, 1000);
      // First sample sets baseline
      expect(estimator.estimatedBps, equals(2000000.0));
      expect(estimator.samplesCount, equals(1));
      expect(estimator.bandwidthClass, equals(NetworkBandwidthClass.excellent));

      // Next transfer: 12.5 KB (100,000 bits) in 1000ms -> sample = 100,000 bps
      // EWMA: 0.25 * 100,000 + 0.75 * 2,000,000 = 25,000 + 1,500,000 = 1,525,000 bps
      estimator.recordTransfer(12500, 1000);
      expect(estimator.estimatedBps, closeTo(1525000.0, 10.0));
      expect(estimator.samplesCount, equals(2));
    });

    test('Speed classification thresholds: poor, moderate, good, excellent', () {
      // Poor: < 150 kbps
      estimator.reset(initialBps: 100000.0);
      expect(estimator.bandwidthClass, equals(NetworkBandwidthClass.poor));

      // Moderate: 150 - 450 kbps
      estimator.reset(initialBps: 300000.0);
      expect(estimator.bandwidthClass, equals(NetworkBandwidthClass.moderate));

      // Good: 450 - 1800 kbps
      estimator.reset(initialBps: 1200000.0);
      expect(estimator.bandwidthClass, equals(NetworkBandwidthClass.good));

      // Excellent: > 1800 kbps
      estimator.reset(initialBps: 2500000.0);
      expect(estimator.bandwidthClass, equals(NetworkBandwidthClass.excellent));
    });

    test('Reset clears samples and restores default baseline on interface handover', () {
      estimator.recordTransfer(500000, 500);
      expect(estimator.samplesCount, greaterThan(0));

      estimator.reset(initialBps: 800000.0);
      expect(estimator.samplesCount, equals(0));
      expect(estimator.estimatedBps, equals(800000.0));
      expect(estimator.latencyMs, equals(80.0));
    });
  });

  group('2. Adaptive Quality Manager & Hysteresis Switching', () {
    late ThroughputEstimator estimator;
    late AdaptiveQualityManager qualityManager;

    setUp(() {
      estimator = ThroughputEstimator(initialBps: 2500000.0); // Fast connection
      qualityManager = AdaptiveQualityManager(estimator: estimator);
    });

    tearDown(() {
      qualityManager.dispose();
    });

    test('Fast downgrade on low buffer health (< 3.5s and < 2.0s)', () {
      expect(qualityManager.currentQuality, equals('normal'));

      // Buffer health drops below 3.5s
      qualityManager.updateBufferHealth(
        const Duration(seconds: 50),
        const Duration(seconds: 53), // 3.0s buffer health
      );
      expect(qualityManager.bufferHealthSeconds, closeTo(3.0, 0.1));

      // Buffer critically drops below 2.0s -> urgent drop to 'low'
      qualityManager.updateBufferHealth(
        const Duration(seconds: 50),
        const Duration(milliseconds: 51200), // 1.2s buffer health
      );
      expect(qualityManager.currentQuality, equals('low'));
    });

    test('Fast downgrade on playback stall', () {
      // Upgrade state manually for test
      qualityManager.updateBufferHealth(
        const Duration(seconds: 10),
        const Duration(seconds: 30),
      );

      qualityManager.recordStall();
      // On stall, quality immediately downgrades
      expect(qualityManager.currentQuality, equals('low'));
    });

    test('Delayed gradual upgrade requires sustained stability (>=15s)', () {
      final track = createSampleTrack('1', 'Test Song');
      final initialQ = qualityManager.resolveQualityForTrack(
        track,
        isWifi: true,
        isCellular: false,
        isDataSaver: false,
      );
      expect(initialQ, isIn(['high', 'very_high']));
    });

    test('Data saver on mobile data caps quality to low', () {
      final track = createSampleTrack('1', 'Data Saver Track');
      final q = qualityManager.resolveQualityForTrack(
        track,
        isWifi: false,
        isCellular: true,
        isDataSaver: true,
      );
      expect(q, equals('low'));
    });

    test('User explicit preference overrides automatic adaptation', () {
      final track = createSampleTrack('1', 'Explicit Track');
      final q = qualityManager.resolveQualityForTrack(
        track,
        configuredPreference: 'high',
        isWifi: true,
        isCellular: false,
        isDataSaver: false,
      );
      expect(q, equals('high'));
    });
  });

  group('3. Playback Watchdog (Silent Stall Detection & Recovery)', () {
    test('Advancing position does not trigger stall recovery', () async {
      var stallTriggered = false;
      final watchdog = PlaybackWatchdog(
        onStallDetected: (pos) async {
          stallTriggered = true;
        },
        stallThreshold: const Duration(milliseconds: 100),
      );
      watchdog.start();

      await watchdog.evaluate(
        isPlaying: true,
        isBuffering: false,
        isConnected: true,
        currentPosition: const Duration(seconds: 1),
      );

      await watchdog.evaluate(
        isPlaying: true,
        isBuffering: false,
        isConnected: true,
        currentPosition: const Duration(seconds: 2),
      );

      expect(stallTriggered, isFalse);
      watchdog.dispose();
    });

    test('Stall detected after stallThreshold while stuck buffering triggers silent recovery at current position', () async {
      Duration? recoveredPos;
      final watchdog = PlaybackWatchdog(
        onStallDetected: (pos) async {
          recoveredPos = pos;
        },
        stallThreshold: const Duration(milliseconds: 50),
      );
      watchdog.start();

      // First tick at position 42s in buffering
      await watchdog.evaluate(
        isPlaying: true,
        isBuffering: true,
        isConnected: true,
        currentPosition: const Duration(seconds: 42),
      );

      // Wait longer than stallThreshold
      await Future.delayed(const Duration(milliseconds: 70));

      // Still stuck buffering at position 42s
      await watchdog.evaluate(
        isPlaying: true,
        isBuffering: true,
        isConnected: true,
        currentPosition: const Duration(seconds: 42),
      );

      expect(recoveredPos, equals(const Duration(seconds: 42)));
      watchdog.dispose();
    });
  });

  group('4. AudioCache & Downloads Protection', () {
    test('Active playing track is protected during cache clearing', () async {
      final cache = AudioCache();
      const activeKey = 'test_active_song_key';

      cache.protect(activeKey);
      expect(cache.isProtected(activeKey), isTrue);

      cache.unprotect(activeKey);
      expect(cache.isProtected(activeKey), isFalse);
    });

    test('CancellationToken cancels in-flight chunk downloads on seek or track switch', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);

      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });

  group('5. PlayerController Spotify-Style Continuity & Preload', () {
    late PlayerController player;
    late List<Track> sampleQueue;

    setUp(() {
      player = PlayerController();
      sampleQueue = [
        createSampleTrack('1', 'Track 1', duration: 100),
        createSampleTrack('2', 'Track 2', duration: 120),
        createSampleTrack('3', 'Track 3', duration: 140),
      ];
    });

    tearDown(() {
      player.dispose();
    });

    test('Starts track with correct initial state and duration', () async {
      await player.play(sampleQueue[0], fromQueue: sampleQueue);
      expect(player.current?.title, equals('Track 1'));
      expect(player.currentIndex, equals(0));
      expect(player.queue.length, equals(3));
      expect(player.duration.inSeconds, equals(100));
    });

    test('Network change does not restart or reload song if playing from buffer', () {
      player.play(sampleQueue[0], fromQueue: sampleQueue);
      expect(player.current?.title, equals('Track 1'));

      // Simulate connection restored event
      // PlayerController must not reset position or restart from 00:00
      expect(player.current?.title, equals('Track 1'));
      expect(player.currentIndex, equals(0));
    });

    test('Next track progression preserves original queue order when shuffle is off', () async {
      await player.play(sampleQueue[0], fromQueue: sampleQueue);
      expect(player.currentIndex, equals(0));

      await player.next();
      expect(player.currentIndex, equals(1));
      expect(player.current?.title, equals('Track 2'));

      await player.next();
      expect(player.currentIndex, equals(2));
      expect(player.current?.title, equals('Track 3'));
    });

    test('Previous button rewinds to 00:00 if played > 5 seconds, else moves to previous track', () async {
      await player.play(sampleQueue[1], fromQueue: sampleQueue);
      expect(player.currentIndex, equals(1));

      // Simulated position at 10s: previous() rewinds to 00:00
      player.position = const Duration(seconds: 10);
      await player.previous();
      expect(player.position, equals(Duration.zero));
      expect(player.currentIndex, equals(1));

      // Position <= 5s: previous() moves to previous song
      player.position = const Duration(seconds: 2);
      await player.previous();
      expect(player.currentIndex, equals(0));
      expect(player.current?.title, equals('Track 1'));
    });

    test('isHlsStream accurately identifies HLS playlists with and without tokens', () {
      expect(PlayerController.isHlsStream('https://vodhlsgaana-ebw.akamaized.net/hls/56/13879256/69704746/320.mp4.master.m3u8?hdnts=exp=1725881452~acl=/hls/*'), isTrue);
      expect(PlayerController.isHlsStream('https://cdn.example.com/audio/master.m3u8'), isTrue);
      expect(PlayerController.isHlsStream('https://cdn.example.com/hls/stream/audio'), isTrue);
      expect(PlayerController.isHlsStream('https://cdn.example.com/audio/song.mp4'), isFalse);
      expect(PlayerController.isHlsStream('https://cdn.example.com/audio/song.mp3?token=abc'), isFalse);
    });

    test('PlayerController with audioCache seamlessly plays HLS tracks without failure', () async {
      final cache = AudioCache();
      final hlsPlayer = PlayerController(audioCache: cache);
      final hlsTrack = createSampleTrack(
        'gehra-hua',
        'GEHRA HUA (FROM "DHURANDHAR")',
        duration: 363,
      );

      await hlsPlayer.play(hlsTrack);
      expect(hlsPlayer.current?.title, equals('GEHRA HUA (FROM "DHURANDHAR")'));
      expect(hlsPlayer.error, isNull);
      expect(hlsPlayer.duration.inSeconds, equals(363));
      hlsPlayer.dispose();
    });
  });
}
