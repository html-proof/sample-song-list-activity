import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/services.dart';

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

  Track createTrack(String id, String title, {int duration = 200}) {
    return Track.fromJson({
      'id': id,
      'seokey': id,
      'title': title,
      'artists': 'Artist Test',
      'duration': '$duration',
      'stream_urls': {
        'urls': {'high_quality': 'https://stream.test/$id.m3u8'}
      },
    });
  }

  group('Spotify-Style Album Playback & Queue Progression', () {
    test('Track finishes -> automatically plays next song in album queue (Track 1 -> Track 2 -> Track 3)', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1'),
        createTrack('2', 'Track 2'),
        createTrack('3', 'Track 3'),
      ];

      // Start Track 1 with album queue
      await player.play(albumTracks[0], fromQueue: albumTracks);
      expect(player.current?.title, 'Track 1');
      expect(player.currentIndex, 0);
      expect(player.queue.length, 3);
      expect(player.queue.map((t) => t.title).toList(), ['Track 1', 'Track 2', 'Track 3']);

      // Track 1 completes -> onSongCompleted() should advance to Track 2
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 2');
      expect(player.currentIndex, 1);
      // Album queue must remain intact and persistent
      expect(player.queue.map((t) => t.title).toList(), ['Track 1', 'Track 2', 'Track 3']);

      // Track 2 completes -> onSongCompleted() should advance to Track 3
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 3');
      expect(player.currentIndex, 2);
      expect(player.queue.map((t) => t.title).toList(), ['Track 1', 'Track 2', 'Track 3']);

      player.dispose();
    });

    test('Starting mid-album (Track 2) sets currentIndex = 1 and advances to Track 3 on completion', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1'),
        createTrack('2', 'Track 2'),
        createTrack('3', 'Track 3'),
        createTrack('4', 'Track 4'),
      ];

      // User starts Track 2 directly from album screen
      await player.play(albumTracks[1], fromQueue: albumTracks);
      expect(player.current?.title, 'Track 2');
      expect(player.currentIndex, 1);
      expect(player.queue.length, 4);

      // Track 2 completes -> advances to Track 3
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 3');
      expect(player.currentIndex, 2);

      // Track 3 completes -> advances to Track 4
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 4');
      expect(player.currentIndex, 3);

      player.dispose();
    });

    test('Repeat One replays the current song without incrementing queue index', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1'),
        createTrack('2', 'Track 2'),
        createTrack('3', 'Track 3'),
      ];

      await player.play(albumTracks[1], fromQueue: albumTracks);
      player.repeatMode = PlaybackRepeatMode.one;
      expect(player.currentIndex, 1);
      expect(player.current?.title, 'Track 2');

      // Track 2 completes with Repeat One
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 2');
      expect(player.currentIndex, 1);
      expect(player.position, Duration.zero);

      player.dispose();
    });

    test('Repeat All: when last song finishes, wraps back to first song of album (Track 1)', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1'),
        createTrack('2', 'Track 2'),
        createTrack('3', 'Track 3'),
      ];

      await player.play(albumTracks[2], fromQueue: albumTracks);
      player.repeatMode = PlaybackRepeatMode.all;
      expect(player.currentIndex, 2);
      expect(player.current?.title, 'Track 3');

      // Track 3 finishes -> should wrap back to Track 1 (index 0)
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 1');
      expect(player.currentIndex, 0);

      player.dispose();
    });

    test('Repeat Off: when last song finishes and autoplay is disabled, stops playback', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1'),
        createTrack('2', 'Track 2'),
      ];

      player.repeatMode = PlaybackRepeatMode.off;
      player.autoplayEnabled = false;

      await player.play(albumTracks[1], fromQueue: albumTracks);
      expect(player.currentIndex, 1);
      expect(player.current?.title, 'Track 2');

      // Last track finishes -> stops playback
      await player.onSongCompleted();
      expect(player.playing, false);
      expect(player.position, Duration.zero);
      expect(player.current?.title, 'Track 2');

      player.dispose();
    });

    test('Repeat Off + Autoplay enabled: loads related tracks when album finishes', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1'),
        createTrack('2', 'Track 2'),
      ];

      final relatedTrack = createTrack('related_1', 'Related Recommendation');
      player.repeatMode = PlaybackRepeatMode.off;
      player.autoplayEnabled = true;
      player.loadRelatedTracks = (track) async => [relatedTrack];

      await player.play(albumTracks[1], fromQueue: albumTracks);
      expect(player.currentIndex, 1);

      // Last track finishes -> fetches related music and plays related_1
      await player.onSongCompleted();
      expect(player.current?.title, 'Related Recommendation');
      expect(player.currentIndex, 2);
      expect(player.queue.length, 3);
      expect(player.queue[2].title, 'Related Recommendation');

      player.dispose();
    });

    test('Position immediately resets to 0:00 on song transition', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1', duration: 180),
        createTrack('2', 'Track 2', duration: 210),
      ];

      await player.play(albumTracks[0], fromQueue: albumTracks);
      player.position = const Duration(seconds: 180);

      // Trigger next track
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 2');
      // Position must not remain stuck at 180s; it must be 0
      expect(player.position, Duration.zero);

      player.dispose();
    });

    test('Session restoration preserves currentIndex and queue', () async {
      final player = PlayerController();
      final albumTracks = [
        createTrack('1', 'Track 1'),
        createTrack('2', 'Track 2'),
        createTrack('3', 'Track 3'),
      ];

      await player.restorePlaybackSession(
        albumTracks[1],
        albumTracks,
        const Duration(seconds: 45),
        savedIndex: 1,
      );

      expect(player.current?.title, 'Track 2');
      expect(player.currentIndex, 1);
      expect(player.position, const Duration(seconds: 45));

      // Advancing from restored state continues sequentially to Track 3
      await player.onSongCompleted();
      expect(player.current?.title, 'Track 3');
      expect(player.currentIndex, 2);

      player.dispose();
    });
  });
}
