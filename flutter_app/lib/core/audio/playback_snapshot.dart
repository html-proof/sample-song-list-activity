/// A durable picture of the playback session.
///
/// Written continuously while playing and on every meaningful player event, so
/// a cold start can restore the exact song and position without touching the
/// network. Everything here is cheap to serialise; audio bytes live on disk.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.songId,
    required this.title,
    required this.artist,
    required this.position,
    required this.queueIndex,
    required this.queueSongIds,
    required this.wasPlaying,
    required this.updatedAt,
    this.streamUrl,
    this.streamUrlExpiresAt,
    this.artworkUrl,
    this.duration,
    this.cacheKey,
  });

  /// A track this close to its end is treated as finished on restore, so the
  /// user resumes on the next song instead of the final moment of the old one.
  static const completionTolerance = Duration(seconds: 3);

  final String songId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? streamUrl;
  final DateTime? streamUrlExpiresAt;

  final Duration position;
  final Duration? duration;

  final int queueIndex;
  final List<String> queueSongIds;

  final bool wasPlaying;
  final DateTime updatedAt;

  final String? cacheKey;

  /// True when the saved position sat within [completionTolerance] of the end.
  bool get wasEffectivelyComplete {
    final total = duration;
    if (total == null || total <= Duration.zero) return false;
    return total - position <= completionTolerance;
  }

  /// A stream URL is only worth reusing while its signed token is still valid.
  bool get hasFreshStreamUrl {
    if (streamUrl == null || streamUrl!.isEmpty) return false;
    final expiry = streamUrlExpiresAt;
    return expiry == null || expiry.isAfter(DateTime.now());
  }

  Map<String, dynamic> toJson() => {
    'song_id': songId,
    'title': title,
    'artist': artist,
    'artwork_url': artworkUrl,
    'stream_url': streamUrl,
    'stream_url_expires_at': streamUrlExpiresAt?.millisecondsSinceEpoch,
    'position_ms': position.inMilliseconds,
    'duration_ms': duration?.inMilliseconds,
    'queue_index': queueIndex,
    'queue_song_ids': queueSongIds,
    'was_playing': wasPlaying,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'cache_key': cacheKey,
  };

  static PlaybackSnapshot? fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return null;
    final songId = json['song_id']?.toString();
    if (songId == null || songId.isEmpty) return null;
    return PlaybackSnapshot(
      songId: songId,
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      artworkUrl: json['artwork_url']?.toString(),
      streamUrl: json['stream_url']?.toString(),
      streamUrlExpiresAt: _time(json['stream_url_expires_at']),
      position: _duration(json['position_ms']) ?? Duration.zero,
      duration: _duration(json['duration_ms']),
      queueIndex: _int(json['queue_index']) ?? 0,
      queueSongIds: json['queue_song_ids'] is List
          ? (json['queue_song_ids'] as List)
                .map((value) => value.toString())
                .toList(growable: false)
          : const [],
      wasPlaying: json['was_playing'] == true,
      updatedAt: _time(json['updated_at']) ?? DateTime.now(),
      cacheKey: json['cache_key']?.toString(),
    );
  }

  static int? _int(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static Duration? _duration(Object? value) {
    final milliseconds = _int(value);
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  static DateTime? _time(Object? value) {
    final milliseconds = _int(value);
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}
