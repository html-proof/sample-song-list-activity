import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/lyrics/data/lyrics_remote_datasource.dart';
import 'package:music_hub_app/features/lyrics/data/lyrics_repository_impl.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyric_line.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyrics.dart';
import 'package:music_hub_app/features/lyrics/domain/repositories/lyrics_repository.dart';
import 'package:music_hub_app/features/player/presentation/player_providers.dart';

final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  return LyricsRepositoryImpl(
    LyricsRemoteDataSource(ref.watch(apiClientProvider)),
    ref.watch(localStoreProvider),
  );
});

final lyricsConnectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  return Connectivity().onConnectivityChanged;
});

final lyricsControllerProvider = StateNotifierProvider.autoDispose
    .family<LyricsController, AsyncValue<Lyrics>, LyricsRequest>((
      ref,
      request,
    ) {
      final controller = LyricsController(
        ref.watch(lyricsRepositoryProvider),
        request,
      )..load();
      ref.listen(lyricsConnectivityProvider, (previous, next) {
        final wasOffline = _offline(previous?.valueOrNull);
        final isOnline = !_offline(next.valueOrNull);
        if (wasOffline && isOnline) controller.load(force: true);
      });
      return controller;
    });

final lyricsPrefetchProvider = Provider<void>((ref) {
  final media = ref.watch(currentMediaItemProvider).valueOrNull;
  final queue =
      ref.watch(playerQueueProvider).valueOrNull ?? const <MediaItem>[];
  final queueIndex = ref.watch(playbackStateProvider).valueOrNull?.queueIndex;
  final connections = ref.watch(lyricsConnectivityProvider).valueOrNull;
  if (media == null || _offline(connections)) return;

  final repository = ref.watch(lyricsRepositoryProvider);
  final currentRequest = lyricsRequestForMedia(media);
  if (currentRequest != null) {
    unawaited(repository.prefetch(currentRequest));
  }

  final currentIndex =
      queueIndex ?? queue.indexWhere((item) => item.id == media.id);
  if (currentIndex >= 0 && currentIndex + 1 < queue.length) {
    final nextRequest = lyricsRequestForMedia(queue[currentIndex + 1]);
    if (nextRequest != null) unawaited(repository.prefetch(nextRequest));
  }
});

final currentLyricLineProvider = Provider.autoDispose.family<int, Lyrics>((
  ref,
  lyrics,
) {
  final position = ref.watch(
    playerPositionProvider.select(
      (value) => value.valueOrNull ?? Duration.zero,
    ),
  );
  return findCurrentLyricLine(lyrics.lines, position, offset: lyrics.offset);
});

class LyricsController extends StateNotifier<AsyncValue<Lyrics>> {
  LyricsController(this._repository, this._request)
    : super(const AsyncLoading());

  final LyricsRepository _repository;
  final LyricsRequest _request;
  CancelToken? _cancelToken;
  int _generation = 0;

  Future<void> load({bool force = false}) async {
    final generation = ++_generation;
    _cancelToken?.cancel('Lyrics request superseded');
    _cancelToken = CancelToken();
    final cached = _repository.readCached(_request);
    if (cached != null && !force) {
      state = AsyncData(cached);
    } else {
      state = const AsyncLoading();
    }
    try {
      final result = await _repository.fetch(
        _request,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) return;
      if (cached != null && result.status == LyricsStatus.temporaryError) {
        return;
      }
      state = AsyncData(result);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      if (cached != null) return;
      state = AsyncData(Lyrics.offline(_request.songId));
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken?.cancel('Lyrics controller disposed');
    super.dispose();
  }
}

LyricsRequest? lyricsRequestForMedia(MediaItem media) {
  final rawValue = media.extras?['raw'];
  final raw = rawValue is Map
      ? rawValue.cast<String, dynamic>()
      : const <String, dynamic>{};
  final songId = (raw['seokey'] ?? media.id).toString().trim();
  if (songId.isEmpty) return null;
  final identity = [
    raw['provider'],
    raw['provider_id'],
    raw['track_id'],
    raw['isrc'],
    songId,
    media.title,
    media.artist,
    media.album,
    media.duration?.inMilliseconds,
  ].map((value) => value?.toString().trim().toLowerCase() ?? '').join('\u001f');
  return LyricsRequest(songId: songId, identityKey: _fnv1a(identity));
}

int findCurrentLyricLine(
  List<LyricLine> lines,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final adjusted = position - offset;
  var low = 0;
  var high = lines.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final line = lines[middle];
    if (adjusted < line.start) {
      high = middle - 1;
    } else if (adjusted >= line.end) {
      low = middle + 1;
    } else {
      return middle;
    }
  }
  return -1;
}

String _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

bool _offline(List<ConnectivityResult>? results) =>
    results?.isNotEmpty == true &&
    results!.every((result) => result == ConnectivityResult.none);
