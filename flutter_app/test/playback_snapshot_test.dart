import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/audio/playback_snapshot.dart';

PlaybackSnapshot make({
  Duration position = const Duration(minutes: 2, seconds: 17),
  Duration? duration = const Duration(minutes: 4, seconds: 32),
  bool wasPlaying = true,
  String? streamUrl,
  DateTime? expiresAt,
}) {
  return PlaybackSnapshot(
    songId: '68890279',
    title: 'Kalyani',
    artist: 'ARJN',
    artworkUrl: 'https://cdn.example/art.jpg',
    streamUrl: streamUrl,
    streamUrlExpiresAt: expiresAt,
    position: position,
    duration: duration,
    queueIndex: 2,
    queueSongIds: const ['1', '2', '68890279', '4'],
    wasPlaying: wasPlaying,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    cacheKey: '68890279',
  );
}

void main() {
  test('survives a serialisation round trip', () {
    final restored = PlaybackSnapshot.fromJson(make().toJson())!;

    expect(restored.songId, '68890279');
    expect(restored.title, 'Kalyani');
    expect(restored.artist, 'ARJN');
    expect(restored.position, const Duration(minutes: 2, seconds: 17));
    expect(restored.duration, const Duration(minutes: 4, seconds: 32));
    expect(restored.queueIndex, 2);
    expect(restored.queueSongIds, ['1', '2', '68890279', '4']);
    expect(restored.wasPlaying, isTrue);
    expect(restored.cacheKey, '68890279');
  });

  test('a mid-song position is not treated as complete', () {
    expect(make().wasEffectivelyComplete, isFalse);
  });

  test('the last couple of seconds count as complete', () {
    final snapshot = make(
      position: const Duration(minutes: 4, seconds: 30),
      duration: const Duration(minutes: 4, seconds: 32),
    );

    expect(snapshot.wasEffectivelyComplete, isTrue);
  });

  test('an unknown duration is never complete', () {
    expect(make(duration: null).wasEffectivelyComplete, isFalse);
  });

  test('rejects a snapshot with no song', () {
    expect(PlaybackSnapshot.fromJson({'position_ms': 1000}), isNull);
    expect(PlaybackSnapshot.fromJson(null), isNull);
  });

  test('an expired stream token is not reused', () {
    final snapshot = make(
      streamUrl: 'https://cdn.example/a.m3u8?exp=1',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    expect(snapshot.hasFreshStreamUrl, isFalse);
  });

  test('a still-valid stream token is reused', () {
    final snapshot = make(
      streamUrl: 'https://cdn.example/a.m3u8?exp=9',
      expiresAt: DateTime.now().add(const Duration(hours: 3)),
    );

    expect(snapshot.hasFreshStreamUrl, isTrue);
  });

  test('a missing url is never considered fresh', () {
    expect(make().hasFreshStreamUrl, isFalse);
  });
}
