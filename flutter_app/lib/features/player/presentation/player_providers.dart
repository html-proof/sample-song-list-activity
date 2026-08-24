import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/audio/playback_progress.dart';

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem;
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioHandlerProvider).playbackState;
});

final playerQueueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).queue;
});

final playerPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioHandlerProvider).positionStream;
});

final playerProgressProvider = StreamProvider<PlaybackProgress>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return (() async* {
    yield handler.currentProgress;
    yield* handler.progressStream;
  })();
});
