import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models.dart';
import '../network_policy.dart';
import 'audio_cache.dart';
import 'segment_downloader.dart';

class QueuePrefetchManager {
  QueuePrefetchManager({
    required this.audioCache,
    required this.downloader,
    this.policy,
    this.connection,
  });

  final AudioCache audioCache;
  final SegmentDownloader downloader;
  final DataUsagePolicy? policy;
  final ConnectionMonitor? connection;

  String? _activePrefetchKey;
  CancellationToken? _cancelToken;

  static bool _isHlsStream(String url) {
    if (url.isEmpty) return false;
    final clean = url.toLowerCase().split('?').first;
    return clean.endsWith('.m3u8') || clean.contains('/hls/') || clean.contains('.m3u8');
  }

  /// Prefetch the small initial segment (~256 KB) of the upcoming track.
  Future<void> prefetchNextTrack(
    Track? nextTrack, {
    required String userId,
    String audioQuality = 'automatic',
  }) async {
    cancel();
    if (nextTrack == null || nextTrack.streamUrl.isEmpty) return;

    final connState = connection?.state ?? const NetworkState();
    if (policy != null) {
      if (!policy!.canPreloadNextSong(connState)) {
        return; // Data saver or preloading disabled
      }
      // When Data Saver is ON, disable speculative audio preload completely
      if (policy!.dataSaverEnabled) {
        return;
      }
    }

    final effectiveQuality = policy?.qualityFor(connState) ?? audioQuality;
    final preferredUrl = nextTrack.getStreamUrlForQuality(effectiveQuality);
    final targetUrl = preferredUrl.isNotEmpty ? preferredUrl : nextTrack.streamUrl;
    if (targetUrl.isEmpty || _isHlsStream(targetUrl)) return;

    final key = AudioCache.generateKey(
      userId: userId,
      songId: nextTrack.id.isNotEmpty ? nextTrack.id : nextTrack.seokey,
      audioQuality: effectiveQuality,
    );

    // If initial 256 KB range is already cached, no need to touch network
    const int prefetchStart = 0;
    const int prefetchEnd = 262143; // 256 KB chunk
    if (audioCache.hasRange(key, prefetchStart, prefetchEnd)) return;

    final token = CancellationToken();
    _cancelToken = token;
    _activePrefetchKey = key;

    try {
      final uri = Uri.parse(targetUrl);
      // Consistent lockKey format so player and prefetch share deduplication
      final lockKey = '$key-$prefetchStart-$prefetchEnd';
      final result = await downloader.downloadRange(
        uri,
        lockKey: lockKey,
        start: prefetchStart,
        end: prefetchEnd,
        cancelToken: token,
      );

      if (token.isCancelled || _activePrefetchKey != key) return;

      if (result != null && result.bytes.isNotEmpty) {
        await audioCache.writeSegment(
          key: key,
          songId: nextTrack.id.isNotEmpty ? nextTrack.id : nextTrack.seokey,
          userId: userId,
          audioQuality: effectiveQuality,
          streamVersion: '1',
          byteStart: result.byteStart,
          byteEnd: result.byteEnd,
          totalContentLength: result.totalContentLength,
          bytes: result.bytes,
          etag: result.etag,
          mimeType: result.mimeType,
        );
      }
    } catch (e) {
      debugPrint('Queue prefetch failed gracefully: $e');
    } finally {
      if (_activePrefetchKey == key) {
        _activePrefetchKey = null;
        _cancelToken = null;
      }
    }
  }

  /// Immediately cancel any active prefetch transfer.
  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _activePrefetchKey = null;
  }
}
