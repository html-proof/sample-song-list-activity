import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:just_audio/just_audio.dart';

import 'models.dart';

/// The single process-wide audio handler used by the UI and the OS controls.
class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    playbackState.add(playbackState.value.copyWith(
      controls: const [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
    ));
    _stateSubscription = player.playerStateStream.listen((state) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          state.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        playing: state.playing,
        processingState: _mapState(state.processingState),
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
      ));
    });
    _positionSubscription = player.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
        bufferedPosition: player.bufferedPosition,
      ));
    });
  }

  Future<Duration?> loadTrack(Track track,
      {Map<String, String>? headers, bool autoPlay = true}) async {
    try {
      await player.pause();
      await player.stop();
    } catch (_) {}
    final item = _toMediaItem(track);
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      processingState: AudioProcessingState.loading,
    ));
    final source = AudioSource.uri(
      Uri.parse(track.streamUrl),
      headers: headers,
      tag: item,
    );
    final duration = await player.setAudioSource(source);
    if (autoPlay) {
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      unawaited(player.play().catchError((_) {}));
    }
    return duration;
  }

  Future<Duration?> loadAudioSource(Track track, AudioSource source,
      {bool autoPlay = true}) async {
    try {
      await player.pause();
      await player.stop();
    } catch (_) {}
    mediaItem.add(_toMediaItem(track));
    playbackState.add(playbackState.value.copyWith(
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      processingState: AudioProcessingState.loading,
    ));
    final duration = await player.setAudioSource(source);
    if (autoPlay) {
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      unawaited(player.play().catchError((_) {}));
    }
    return duration;
  }

  /// Seamlessly switch the active audio source while preserving the exact
  /// playback position and media session state (e.g. quality switch or range reconnect).
  Future<Duration?> switchAudioSource(
    AudioSource source, {
    Duration initialPosition = Duration.zero,
    bool autoPlay = true,
  }) async {
    final duration = await player.setAudioSource(
      source,
      initialPosition: initialPosition,
    );
    if (autoPlay) {
      unawaited(player.play().catchError((_) {}));
    }
    return duration;
  }

  Future<Duration?> loadLocalTrack(Track track, String path,
      {bool autoPlay = true}) async {
    try {
      await player.pause();
      await player.stop();
    } catch (_) {}
    final item = _toMediaItem(track);
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      processingState: AudioProcessingState.loading,
    ));
    final source = AudioSource.file(path, tag: item);
    final duration = await player.setAudioSource(source);
    if (autoPlay) {
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      unawaited(player.play().catchError((_) {}));
    }
    return duration;
  }

  void publishQueue(List<Track> tracks) {
    queue.add(tracks.map(_toMediaItem).toList(growable: false));
  }

  MediaItem toMediaItem(Track track) => _toMediaItem(track);

  MediaItem _toMediaItem(Track track) => MediaItem(
      id: track.id.isNotEmpty
          ? track.id
          : (track.seokey.isNotEmpty ? track.seokey : track.trackId),
      title: track.title,
      artist: track.artist,
      album: track.album,
      artUri: track.imageUrl.isEmpty ? null : Uri.tryParse(track.imageUrl),
      duration: track.durationSeconds > 0
          ? Duration(seconds: track.durationSeconds)
          : null,
    );

  AudioProcessingState _mapState(ProcessingState state) => switch (state) {
    ProcessingState.idle => AudioProcessingState.idle,
    ProcessingState.loading => AudioProcessingState.loading,
    ProcessingState.buffering => AudioProcessingState.buffering,
    ProcessingState.ready => AudioProcessingState.ready,
    ProcessingState.completed => AudioProcessingState.completed,
  };

  @override
  Future<void> play() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
    return player.play();
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> skipToNext() async {
    if (onNext != null) await onNext!();
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPrevious != null) await onPrevious!();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _positionSubscription?.cancel();
    await player.dispose();
  }
}

Future<MusicAudioHandler> initAudioHandler() async {
  // Android 13+ will suppress the media notification (and therefore the
  // lock-screen controls) until notification permission has been granted.
  // Request it before starting the foreground audio service.
  try {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  } catch (_) {
    // Playback still works if permission is unavailable; the OS may hide the
    // notification until the user enables it in system settings.
  }
  final handler = await AudioService.init(
    builder: MusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.musichub.app.playback',
      androidNotificationChannelName: 'Music Hub playback',
      // Keep the foreground service alive while paused so Android can keep
      // the media session available to the lock screen.
      // Keep the service in the foreground while paused so the lock-screen
      // MediaSession remains available. The audio_service package requires
      // androidNotificationOngoing=false when stopForegroundOnPause=false.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidShowNotificationBadge: true,
      preloadArtwork: true,
      androidResumeOnClick: true,
    ),
  );
  return handler;
}
