import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler(this._store) {
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen(_handleIndexChanged);
    _player.positionStream.listen((_) => _scheduleQueuePersistence());
    _player.errorStream.listen((error) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          errorCode: 1,
          errorMessage: "Couldn't play this track",
        ),
      );
    });
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(skipToNext());
      }
      if (!state.playing) unawaited(_persistQueue());
    });
  }

  final LocalStore _store;
  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: true,
    androidApplyAudioAttributes: true,
    handleAudioSessionActivation: true,
  );
  List<MusicItem> _musicQueue = const [];
  Timer? _persistenceDebounce;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  int? get currentIndex => _player.currentIndex;

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    final saved = _store.readQueue();
    final items = saved?['items'];
    if (items is List) {
      final restored = items
          .whereType<Map>()
          .map((item) => MusicItem.fromJson(item.cast<String, dynamic>()))
          .where((item) => item.playable)
          .toList(growable: false);
      if (restored.isNotEmpty) {
        final index = (saved?['index'] as int? ?? 0).clamp(
          0,
          restored.length - 1,
        );
        await setMusicQueue(
          restored,
          initialIndex: index,
          autoPlay: false,
          persist: false,
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
        final positionMs = int.tryParse(
          saved?['position_ms']?.toString() ?? '',
        );
        if (positionMs != null && positionMs > 0) {
          await _player.seek(Duration(milliseconds: positionMs), index: index);
        }
        _broadcastState(_player.playbackEvent);
      }
    }
  }

  Future<void> playItems(List<MusicItem> items, {int initialIndex = 0}) {
    return setMusicQueue(items, initialIndex: initialIndex, autoPlay: true);
  }

  Future<void> playItem(MusicItem item) => playItems([item]);

  Future<void> setMusicQueue(
    List<MusicItem> items, {
    int initialIndex = 0,
    bool autoPlay = false,
    bool persist = true,
  }) async {
    final requested = initialIndex >= 0 && initialIndex < items.length
        ? items[initialIndex]
        : null;
    final playable = items
        .where((item) => item.playable)
        .toList(growable: false);
    if (playable.isEmpty) return;
    final requestedIndex = requested == null
        ? -1
        : playable.indexWhere((item) => item.id == requested.id);
    final safeIndex = (requestedIndex < 0 ? initialIndex : requestedIndex)
        .clamp(0, playable.length - 1);
    _musicQueue = playable;
    final quality = await _streamingQuality();
    final mediaItems = playable.map(_toMediaItem).toList(growable: false);
    queue.add(mediaItems);
    await _player.setAudioSources(
      playable
          .map((item) => _audioSource(item, quality))
          .toList(growable: false),
      initialIndex: safeIndex,
      preload: autoPlay,
    );
    mediaItem.add(mediaItems[safeIndex]);
    if (persist) await _persistQueue();
    if (autoPlay) await play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  Future<void> clearQueue() async {
    _persistenceDebounce?.cancel();
    _musicQueue = const [];
    queue.add(const []);
    mediaItem.add(null);
    await _store.saveQueue(const [], 0, positionMs: 0);
    await stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _musicQueue.length) {
      await _player.seek(Duration.zero, index: index);
      await _persistQueue();
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final raw = mediaItem.extras?['raw'];
    if (raw is! Map) return;
    final music = MusicItem.fromJson(raw.cast<String, dynamic>());
    if (!music.playable) return;
    final quality = await _streamingQuality();
    _musicQueue = [..._musicQueue, music];
    await _player.addAudioSource(_audioSource(music, quality));
    queue.add(_musicQueue.map(_toMediaItem).toList(growable: false));
    await _persistQueue();
  }

  Future<void> playNext(MusicItem music) async {
    if (!music.playable) return;
    final insertAt = ((_player.currentIndex ?? -1) + 1).clamp(
      0,
      _musicQueue.length,
    );
    final quality = await _streamingQuality();
    _musicQueue = [..._musicQueue]..insert(insertAt, music);
    await _player.insertAudioSource(insertAt, _audioSource(music, quality));
    queue.add(_musicQueue.map(_toMediaItem).toList(growable: false));
    await _persistQueue();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _musicQueue.length) return;
    final current = _player.currentIndex ?? 0;
    final updated = [..._musicQueue]..removeAt(index);
    if (updated.isEmpty) {
      await clearQueue();
      return;
    }
    _musicQueue = updated;
    await _player.removeAudioSourceAt(index);
    queue.add(updated.map(_toMediaItem).toList(growable: false));
    final nextIndex =
        _player.currentIndex ?? current.clamp(0, updated.length - 1);
    if (nextIndex >= 0 && nextIndex < queue.value.length) {
      mediaItem.add(queue.value[nextIndex]);
    }
    await _persistQueue();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _musicQueue.length) return;
    if (oldIndex < newIndex) newIndex -= 1;
    final destination = newIndex.clamp(0, _musicQueue.length - 1);
    if (oldIndex == destination) return;
    final updated = [..._musicQueue];
    final item = updated.removeAt(oldIndex);
    updated.insert(destination, item);
    _musicQueue = updated;
    await _player.moveAudioSource(oldIndex, destination);
    queue.add(updated.map(_toMediaItem).toList(growable: false));
    await _persistQueue();
  }

  Future<void> setShuffle(bool enabled) async {
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
    if (repeat != null) {
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
  }

  void _handleIndexChanged(int? index) {
    final items = queue.value;
    if (index == null || index < 0 || index >= items.length) return;
    mediaItem.add(items[index]);
    unawaited(_persistQueue());
  }

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  MediaItem _toMediaItem(MusicItem item) => MediaItem(
    id: item.id,
    title: item.title,
    artist: item.subtitle,
    album: (item.raw['album'] ?? item.raw['album_name'])?.toString(),
    artUri: item.imageUrl == null ? null : Uri.tryParse(item.imageUrl!),
    duration: item.duration,
    extras: {'streamUrl': item.streamUrl, 'raw': item.raw},
  );

  Future<void> _persistQueue() {
    return _store.saveQueue(
      _musicQueue.map((item) => item.toJson()).toList(growable: false),
      _player.currentIndex ?? 0,
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

  AudioSource _audioSource(MusicItem item, String quality) => AudioSource.uri(
    Uri.parse(_streamUrl(item, quality) ?? item.streamUrl!),
    tag: _toMediaItem(item),
  );

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

  String? _streamUrl(MusicItem item, String quality) {
    final streams = item.raw['stream_urls'];
    if (streams is! Map) return item.streamUrl;
    final urls = streams['urls'];
    if (urls is! Map) return item.streamUrl;
    final keys = switch (quality) {
      'low' => const [
        'low_quality',
        'medium_quality',
        'high_quality',
        'very_high_quality',
      ],
      'medium' => const [
        'medium_quality',
        'high_quality',
        'low_quality',
        'very_high_quality',
      ],
      _ => const [
        'very_high_quality',
        'high_quality',
        'medium_quality',
        'low_quality',
      ],
    };
    for (final key in keys) {
      final value = urls[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return item.streamUrl;
  }
}
