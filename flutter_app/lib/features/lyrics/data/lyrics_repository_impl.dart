import 'dart:async';

import 'package:dio/dio.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/features/lyrics/data/lyrics_remote_datasource.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyrics.dart';
import 'package:music_hub_app/features/lyrics/domain/repositories/lyrics_repository.dart';

class LyricsRepositoryImpl implements LyricsRepository {
  LyricsRepositoryImpl(this._remote, this._store);

  static const _contentTtl = Duration(days: 7);
  static const _negativeTtl = Duration(hours: 1);

  final LyricsRemoteDataSource _remote;
  final LocalStore _store;
  final Map<LyricsRequest, Future<Lyrics>> _prefetches = {};

  @override
  Lyrics? readCached(LyricsRequest request) {
    final value = _store.readCached(_key(request));
    return value is Map ? Lyrics.fromJson(value.cast<String, dynamic>()) : null;
  }

  @override
  Future<Lyrics> fetch(
    LyricsRequest request, {
    CancelToken? cancelToken,
  }) async {
    final lyrics = await _remote.fetch(
      request.songId,
      cancelToken: cancelToken,
    );
    if (lyrics.songId != request.songId) {
      throw StateError('Lyrics response belongs to a different song');
    }
    if (lyrics.status != LyricsStatus.temporaryError &&
        lyrics.status != LyricsStatus.offline) {
      final stable =
          lyrics.status == LyricsStatus.available ||
          lyrics.status == LyricsStatus.plainOnly ||
          lyrics.status == LyricsStatus.instrumental;
      await _store.putCached(
        _key(request),
        lyrics.toJson(),
        ttl: stable ? _contentTtl : _negativeTtl,
      );
    }
    return lyrics;
  }

  @override
  Future<void> prefetch(LyricsRequest request) async {
    if (readCached(request) != null) return;
    final operation = _prefetches.putIfAbsent(request, () => fetch(request));
    try {
      await operation;
    } catch (_) {
      // Prefetch is opportunistic and must never affect playback.
    } finally {
      if (identical(_prefetches[request], operation)) {
        _prefetches.remove(request);
      }
    }
  }

  static String _key(LyricsRequest request) =>
      'lyrics:${request.songId}:${request.identityKey}';
}
