// ignore_for_file: experimental_member_use, prefer_initializing_formals
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_cache.dart';
import 'segment_downloader.dart';

class CachedStreamAudioSource extends StreamAudioSource {
  CachedStreamAudioSource({
    required this.audioCache,
    required this.downloader,
    required Uri uri,
    required this.cacheKey,
    required this.songId,
    required this.userId,
    this.audioQuality = 'automatic',
    this.streamVersion = '1',
    this.extraHeaders,
    this.onNetworkDownloaded,
    this.onCacheRead,
    this.onDuplicatePrevented,
    super.tag,
  }) : _uri = uri;

  final AudioCache audioCache;
  final SegmentDownloader downloader;
  Uri _uri;
  Uri get uri => _uri;
  final String cacheKey;
  final String songId;
  final String userId;
  final String audioQuality;
  final String streamVersion;
  final Map<String, String>? extraHeaders;
  final void Function(int bytes)? onNetworkDownloaded;
  final void Function(int bytes)? onCacheRead;
  final VoidCallback? onDuplicatePrevented;

  final CancellationToken _cancelToken = CancellationToken();

  void updateUri(Uri newUri) {
    _uri = newUri;
  }

  void cancel() {
    _cancelToken.cancel();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (_cancelToken.isCancelled) {
      throw StateError('Audio source request cancelled');
    }
    final reqStart = start ?? 0;
    final cachedEntry = audioCache.getEntry(cacheKey);

    // 1. If entire song is already cached on disk, stream directly from disk file (0 network usage)
    final completeFile = audioCache.getCompleteFile(cacheKey);
    if (completeFile != null) {
      final total = cachedEntry?.totalBytes ?? completeFile.lengthSync();
      final reqEnd = (end != null && end < total) ? end : (total - 1);
      final len = reqEnd - reqStart + 1;
      if (len > 0) {
        onCacheRead?.call(len);
        return StreamAudioResponse(
          rangeRequestsSupported: true,
          sourceLength: total,
          contentLength: len,
          offset: reqStart,
          contentType: cachedEntry?.mimeType ?? 'audio/mp4',
          stream: completeFile.openRead(reqStart, reqEnd + 1),
        );
      }
    }

    // 2. Determine chunk boundary (chunk forward to 512KB so playback starts fast without huge buffers)
    final total = cachedEntry?.totalBytes ?? 0;
    final defaultEnd = reqStart + 512 * 1024 - 1;
    final reqEnd = (end != null)
        ? end
        : (total > 0 && defaultEnd >= total)
            ? (total - 1)
            : defaultEnd;

    // 3. Check if contiguous cached bytes are available for the requested start offset
    final availableRange = audioCache.getContiguousAvailableRange(cacheKey, reqStart);
    if (availableRange != null && availableRange.end >= reqStart) {
      final targetEnd = (reqEnd <= availableRange.end) ? reqEnd : availableRange.end;
      final cachedBytes = await audioCache.readRange(cacheKey, reqStart, targetEnd);
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        onCacheRead?.call(cachedBytes.length);
        return StreamAudioResponse(
          rangeRequestsSupported: true,
          sourceLength: cachedEntry?.totalBytes,
          contentLength: cachedBytes.length,
          offset: reqStart,
          contentType: cachedEntry?.mimeType ?? 'audio/mp4',
          stream: Stream.value(cachedBytes),
        );
      }
    }

    // 4. If uncached or missing range, download via SegmentDownloader with deduplication
    final downloadResult = await downloader.downloadRange(
      _uri,
      lockKey: '$cacheKey-$reqStart-$reqEnd',
      start: reqStart,
      end: reqEnd,
      extraHeaders: extraHeaders,
      cancelToken: _cancelToken,
      onDuplicatePrevented: onDuplicatePrevented,
    );

    if (downloadResult != null && downloadResult.bytes.isNotEmpty) {
      // Reuse final resolved URL if redirected (Point 11)
      if (downloadResult.resolvedUri != null && downloadResult.resolvedUri != _uri) {
        _uri = downloadResult.resolvedUri!;
      }

      onNetworkDownloaded?.call(downloadResult.bytes.length);

      // Asynchronously populate disk cache with received segment
      unawaited(
        audioCache.writeSegment(
          key: cacheKey,
          songId: songId,
          userId: userId,
          audioQuality: audioQuality,
          streamVersion: streamVersion,
          byteStart: downloadResult.byteStart,
          byteEnd: downloadResult.byteEnd,
          totalContentLength: downloadResult.totalContentLength,
          bytes: downloadResult.bytes,
          etag: downloadResult.etag,
          mimeType: downloadResult.mimeType,
        ),
      );

      final totalLen = downloadResult.totalContentLength > 0
          ? downloadResult.totalContentLength
          : (cachedEntry?.totalBytes);

      return StreamAudioResponse(
        rangeRequestsSupported: true,
        sourceLength: totalLen,
        contentLength: downloadResult.bytes.length,
        offset: downloadResult.byteStart,
        contentType: downloadResult.mimeType,
        stream: Stream.value(downloadResult.bytes),
      );
    }

    // Fallback: If network failed, check if any cached data is available for reqStart
    if (cachedEntry != null && cachedEntry.cachedBytes > reqStart) {
      final maxAvailable = cachedEntry.cachedBytes - 1;
      final targetEnd = reqEnd < maxAvailable ? reqEnd : maxAvailable;
      final bytes = await audioCache.readRange(cacheKey, reqStart, targetEnd);
      if (bytes != null && bytes.isNotEmpty) {
        onCacheRead?.call(bytes.length);
        return StreamAudioResponse(
          rangeRequestsSupported: true,
          sourceLength: cachedEntry.totalBytes,
          contentLength: bytes.length,
          offset: reqStart,
          contentType: cachedEntry.mimeType,
          stream: Stream.value(bytes),
        );
      }
    }

    throw StateError('Unable to stream audio segment for $cacheKey at $reqStart-$reqEnd');
  }
}
