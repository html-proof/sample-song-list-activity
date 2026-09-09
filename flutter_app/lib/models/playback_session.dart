/// Authoritative state representing an active playback session for a track.
/// Once created, the [lockedBitrate], [lockedQuality], and [streamUrl]
/// MUST NOT change for the lifetime of the currently playing track.
class PlaybackSession {
  final String trackId;
  final String title;
  final String streamUrl;
  final String codec;
  final int lockedBitrate; // in kbps (e.g. 64, 128, 160, 320)
  final String lockedQuality; // 'low', 'normal', 'high', 'very_high'
  final Duration duration;
  final String cacheKey;
  final String requestId;
  final DateTime startTime;

  Duration position;
  Duration bufferedPosition;
  int networkBytesDownloaded;
  int cacheBytesRead;
  bool isPlaying;
  int retryCount;
  int redirectCount;
  bool duplicateRequestPrevented;

  PlaybackSession({
    required this.trackId,
    required this.title,
    required this.streamUrl,
    this.codec = 'AAC',
    required this.lockedBitrate,
    required this.lockedQuality,
    required this.duration,
    required this.cacheKey,
    required this.requestId,
    DateTime? startTime,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.networkBytesDownloaded = 0,
    this.cacheBytesRead = 0,
    this.isPlaying = false,
    this.retryCount = 0,
    this.redirectCount = 0,
    this.duplicateRequestPrevented = false,
  }) : startTime = startTime ?? DateTime.now();

  /// Total audio data bytes processed for this session.
  int get totalBytesProcessed => networkBytesDownloaded + cacheBytesRead;

  /// Expected file size in megabytes based on locked bitrate and duration:
  /// file_size_MB = bitrate_kbps * duration_seconds / 8 / 1000
  double get expectedFileSizeBytes {
    final secs = duration.inSeconds > 0 ? duration.inSeconds : 240;
    return (lockedBitrate * secs) / 8 / 1000;
  }

  /// Actual network data downloaded in megabytes.
  double get networkDownloadedMb => networkBytesDownloaded / (1024 * 1024);

  /// Actual cache data read in megabytes.
  double get cacheReadMb => cacheBytesRead / (1024 * 1024);

  /// True if network downloaded bytes significantly exceed expected size (> 25% overhead).
  bool get isSuspiciousConsumption {
    if (duration.inSeconds <= 0) return false;
    final expectedMb = expectedFileSizeBytes;
    return networkDownloadedMb > (expectedMb * 1.25) && networkBytesDownloaded > 1024 * 1024;
  }

  /// Generate structured TRACK DATA REPORT for debugging and analytics.
  String generateTrackDataReport() {
    final expectedMb = expectedFileSizeBytes.toStringAsFixed(2);
    final downloadedMb = networkDownloadedMb.toStringAsFixed(2);
    final cacheMb = cacheReadMb.toStringAsFixed(2);

    final buffer = StringBuffer();
    buffer.writeln('========================================');
    buffer.writeln('          TRACK DATA REPORT             ');
    buffer.writeln('========================================');
    buffer.writeln('Track ID: $trackId');
    buffer.writeln('Title: $title');
    buffer.writeln('Duration: ${duration.inSeconds} sec');
    buffer.writeln('Codec: $codec');
    buffer.writeln('Quality: $lockedQuality');
    buffer.writeln('Locked Bitrate: $lockedBitrate kbps');
    buffer.writeln('Expected File Size: $expectedMb MB');
    buffer.writeln('Network Downloaded: $downloadedMb MB');
    buffer.writeln('Cache Read: $cacheMb MB');
    buffer.writeln('Duplicate Request Prevented: $duplicateRequestPrevented');
    buffer.writeln('Retry Count: $retryCount');
    buffer.writeln('Redirect Count: $redirectCount');
    if (isSuspiciousConsumption) {
      buffer.writeln('WARNING: Data consumption exceeds expected size by >25%!');
    }
    buffer.writeln('========================================');
    return buffer.toString();
  }

  PlaybackSession copyWith({
    Duration? position,
    Duration? bufferedPosition,
    int? networkBytesDownloaded,
    int? cacheBytesRead,
    bool? isPlaying,
    int? retryCount,
    int? redirectCount,
    bool? duplicateRequestPrevented,
  }) {
    final s = PlaybackSession(
      trackId: trackId,
      title: title,
      streamUrl: streamUrl,
      codec: codec,
      lockedBitrate: lockedBitrate,
      lockedQuality: lockedQuality,
      duration: duration,
      cacheKey: cacheKey,
      requestId: requestId,
      startTime: startTime,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      networkBytesDownloaded: networkBytesDownloaded ?? this.networkBytesDownloaded,
      cacheBytesRead: cacheBytesRead ?? this.cacheBytesRead,
      isPlaying: isPlaying ?? this.isPlaying,
      retryCount: retryCount ?? this.retryCount,
      redirectCount: redirectCount ?? this.redirectCount,
      duplicateRequestPrevented: duplicateRequestPrevented ?? this.duplicateRequestPrevented,
    );
    return s;
  }
}
