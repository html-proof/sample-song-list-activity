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

  Track createTrack(String id, String title) {
    return Track.fromJson({
      'id': id,
      'seokey': id,
      'title': title,
      'artists': 'Artist 1',
      'duration': '200',
      'stream_urls': {
        'urls': {'high_quality': 'https://stream.test/$id.m3u8'}
      },
    });
  }

  group('Spotify-like Sequential Playback (Shuffle OFF)', () {
    test('plays full album sequentially in strict original order: A -> B -> C -> D -> E', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song A'),
        createTrack('2', 'Song B'),
        createTrack('3', 'Song C'),
        createTrack('4', 'Song D'),
        createTrack('5', 'Song E'),
      ];

      expect(player.isShuffled, false);

      // Start at first track
      await player.play(tracks[0], fromQueue: tracks);
      expect(player.current?.title, 'Song A');
      expect(player.queue.map((t) => t.title).toList(), [
        'Song A',
        'Song B',
        'Song C',
        'Song D',
        'Song E',
      ]);
      expect(player.originalQueue.map((t) => t.title).toList(), [
        'Song A',
        'Song B',
        'Song C',
        'Song D',
        'Song E',
      ]);

      // Move next -> Song B
      await player.next();
      expect(player.current?.title, 'Song B');

      // Move next -> Song C
      await player.next();
      expect(player.current?.title, 'Song C');

      // Move next -> Song D
      await player.next();
      expect(player.current?.title, 'Song D');

      // Move next -> Song E
      await player.next();
      expect(player.current?.title, 'Song E');

      // Move next at end of queue when repeat is off: remains on Song E (no random wrap)
      await player.next();
      expect(player.current?.title, 'Song E');

      player.dispose();
    });

    test('starting mid-album (Song C) strictly plays C -> D -> E without reordering queue', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song A'),
        createTrack('2', 'Song B'),
        createTrack('3', 'Song C'),
        createTrack('4', 'Song D'),
        createTrack('5', 'Song E'),
      ];

      expect(player.isShuffled, false);

      // User taps Song C in album
      await player.play(tracks[2], fromQueue: tracks);
      expect(player.current?.title, 'Song C');
      // Queue remains unchanged in original album order
      expect(player.queue.map((t) => t.title).toList(), [
        'Song A',
        'Song B',
        'Song C',
        'Song D',
        'Song E',
      ]);

      // Move next -> Song D
      await player.next();
      expect(player.current?.title, 'Song D');

      // Move next -> Song E
      await player.next();
      expect(player.current?.title, 'Song E');

      player.dispose();
    });
  });

  group('Spotify-like Shuffle Toggle & Behavior', () {
    test('toggling Shuffle ON shuffles upcoming tracks without restarting current track', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song A'),
        createTrack('2', 'Song B'),
        createTrack('3', 'Song C'),
        createTrack('4', 'Song D'),
        createTrack('5', 'Song E'),
      ];

      // Start playing Song B with Shuffle OFF
      await player.play(tracks[1], fromQueue: tracks);
      expect(player.current?.title, 'Song B');
      expect(player.isShuffled, false);

      // Toggle Shuffle ON while Song B is playing
      player.toggleShuffle();
      expect(player.isShuffled, true);
      // Current track must still be Song B
      expect(player.current?.title, 'Song B');
      expect(player.queue.first.title, 'Song B');
      // All tracks must be present without duplicates
      expect(player.queue.length, 5);
      final uniqueIds = player.queue.map((t) => t.id).toSet();
      expect(uniqueIds.length, 5);
      // Original queue must be preserved
      expect(player.originalQueue.map((t) => t.title).toList(), [
        'Song A',
        'Song B',
        'Song C',
        'Song D',
        'Song E',
      ]);

      player.dispose();
    });

    test('toggling Shuffle OFF restores original queue order from current song onwards without restart', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song A'),
        createTrack('2', 'Song B'),
        createTrack('3', 'Song C'),
        createTrack('4', 'Song D'),
        createTrack('5', 'Song E'),
      ];

      // Play with Shuffle ON
      await player.playWithShuffle(tracks, startTrack: tracks[2]); // Song C
      expect(player.isShuffled, true);
      expect(player.current?.title, 'Song C');
      expect(player.originalQueue.map((t) => t.title).toList(), [
        'Song A',
        'Song B',
        'Song C',
        'Song D',
        'Song E',
      ]);

      // Toggle Shuffle OFF
      player.toggleShuffle();
      expect(player.isShuffled, false);
      // Current song is still Song C
      expect(player.current?.title, 'Song C');
      // Queue is restored to original album order
      expect(player.queue.map((t) => t.title).toList(), [
        'Song A',
        'Song B',
        'Song C',
        'Song D',
        'Song E',
      ]);

      // Next track must now strictly follow original album order: Song D -> Song E
      await player.next();
      expect(player.current?.title, 'Song D');
      await player.next();
      expect(player.current?.title, 'Song E');

      player.dispose();
    });

    test('playWithShuffle preserves original queue and sets isShuffled = true', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song 1'),
        createTrack('2', 'Song 2'),
        createTrack('3', 'Song 3'),
        createTrack('4', 'Song 4'),
      ];

      await player.playWithShuffle(tracks);
      expect(player.isShuffled, true);
      expect(player.originalQueue.length, 4);
      expect(player.queue.length, 4);
      expect(player.originalQueue.map((t) => t.id).toList(), ['1', '2', '3', '4']);
      expect(player.queue.contains(player.current), true);

      player.dispose();
    });
  });

  group('Playback History & Previous Navigation', () {
    test('previous() follows playback history stack correctly', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song 1'),
        createTrack('2', 'Song 2'),
        createTrack('3', 'Song 3'),
      ];

      await player.play(tracks[0], fromQueue: tracks);
      expect(player.current?.title, 'Song 1');

      await player.next();
      expect(player.current?.title, 'Song 2');
      expect(player.playbackHistory.length, 1);
      expect(player.playbackHistory.last.title, 'Song 1');

      await player.next();
      expect(player.current?.title, 'Song 3');
      expect(player.playbackHistory.length, 2);

      // Previous should return to Song 2
      player.position = const Duration(seconds: 2); // <= 10s
      await player.previous();
      expect(player.current?.title, 'Song 2');

      // Previous again should return to Song 1
      player.position = const Duration(seconds: 2);
      await player.previous();
      expect(player.current?.title, 'Song 1');

      player.dispose();
    });

    test('previous() resets to 0:00 when position > 10 seconds', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song 1'),
        createTrack('2', 'Song 2'),
      ];

      await player.play(tracks[0], fromQueue: tracks);
      await player.next();
      expect(player.current?.title, 'Song 2');

      // Position > 10s
      player.position = const Duration(seconds: 35);
      await player.previous();
      // Must stay on current song and reset position to zero
      expect(player.current?.title, 'Song 2');
      expect(player.position, Duration.zero);

      player.dispose();
    });
  });

  group('Repeat All Cycle with Shuffle', () {
    test('when last song in shuffled queue completes and repeatMode is all, regenerates fresh shuffle cycle', () async {
      final player = PlayerController();
      final tracks = [
        createTrack('1', 'Song A'),
        createTrack('2', 'Song B'),
        createTrack('3', 'Song C'),
      ];

      player.repeatMode = PlaybackRepeatMode.all;
      await player.playWithShuffle(tracks);
      expect(player.isShuffled, true);

      // Advance to end of queue
      await player.next();
      await player.next();
      expect(player.current?.id, player.queue.last.id);

      // Advance past last track with RepeatMode.all and Shuffle ON
      await player.next();
      expect(player.queue.length, 3);
      expect(player.isShuffled, true);
      expect(player.originalQueue.map((t) => t.id).toList(), ['1', '2', '3']);
      expect(player.current, isNotNull);

      player.dispose();
    });
  });
}
