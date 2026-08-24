import 'package:dio/dio.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyrics.dart';

class LyricsRequest {
  const LyricsRequest({required this.songId, required this.identityKey});

  final String songId;
  final String identityKey;

  @override
  bool operator ==(Object other) =>
      other is LyricsRequest &&
      other.songId == songId &&
      other.identityKey == identityKey;

  @override
  int get hashCode => Object.hash(songId, identityKey);
}

abstract class LyricsRepository {
  Lyrics? readCached(LyricsRequest request);

  Future<Lyrics> fetch(LyricsRequest request, {CancelToken? cancelToken});

  Future<void> prefetch(LyricsRequest request);
}
