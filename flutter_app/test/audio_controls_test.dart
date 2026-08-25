import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/audio/media_item_mapper.dart';
import 'package:music_hub_app/core/audio/playback_state_machine.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

void main() {
  group('MediaItemMapper', () {
    test('maps complete song with artist, album, duration, and artUri', () {
      const item = MusicItem(
        id: 'track-100',
        title: 'Song Title',
        subtitle: 'Artist Subtitle',
        artistName: 'Explicit Artist',
        albumName: 'Explicit Album',
        imageUrl: 'https://cdn.example.com/art.jpg',
        duration: Duration(minutes: 3, seconds: 45),
        streamUrl: 'https://cdn.example.com/audio.mp3',
        type: MusicItemType.song,
        raw: {'album': 'Raw Album'},
      );

      final media = mediaItemFromMusicItem(item);

      expect(media.id, 'track-100');
      expect(media.title, 'Song Title');
      expect(media.artist, 'Explicit Artist');
      expect(media.album, 'Explicit Album');
      expect(media.artUri, Uri.parse('https://cdn.example.com/art.jpg'));
      expect(media.duration, const Duration(minutes: 3, seconds: 45));
    });

    test('ignores non-http/file URI schemes safely', () {
      const item = MusicItem(
        id: 'track-200',
        title: 'Invalid Scheme Song',
        imageUrl: 'javascript:alert(1)',
        type: MusicItemType.song,
        raw: {},
      );

      final media = mediaItemFromMusicItem(item);
      expect(media.artUri, isNull);
    });
  });

  group('PlaybackStateMachine & System Actions', () {
    test('transition to playRequested sets wantsToPlay and updates phase', () {
      var state = const PlaybackMachineState();
      expect(state.phase, PlaybackPhase.idle);
      expect(state.wantsToPlay, isFalse);

      state = state.transition(PlaybackSignal.loadRequested, autoPlay: true);
      expect(state.phase, PlaybackPhase.loading);
      expect(state.wantsToPlay, isTrue);

      state = state.transition(PlaybackSignal.playbackStarted);
      expect(state.phase, PlaybackPhase.playing);
      expect(state.wantsToPlay, isTrue);

      state = state.transition(PlaybackSignal.pauseRequested);
      expect(state.phase, PlaybackPhase.paused);
      expect(state.wantsToPlay, isFalse);
    });

    test('completed signal transitions cleanly to completed phase', () {
      var state = const PlaybackMachineState(
        phase: PlaybackPhase.playing,
        wantsToPlay: true,
      );
      state = state.transition(PlaybackSignal.completed);
      expect(state.phase, PlaybackPhase.completed);
      expect(state.wantsToPlay, isFalse);
    });

    test('rapid Next requests maintain wantsToPlay intent', () {
      var state = const PlaybackMachineState(
        phase: PlaybackPhase.playing,
        wantsToPlay: true,
      );
      // Tap next
      state = state.transition(PlaybackSignal.loadRequested, autoPlay: true);
      expect(state.phase, PlaybackPhase.loading);
      expect(state.wantsToPlay, isTrue);

      // Tap next immediately again
      state = state.transition(PlaybackSignal.loadRequested, autoPlay: true);
      expect(state.phase, PlaybackPhase.loading);
      expect(state.wantsToPlay, isTrue);

      // Tap next third time
      state = state.transition(PlaybackSignal.loadRequested, autoPlay: true);
      expect(state.phase, PlaybackPhase.loading);
      expect(state.wantsToPlay, isTrue);

      // Finally playback starts
      state = state.transition(PlaybackSignal.playbackStarted);
      expect(state.phase, PlaybackPhase.playing);
      expect(state.wantsToPlay, isTrue);
    });
  });
}
