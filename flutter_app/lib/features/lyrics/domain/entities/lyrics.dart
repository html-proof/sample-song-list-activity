import 'package:music_hub_app/features/lyrics/domain/entities/lyric_line.dart';

enum LyricsStatus {
  available,
  plainOnly,
  instrumental,
  notFound,
  unsupported,
  temporaryError,
  offline,
}

enum LyricsSyncType { word, line, plain }

class Lyrics {
  const Lyrics({
    required this.songId,
    required this.status,
    this.syncType,
    this.language,
    this.offset = Duration.zero,
    this.confidence,
    this.lines = const [],
    this.plainText,
    this.provider,
    this.lyricsVersion,
    this.fetchedAt,
    this.songIdentityHash,
  });

  final String songId;
  final LyricsStatus status;
  final LyricsSyncType? syncType;
  final String? language;
  final Duration offset;
  final double? confidence;
  final List<LyricLine> lines;
  final String? plainText;
  final String? provider;
  final String? lyricsVersion;
  final DateTime? fetchedAt;
  final String? songIdentityHash;

  bool get synchronized => status == LyricsStatus.available && lines.isNotEmpty;

  factory Lyrics.offline(String songId) =>
      Lyrics(songId: songId, status: LyricsStatus.offline);

  factory Lyrics.fromJson(Map<String, dynamic> json) => Lyrics(
    songId: json['song_id']?.toString() ?? '',
    status: _status(json['status']?.toString()),
    syncType: _syncType(json['sync_type']?.toString()),
    language: json['language']?.toString(),
    offset: Duration(
      milliseconds: int.tryParse(json['offset_ms']?.toString() ?? '') ?? 0,
    ),
    confidence: (json['confidence'] as num?)?.toDouble(),
    lines: _maps(json['lines']).map(LyricLine.fromJson).toList(growable: false),
    plainText: json['plain_text']?.toString(),
    provider: json['provider']?.toString(),
    lyricsVersion: json['lyrics_version']?.toString(),
    fetchedAt: DateTime.tryParse(json['fetched_at']?.toString() ?? ''),
    songIdentityHash: json['song_identity_hash']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'song_id': songId,
    'status': switch (status) {
      LyricsStatus.plainOnly => 'plain_only',
      LyricsStatus.notFound => 'not_found',
      LyricsStatus.temporaryError => 'temporary_error',
      _ => status.name,
    },
    if (syncType != null) 'sync_type': syncType!.name,
    if (language != null) 'language': language,
    'offset_ms': offset.inMilliseconds,
    if (confidence != null) 'confidence': confidence,
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
    if (plainText != null) 'plain_text': plainText,
    if (provider != null) 'provider': provider,
    if (lyricsVersion != null) 'lyrics_version': lyricsVersion,
    if (fetchedAt != null) 'fetched_at': fetchedAt!.toIso8601String(),
    if (songIdentityHash != null) 'song_identity_hash': songIdentityHash,
  };
}

LyricsStatus _status(String? value) => switch (value) {
  'available' => LyricsStatus.available,
  'plain_only' => LyricsStatus.plainOnly,
  'instrumental' => LyricsStatus.instrumental,
  'unsupported' => LyricsStatus.unsupported,
  'temporary_error' => LyricsStatus.temporaryError,
  'offline' => LyricsStatus.offline,
  _ => LyricsStatus.notFound,
};

LyricsSyncType? _syncType(String? value) => switch (value) {
  'word' => LyricsSyncType.word,
  'line' => LyricsSyncType.line,
  'plain' => LyricsSyncType.plain,
  _ => null,
};

Iterable<Map<String, dynamic>> _maps(dynamic value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) yield item.cast<String, dynamic>();
  }
}
