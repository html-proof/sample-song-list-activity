import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_hub_app/core/audio/media_item_mapper.dart';
import 'package:music_hub_app/core/audio/playback_analytics.dart';
import 'package:music_hub_app/core/audio/playback_progress.dart';
import 'package:music_hub_app/core/audio/playback_queue_policy.dart';
import 'package:music_hub_app/core/audio/playback_source_resolver.dart';
import 'package:music_hub_app/core/audio/playback_state_machine.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler(
    this._store, {
    PlaybackSourceResolver? sourceResolver,
    this._analytics,
  }) : _sourceResolver = sourceResolver ?? PlaybackSourceResolver(_store),
       super() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen(_handleIndexChanged);
    _player.positionStream.listen((position) {
      if (_player.currentIndex == _activeIndex) {
        _lastActivePosition = position;
      }
      _scheduleProgress();
      _scheduleQueuePersistence();
    });
    _player.durationStream.listen((_) => _scheduleProgress(force: true));
    _player.errorStream.listen((error) => unawaited(_recover(error)));
    _player.playerStateStream.listen(_handlePlayerState);
  }

  static const _previousRestartThreshold = Duration(seconds: 4);
  static const _maxConsecutiveFailedTracks = 3;

  final LocalStore _store;
  final PlaybackSourceResolver _sourceResolver;
  final PlaybackAnalytics? _analytics;
  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: true,
    androidApplyAudioAttributes: true,
    handleAudioSessionActivation: true,
  );
  final StreamController<PlaybackMachineState> _machineController =
      StreamController<PlaybackMachineState>.broadcast();
  final StreamController<PlaybackProgress> _progressController =
      StreamController<PlaybackProgress>.broadcast();

  List<MusicItem> _musicQueue = const [];
  List<ResolvedPlaybackSource> _resolvedQueue = const [];
  PlaybackMachineState _machine = const PlaybackMachineState();
  PlaybackProgress _lastProgress = const PlaybackProgress.zero();
  Future<void> _mutationTail = Future<void>.value();
  Timer? _persistenceDebounce;
  Timer? _progressDebounce;
  Stopwatch? _listenStopwatch;
  Duration _lastActivePosition = Duration.zero;
  int _accumulatedListenMs = 0;
  int _loadGeneration = 0;
  int _selectionGeneration = 0;
  int _consecutiveFailedTracks = 0;
  int? _requestedQueueIndex;
  int? _activeIndex;
  int? _progressIndex;
  bool _allowProgressRegression = false;
  bool _desiredPlaying = false;
  bool _recovering = false;
  bool _hasStartedCurrent = false;
  bool _currentListenFinalized = false;
  String _queueSource = 'unknown';

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlaybackProgress> get progressStream => _progressController.stream;
  PlaybackProgress get currentProgress => _lastProgress;
  Stream<PlaybackMachineState> get machineStateStream =>
      _machineController.stream;
  PlaybackMachineState get machineState => _machine;
  int? get currentIndex => _player.currentIndex;

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    final saved = _store.readQueue();
    final items = saved?['items'];
    if (items is! List) return;
    final restored = items
        .whereType<Map>()
        .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
        .where(_sourceResolver.hasPotentialSource)
        .toList(growable: false);
    if (restored.isEmpty) return;

    final index = (saved?['index'] as int? ?? 0).clamp(0, restored.length - 1);
    await setMusicQueue(
      restored,
      initialIndex: index,
      autoPlay: false,
      persist: false,
      allowConsecutiveDuplicates: true,
      source: 'restored_queue',
    );
    final repeatMode = switch (saved?['repeat_mode']?.toString()) {
      'all' => LoopMode.all,
      'one' => LoopMode.one,
      _ => LoopMode.off,
    };
    await _player.setLoopMode(repeatMode);
    if (saved?['shuffle'] == true) {
      await _player.shuffle();
      await _player.setShuffleModeEnabled(true);
    }
    final positionMs = int.tryParse(saved?['position_ms']?.toString() ?? '');
    if (positionMs != null && positionMs > 0 && _musicQueue.isNotEmpty) {
      await seek(Duration(milliseconds: positionMs));
    }
    _broadcastState(_player.playbackEvent);
    _scheduleProgress(force: true);
  }

  Future<void> playItems(
    List<MusicItem> items, {
    int initialIndex = 0,
    String source = 'unknown',
    bool allowConsecutiveDuplicates = false,
  }) {
    return setMusicQueue(
      items,
      initialIndex: initialIndex,
      autoPlay: true,
      source: source,
      allowConsecutiveDuplicates: allowConsecutiveDuplicates,
    );
  }

  Future<void> playItem(MusicItem item, {String source = 'unknown'}) =>
      playItems([item], source: source);

  Future<void> setMusicQueue(
    List<MusicItem> items, {
    int initialIndex = 0,
    bool autoPlay = false,
    bool persist = true,
    String source = 'unknown',
    bool allowConsecutiveDuplicates = false,
  }) async {
    final generation = ++_loadGeneration;
    ++_selectionGeneration;
    _desiredPlaying = autoPlay;
    _transition(PlaybackSignal.loadRequested, autoPlay: autoPlay);

    final requested = initialIndex >= 0 && initialIndex < items.length
        ? items[initialIndex]
        : null;
    final prepared = PlaybackQueuePolicy.prepare(
      items,
      allowConsecutiveDuplicates: allowConsecutiveDuplicates,
    );
    if (prepared.isEmpty) {
      _failLoadingIfCurrent(generation);
      return;
    }
    var requestedIndex = requested == null
        ? initialIndex.clamp(0, prepared.length - 1)
        : prepared.indexWhere((item) => identical(item, requested));
    if (requestedIndex < 0 && requested != null) {
      requestedIndex = prepared.indexWhere((item) => item.id == requested.id);
    }
    requestedIndex = requestedIndex.clamp(0, prepared.length - 1);

    // Show the selected metadata immediately. Older async loads are rejected
    // by the generation checks before they can replace the actual player.
    mediaItem.add(_toMediaItem(prepared[requestedIndex]));
    _broadcastIntent();

    final quality = await _streamingQuality();
    final resolved = await Future.wait(
      prepared.map((item) => _sourceResolver.resolve(item, quality)),
    );
    if (generation != _loadGeneration) return;
    if (resolved[requestedIndex] == null) {
      resolved[requestedIndex] = await _sourceResolver.resolve(
        prepared[requestedIndex],
        quality,
        refreshNetwork: true,
      );
    }
    if (generation != _loadGeneration) return;

    final available = <ResolvedPlaybackSource>[];
    var safeIndex = 0;
    for (var index = 0; index < resolved.length; index++) {
      final resolvedSource = resolved[index];
      if (resolvedSource == null) continue;
      if (index <= requestedIndex) safeIndex = available.length;
      available.add(resolvedSource);
    }
    if (available.isEmpty) {
      _failLoadingIfCurrent(generation);
      return;
    }
    safeIndex = safeIndex.clamp(0, available.length - 1);

    await _serialize(() async {
      if (generation != _loadGeneration) return;
      _resetAnalyticsForNewTrack();
      _resolvedQueue = available;
      _musicQueue = available.map((source) => source.item).toList();
      _queueSource = source;
      _requestedQueueIndex = safeIndex;
      final mediaItems = _musicQueue.map(_toMediaItem).toList(growable: false);
      queue.add(mediaItems);
      await _player.setAudioSources(
        _resolvedQueue.map(_audioSource).toList(growable: false),
        initialIndex: safeIndex,
        preload: autoPlay,
      );
      mediaItem.add(mediaItems[safeIndex]);
      if (persist) await _persistQueue();
      if (_desiredPlaying) _startPlayer();
    });
  }

  @override
  Future<void> play() async {
    if (_desiredPlaying) return;
    _desiredPlaying = true;
    _transition(PlaybackSignal.playRequested);
    _broadcastIntent();
    _startPlayer();
  }

  void _startPlayer() {
    if (_player.playing) return;
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        unawaited(_recover(error));
      }),
    );
  }

  @override
  Future<void> pause() async {
    if (!_desiredPlaying && !_player.playing) return;
    _desiredPlaying = false;
    _trackCurrent('pause');
    _finishCurrentListen(completed: false);
    _transition(PlaybackSignal.pauseRequested);
    _broadcastIntent();
    await _player.pause();
    await _persistQueue();
  }

  @override
  Future<void> stop() async {
    ++_loadGeneration;
    ++_selectionGeneration;
    _desiredPlaying = false;
    _finishCurrentListen(completed: false);
    _transition(PlaybackSignal.stopped);
    await _player.stop();
    await _persistQueue();
    await super.stop();
  }

  Future<void> clearQueue() async {
    _persistenceDebounce?.cancel();
    _musicQueue = const [];
    _resolvedQueue = const [];
    queue.add(const []);
    mediaItem.add(null);
    await _store.saveQueue(const [], 0, positionMs: 0);
    await stop();
  }

  @override
  Future<void> seek(Duration position) async {
    final duration = _player.duration;
    final target = duration == null
        ? position
        : Duration(
            milliseconds: position.inMilliseconds.clamp(
              0,
              duration.inMilliseconds,
            ),
          );
    final previous = _player.position;
    _allowProgressRegression = true;
    try {
      await _player.seek(target);
    } catch (_) {
      await _player.seek(previous);
    } finally {
      _scheduleProgress(force: true);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_musicQueue.isEmpty) return;
    final base = _requestedQueueIndex ?? _player.currentIndex ?? 0;
    final target = base + 1;
    if (target >= _musicQueue.length) return;
    _trackCurrent('user_pressed_next', metadata: {'reason': 'next_control'});
    _finishCurrentListen(completed: false);
    await _selectIndexLatest(target);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > _previousRestartThreshold) {
      _trackCurrent(
        'user_pressed_previous',
        metadata: {'action': 'restart_current'},
      );
      await seek(Duration.zero);
      return;
    }
    final base = _requestedQueueIndex ?? _player.currentIndex ?? 0;
    final target = base - 1;
    if (target < 0) {
      await seek(Duration.zero);
      return;
    }
    _trackCurrent(
      'user_pressed_previous',
      metadata: {'action': 'previous_track'},
    );
    _finishCurrentListen(completed: false);
    await _selectIndexLatest(target);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _musicQueue.length) return;
    if (index != _player.currentIndex) {
      _trackCurrent('user_pressed_next', metadata: {'reason': 'queue_tap'});
      _finishCurrentListen(completed: false);
    }
    await _selectIndexLatest(index);
  }

  Future<void> _selectIndexLatest(int index) async {
    final generation = ++_selectionGeneration;
    _requestedQueueIndex = index;
    mediaItem.add(_toMediaItem(_musicQueue[index]));
    _transition(PlaybackSignal.loadRequested, autoPlay: _desiredPlaying);
    _broadcastIntent();
    await _serialize(() async {
      if (generation != _selectionGeneration ||
          index < 0 ||
          index >= _musicQueue.length) {
        return;
      }
      _allowProgressRegression = true;
      await _player.seek(Duration.zero, index: index);
      if (_desiredPlaying) _startPlayer();
      await _persistQueue();
    });
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final raw = mediaItem.extras?['raw'];
    if (raw is! Map) return;
    final music = MusicItem.fromJson(raw.cast<String, dynamic>());
    final quality = await _streamingQuality();
    final resolved = await _sourceResolver.resolve(music, quality);
    if (resolved == null) return;
    await _serialize(() async {
      _musicQueue = [..._musicQueue, resolved.item];
      _resolvedQueue = [..._resolvedQueue, resolved];
      await _player.addAudioSource(_audioSource(resolved));
      queue.add(_musicQueue.map(_toMediaItem).toList(growable: false));
      await _persistQueue();
    });
  }

  Future<void> playNext(MusicItem music) async {
    final quality = await _streamingQuality();
    final resolved = await _sourceResolver.resolve(music, quality);
    if (resolved == null) return;
    await _serialize(() async {
      final insertAt = ((_player.currentIndex ?? -1) + 1).clamp(
        0,
        _musicQueue.length,
      );
      _musicQueue = [..._musicQueue]..insert(insertAt, resolved.item);
      _resolvedQueue = [..._resolvedQueue]..insert(insertAt, resolved);
      await _player.insertAudioSource(insertAt, _audioSource(resolved));
      queue.add(_musicQueue.map(_toMediaItem).toList(growable: false));
      await _persistQueue();
    });
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _musicQueue.length) return;
    await _serialize(() async {
      final removingCurrent = index == _player.currentIndex;
      if (removingCurrent) _finishCurrentListen(completed: false);
      final updated = [..._musicQueue]..removeAt(index);
      final resolved = [..._resolvedQueue]..removeAt(index);
      if (updated.isEmpty) {
        await clearQueue();
        return;
      }
      _musicQueue = updated;
      _resolvedQueue = resolved;
      await _player.removeAudioSourceAt(index);
      queue.add(updated.map(_toMediaItem).toList(growable: false));
      final nextIndex = (_player.currentIndex ?? index).clamp(
        0,
        updated.length - 1,
      );
      _requestedQueueIndex = nextIndex;
      mediaItem.add(queue.value[nextIndex]);
      if (removingCurrent && _desiredPlaying) _startPlayer();
      await _persistQueue();
    });
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _musicQueue.length) return;
    final destination = newIndex.clamp(0, _musicQueue.length - 1);
    if (oldIndex == destination) return;
    await _serialize(() async {
      final updated = [..._musicQueue];
      final resolved = [..._resolvedQueue];
      updated.insert(destination, updated.removeAt(oldIndex));
      resolved.insert(destination, resolved.removeAt(oldIndex));
      _musicQueue = updated;
      _resolvedQueue = resolved;
      await _player.moveAudioSource(oldIndex, destination);
      queue.add(updated.map(_toMediaItem).toList(growable: false));
      _requestedQueueIndex = _player.currentIndex;
      await _persistQueue();
    });
  }

  Future<void> setShuffle(bool enabled) async {
    await _serialize(() async {
      if (enabled) await _player.shuffle();
      await _player.setShuffleModeEnabled(enabled);
      playbackState.add(
        playbackState.value.copyWith(
          shuffleMode: enabled
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
        ),
      );
      await _persistQueue();
    });
  }

  Future<void> cycleRepeat() async {
    final next = switch (_player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(next);
    playbackState.add(
      playbackState.value.copyWith(
        repeatMode: switch (next) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.all => AudioServiceRepeatMode.all,
          LoopMode.one => AudioServiceRepeatMode.one,
        },
      ),
    );
    await _persistQueue();
  }

  Future<void> applyPlaybackSettings(Map<String, dynamic> values) async {
    final repeat = values['repeat_mode']?.toString();
    if (repeat == null) return;
    final mode = switch (repeat) {
      'all' => LoopMode.all,
      'one' => LoopMode.one,
      _ => LoopMode.off,
    };
    await _player.setLoopMode(mode);
    playbackState.add(
      playbackState.value.copyWith(
        repeatMode: switch (mode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.all => AudioServiceRepeatMode.all,
          LoopMode.one => AudioServiceRepeatMode.one,
        },
      ),
    );
    await _persistQueue();
  }

  void _handleIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _musicQueue.length) return;
    final previous = _activeIndex;
    if (previous != null && previous != index && !_currentListenFinalized) {
      final duration = previous < _musicQueue.length
          ? _musicQueue[previous].duration
          : null;
      final completed =
          duration != null &&
          duration.inMilliseconds > 0 &&
          _lastActivePosition.inMilliseconds >=
              (duration.inMilliseconds * 0.9).round();
      if (completed) {
        _trackAt(previous, 'track_end');
        _trackAt(previous, 'complete');
      }
      _finishListenAt(previous, completed: completed);
    }
    if (previous != index) {
      _resetAnalyticsForNewTrack();
      _allowProgressRegression = true;
      _progressIndex = index;
      _lastActivePosition = Duration.zero;
    }
    _activeIndex = index;
    _requestedQueueIndex = index;
    mediaItem.add(_toMediaItem(_musicQueue[index]));
    _scheduleProgress(force: true);
    unawaited(_persistQueue());
  }

  void _handlePlayerState(PlayerState state) {
    switch (state.processingState) {
      case ProcessingState.idle:
        if (_musicQueue.isEmpty) _transition(PlaybackSignal.stopped);
      case ProcessingState.loading:
        _transition(PlaybackSignal.loadRequested, autoPlay: _desiredPlaying);
      case ProcessingState.buffering:
        _transition(PlaybackSignal.bufferingStarted);
      case ProcessingState.ready:
        if (state.playing) {
          _transition(PlaybackSignal.playbackStarted);
          _onActualPlaybackStart();
        } else if (!_desiredPlaying) {
          _transition(PlaybackSignal.pauseRequested);
        }
      case ProcessingState.completed:
        _completeQueueEnd();
    }
    if (!state.playing) {
      _stopListeningClock();
      unawaited(_persistQueue());
    }
  }

  void _onActualPlaybackStart() {
    _consecutiveFailedTracks = 0;
    if (!_hasStartedCurrent) {
      _trackCurrent('play');
      _hasStartedCurrent = true;
    } else if (_listenStopwatch == null) {
      _trackCurrent('resume');
    }
    _listenStopwatch ??= Stopwatch()..start();
  }

  void _completeQueueEnd() {
    if (!_currentListenFinalized) {
      _trackCurrent('track_end');
      _trackCurrent('complete');
      _finishCurrentListen(completed: true);
    }
    _desiredPlaying = false;
    _transition(PlaybackSignal.completed);
  }

  Future<void> _recover(Object error) async {
    if (_recovering || _musicQueue.isEmpty) return;
    _recovering = true;
    final failedIndex = _player.currentIndex ?? _requestedQueueIndex ?? 0;
    if (failedIndex < 0 || failedIndex >= _resolvedQueue.length) {
      _recovering = false;
      return;
    }
    final failed = _resolvedQueue[failedIndex];
    _transition(
      PlaybackSignal.recoverableFailure,
      message: "Couldn't play this track",
    );
    _trackAt(
      failedIndex,
      'network_failure',
      metadata: {'source_kind': failed.kind.name},
    );

    try {
      final quality = await _streamingQuality();
      final replacement = await _sourceResolver.resolve(
        failed.item,
        quality,
        refreshNetwork: true,
        failedUri: failed.uri,
      );
      if (replacement != null &&
          failedIndex == (_player.currentIndex ?? _requestedQueueIndex)) {
        _transition(PlaybackSignal.retryStarted);
        final resumePosition = _player.position;
        await _serialize(() async {
          if (failedIndex >= _resolvedQueue.length) return;
          final updated = [..._resolvedQueue];
          updated[failedIndex] = replacement;
          _resolvedQueue = updated;
          _musicQueue = updated.map((source) => source.item).toList();
          final mediaItems = _musicQueue.map(_toMediaItem).toList();
          queue.add(mediaItems);
          await _player.setAudioSources(
            updated.map(_audioSource).toList(growable: false),
            initialIndex: failedIndex,
            preload: _desiredPlaying,
          );
          if (resumePosition > Duration.zero) {
            await _player.seek(resumePosition, index: failedIndex);
          }
          mediaItem.add(mediaItems[failedIndex]);
          if (_desiredPlaying) _startPlayer();
        });
        return;
      }

      _trackAt(
        failedIndex,
        'track_failed_to_play',
        metadata: {'recovery_attempts': _machine.recoveryAttempt},
      );
      _finishListenAt(failedIndex, completed: false);
      _currentListenFinalized = true;
      final next = failedIndex + 1;
      if (_consecutiveFailedTracks < _maxConsecutiveFailedTracks &&
          next < _musicQueue.length) {
        _consecutiveFailedTracks++;
        customEvent.add({
          'type': 'track_skipped',
          'message': 'Skipped unavailable track',
          'track_id': failed.item.id,
        });
        await _selectIndexLatest(next);
      } else {
        _desiredPlaying = false;
        _transition(
          PlaybackSignal.fatalFailure,
          message: "Couldn't play this right now",
        );
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
            errorCode: 1,
            errorMessage: "Couldn't play this right now",
          ),
        );
      }
    } finally {
      _recovering = false;
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final fatal = _machine.phase == PlaybackPhase.fatalError;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_desiredPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: fatal
            ? AudioProcessingState.error
            : switch (_player.processingState) {
                ProcessingState.idle => AudioProcessingState.idle,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: _desiredPlaying && _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
        errorCode: fatal ? 1 : null,
        errorMessage: fatal ? _machine.message : null,
      ),
    );
    _scheduleProgress();
  }

  void _broadcastIntent() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_desiredPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        playing: _desiredPlaying,
        processingState: switch (_machine.phase) {
          PlaybackPhase.loading => AudioProcessingState.loading,
          PlaybackPhase.buffering => AudioProcessingState.buffering,
          PlaybackPhase.fatalError => AudioProcessingState.error,
          _ => playbackState.value.processingState,
        },
        errorCode: null,
        errorMessage: null,
      ),
    );
  }

  void _transition(PlaybackSignal signal, {bool? autoPlay, String? message}) {
    _machine = _machine.transition(
      signal,
      autoPlay: autoPlay,
      message: message,
    );
    _machineController.add(_machine);
  }

  void _failLoadingIfCurrent(int generation) {
    if (generation != _loadGeneration) return;
    _desiredPlaying = false;
    _transition(
      PlaybackSignal.fatalFailure,
      message: 'This track is not available',
    );
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
        errorCode: 1,
        errorMessage: 'This track is not available',
      ),
    );
  }

  MediaItem _toMediaItem(MusicItem item) => mediaItemFromMusicItem(item);

  AudioSource _audioSource(ResolvedPlaybackSource source) =>
      AudioSource.uri(source.uri, tag: _toMediaItem(source.item));

  Future<void> _persistQueue() {
    return _store.saveQueue(
      _musicQueue.map((item) => item.toJson()).toList(growable: false),
      _player.currentIndex ?? _requestedQueueIndex ?? 0,
      positionMs: _player.position.inMilliseconds,
      shuffle: _player.shuffleModeEnabled,
      repeatMode: switch (_player.loopMode) {
        LoopMode.off => 'off',
        LoopMode.all => 'all',
        LoopMode.one => 'one',
      },
    );
  }

  void _scheduleQueuePersistence() {
    if (!_player.playing || _musicQueue.isEmpty) return;
    _persistenceDebounce?.cancel();
    _persistenceDebounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(_persistQueue()),
    );
  }

  void _scheduleProgress({bool force = false}) {
    if (force) {
      _progressDebounce?.cancel();
      _emitProgress();
      return;
    }
    if (_progressDebounce?.isActive == true) return;
    _progressDebounce = Timer(const Duration(milliseconds: 200), _emitProgress);
  }

  void _emitProgress() {
    final index = _player.currentIndex;
    var position = _player.position;
    if (_progressIndex == index &&
        !_allowProgressRegression &&
        position < _lastProgress.position) {
      position = _lastProgress.position;
    }
    _progressIndex = index;
    _allowProgressRegression = false;
    final duration = _player.duration;
    final boundedPosition = duration == null || position <= duration
        ? position
        : duration;
    final buffered = _player.bufferedPosition < boundedPosition
        ? boundedPosition
        : _player.bufferedPosition;
    _lastProgress = PlaybackProgress(
      position: boundedPosition,
      buffered: buffered,
      duration: duration,
    );
    _progressController.add(_lastProgress);
  }

  Future<String> _streamingQuality() async {
    final fallback = _store.readSetting('playback_streaming_quality', 'auto');
    if (fallback != 'auto') return fallback;
    var quality = 'medium';
    try {
      final connections = await Connectivity().checkConnectivity();
      if (connections.contains(ConnectivityResult.wifi) ||
          connections.contains(ConnectivityResult.ethernet)) {
        quality = _store.readSetting('playback_wifi_streaming_quality', 'high');
      } else {
        quality = _store.readSetting(
          'playback_mobile_streaming_quality',
          'medium',
        );
      }
    } catch (_) {}
    return quality;
  }

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _mutationTail.then((_) => action());
    _mutationTail = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }

  void _trackCurrent(String event, {Map<String, dynamic>? metadata}) {
    final index = _player.currentIndex ?? _activeIndex;
    if (index != null) _trackAt(index, event, metadata: metadata);
  }

  void _trackAt(int index, String event, {Map<String, dynamic>? metadata}) {
    if (index < 0 || index >= _musicQueue.length) return;
    _analytics?.track(
      event,
      _musicQueue[index],
      source: _queueSource,
      positionMs: _lastActivePosition.inMilliseconds,
      metadata: metadata,
    );
  }

  void _stopListeningClock() {
    final stopwatch = _listenStopwatch;
    if (stopwatch == null) return;
    stopwatch.stop();
    _accumulatedListenMs += stopwatch.elapsedMilliseconds;
    _listenStopwatch = null;
  }

  void _finishCurrentListen({required bool completed}) {
    final index = _player.currentIndex ?? _activeIndex;
    if (index == null) return;
    _finishListenAt(index, completed: completed);
    _currentListenFinalized = true;
  }

  void _finishListenAt(int index, {required bool completed}) {
    _stopListeningClock();
    if (index < 0 || index >= _musicQueue.length || _accumulatedListenMs <= 0) {
      return;
    }
    final durationMs = _musicQueue[index].duration?.inMilliseconds;
    final playedMs = durationMs == null
        ? _accumulatedListenMs
        : _accumulatedListenMs.clamp(0, durationMs);
    _analytics?.recordListen(
      _musicQueue[index],
      source: _queueSource,
      playedMs: playedMs,
      completed: completed,
    );
    _accumulatedListenMs = 0;
  }

  void _resetAnalyticsForNewTrack() {
    _stopListeningClock();
    _accumulatedListenMs = 0;
    _hasStartedCurrent = false;
    _currentListenFinalized = false;
  }
}
