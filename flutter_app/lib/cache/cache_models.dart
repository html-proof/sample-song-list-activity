class ByteRange {
  final int start;
  final int end;

  const ByteRange(this.start, this.end);

  int get length => end >= start ? (end - start + 1) : 0;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory ByteRange.fromJson(Map<String, dynamic> json) =>
      ByteRange(json['start'] as int? ?? 0, json['end'] as int? ?? 0);

  bool contains(int position) => position >= start && position <= end;

  bool overlapsOrAdjacent(ByteRange other) =>
      start <= other.end + 1 && end + 1 >= other.start;

  ByteRange merge(ByteRange other) => ByteRange(
        start < other.start ? start : other.start,
        end > other.end ? end : other.end,
      );

  @override
  String toString() => 'bytes=$start-$end';
}

class CacheEntry {
  final String key;
  final String songId;
  final String userId;
  final String audioQuality;
  final String streamVersion;
  final String fileName;
  final int totalBytes;
  final List<ByteRange> cachedRanges;
  final String? etag;
  final String mimeType;
  final DateTime lastAccessedAt;
  final DateTime expiresAt;
  final bool isComplete;

  const CacheEntry({
    required this.key,
    required this.songId,
    required this.userId,
    required this.audioQuality,
    required this.streamVersion,
    required this.fileName,
    required this.totalBytes,
    required this.cachedRanges,
    this.etag,
    this.mimeType = 'audio/mp4',
    required this.lastAccessedAt,
    required this.expiresAt,
    this.isComplete = false,
  });

  int get cachedBytes {
    var sum = 0;
    for (final r in cachedRanges) {
      sum += r.length;
    }
    return sum;
  }

  bool isExpired(DateTime now) => now.isAfter(expiresAt);

  CacheEntry copyWith({
    String? key,
    String? songId,
    String? userId,
    String? audioQuality,
    String? streamVersion,
    String? fileName,
    int? totalBytes,
    List<ByteRange>? cachedRanges,
    String? etag,
    String? mimeType,
    DateTime? lastAccessedAt,
    DateTime? expiresAt,
    bool? isComplete,
  }) {
    return CacheEntry(
      key: key ?? this.key,
      songId: songId ?? this.songId,
      userId: userId ?? this.userId,
      audioQuality: audioQuality ?? this.audioQuality,
      streamVersion: streamVersion ?? this.streamVersion,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      cachedRanges: cachedRanges ?? this.cachedRanges,
      etag: etag ?? this.etag,
      mimeType: mimeType ?? this.mimeType,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'songId': songId,
        'userId': userId,
        'audioQuality': audioQuality,
        'streamVersion': streamVersion,
        'fileName': fileName,
        'totalBytes': totalBytes,
        'cachedRanges': cachedRanges.map((r) => r.toJson()).toList(),
        'etag': etag,
        'mimeType': mimeType,
        'lastAccessedAt': lastAccessedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'isComplete': isComplete,
      };

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    final rawRanges = json['cachedRanges'] as List? ?? const [];
    final ranges = rawRanges
        .whereType<Map>()
        .map((r) => ByteRange.fromJson(Map<String, dynamic>.from(r)))
        .toList();

    return CacheEntry(
      key: '${json['key'] ?? ''}',
      songId: '${json['songId'] ?? ''}',
      userId: '${json['userId'] ?? 'guest'}',
      audioQuality: '${json['audioQuality'] ?? 'automatic'}',
      streamVersion: '${json['streamVersion'] ?? '1'}',
      fileName: '${json['fileName'] ?? ''}',
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      cachedRanges: ranges,
      etag: json['etag'] as String?,
      mimeType: '${json['mimeType'] ?? 'audio/mp4'}',
      lastAccessedAt: DateTime.tryParse('${json['lastAccessedAt']}') ?? DateTime.now(),
      expiresAt: DateTime.tryParse('${json['expiresAt']}') ??
          DateTime.now().add(const Duration(hours: 24)),
      isComplete: json['isComplete'] == true,
    );
  }
}

class CacheMetrics {
  int hits = 0;
  int misses = 0;
  int bytesServedFromCache = 0;
  int bytesDownloaded = 0;
  int evictionCount = 0;
  int rebufferCount = 0;
  int rebufferDurationMs = 0;
  int downloadFailures = 0;
  int streamUrlRefreshes = 0;

  void recordHit(int bytes) {
    hits++;
    bytesServedFromCache += bytes;
  }

  void recordMiss(int bytes) {
    misses++;
    bytesDownloaded += bytes;
  }

  void recordRebuffer(int durationMs) {
    rebufferCount++;
    rebufferDurationMs += durationMs;
  }

  Map<String, dynamic> toJson() => {
        'hits': hits,
        'misses': misses,
        'bytesServedFromCache': bytesServedFromCache,
        'bytesDownloaded': bytesDownloaded,
        'evictionCount': evictionCount,
        'rebufferCount': rebufferCount,
        'rebufferDurationMs': rebufferDurationMs,
        'downloadFailures': downloadFailures,
        'streamUrlRefreshes': streamUrlRefreshes,
      };
}
