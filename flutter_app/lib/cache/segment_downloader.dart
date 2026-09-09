import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../streaming/throughput_estimator.dart';
import 'active_request_registry.dart';

class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class SegmentDownloadResult {
  final int statusCode;
  final int byteStart;
  final int byteEnd;
  final int totalContentLength;
  final String? etag;
  final String mimeType;
  final List<int> bytes;
  final Uri? resolvedUri;

  const SegmentDownloadResult({
    required this.statusCode,
    required this.byteStart,
    required this.byteEnd,
    required this.totalContentLength,
    this.etag,
    this.mimeType = 'audio/mp4',
    required this.bytes,
    this.resolvedUri,
  });
}

class SegmentDownloader {
  SegmentDownloader({
    http.Client? client,
    ThroughputEstimator? estimator,
    ActiveRequestRegistry? registry,
  })  : _client = client ?? http.Client(),
        _estimator = estimator ?? ThroughputEstimator.instance,
        _registry = registry ?? ActiveRequestRegistry.instance;

  final http.Client _client;
  final ThroughputEstimator _estimator;
  final ActiveRequestRegistry _registry;
  final Map<String, Completer<void>> _activeLocks = {};
  final Random _random = Random();

  static const Map<String, String> defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
    'Accept-Encoding': 'identity',
  };

  Future<void> _acquireLock(String key) async {
    while (_activeLocks.containsKey(key)) {
      await _activeLocks[key]!.future;
    }
    _activeLocks[key] = Completer<void>();
  }

  void _releaseLock(String key) {
    final completer = _activeLocks.remove(key);
    completer?.complete();
  }

  /// Download a specific byte range with request deduplication and exponential backoff.
  Future<SegmentDownloadResult?> downloadRange(
    Uri uri, {
    required String lockKey,
    int start = 0,
    int? end,
    Map<String, String>? extraHeaders,
    int maxRetries = 3,
    CancellationToken? cancelToken,
    VoidCallback? onDuplicatePrevented,
  }) {
    if (cancelToken?.isCancelled == true) return Future.value(null);

    // Reuse in-flight request for identical key if already running
    return _registry.runOrAttach(
      lockKey,
      () => _executeDownloadRange(
        uri,
        lockKey: lockKey,
        start: start,
        end: end,
        extraHeaders: extraHeaders,
        maxRetries: maxRetries,
        cancelToken: cancelToken,
      ),
      onDuplicatePrevented: onDuplicatePrevented,
    );
  }

  Future<SegmentDownloadResult?> _executeDownloadRange(
    Uri uri, {
    required String lockKey,
    int start = 0,
    int? end,
    Map<String, String>? extraHeaders,
    int maxRetries = 3,
    CancellationToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) return null;
    await _acquireLock(lockKey);
    try {
      var attempt = 0;
      // Controlled backoff: Retry 1: ~500ms, Retry 2: ~1000ms, Retry 3: ~2000ms
      final backoffDelaysMs = [500, 1000, 2000];

      while (attempt <= maxRetries) {
        if (cancelToken?.isCancelled == true) return null;
        try {
          final headers = <String, String>{
            ...defaultHeaders,
            ...?extraHeaders,
          };
          if (end != null && end >= start) {
            headers['Range'] = 'bytes=$start-$end';
          } else if (start > 0) {
            headers['Range'] = 'bytes=$start-';
          }

          final request = http.Request('GET', uri);
          request.headers.addAll(headers);

          final stopwatch = Stopwatch()..start();
          final streamedResponse = await _client.send(request).timeout(
                const Duration(seconds: 15),
              );

          if (cancelToken?.isCancelled == true) return null;

          final statusCode = streamedResponse.statusCode;
          final contentType =
              streamedResponse.headers['content-type']?.toLowerCase() ?? '';
          final etag = streamedResponse.headers['etag'];
          final contentRange = streamedResponse.headers['content-range'];
          final contentLength = streamedResponse.contentLength ?? 0;
          final resolvedUri = streamedResponse.request?.url;

          // Reject error pages or non-audio responses if HTML is returned
          if (statusCode != 200 && statusCode != 206) {
            if (statusCode == 403 || statusCode == 401 || statusCode == 404) {
              // Non-retryable HTTP auth or not-found errors
              return null;
            }
            throw HttpException('HTTP $statusCode: ${streamedResponse.reasonPhrase}');
          }

          if (contentType.contains('text/html') ||
              contentType.contains('application/json')) {
            throw const HttpException('Invalid content-type: received text instead of audio');
          }

          final bytes = await streamedResponse.stream.toBytes().timeout(
                const Duration(seconds: 30),
              );

          stopwatch.stop();
          if (cancelToken?.isCancelled == true) return null;

          if (bytes.isNotEmpty) {
            _estimator.recordTransfer(bytes.length, stopwatch.elapsedMilliseconds);
          }

          if (bytes.isEmpty && (end == null || end >= start)) {
            throw const HttpException('Zero-byte response received');
          }

          var totalBytes = contentLength;
          var effectiveStart = start;
          var effectiveEnd = start + bytes.length - 1;

          if (contentRange != null) {
            // Format: bytes 0-1023/2048 or bytes 0-1023/*
            final match = RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(contentRange);
            if (match != null) {
              effectiveStart = int.tryParse(match.group(1) ?? '') ?? effectiveStart;
              effectiveEnd = int.tryParse(match.group(2) ?? '') ?? effectiveEnd;
              final totalMatch = match.group(3);
              if (totalMatch != null && totalMatch != '*') {
                totalBytes = int.tryParse(totalMatch) ?? totalBytes;
              }
            }
          } else if (statusCode == 200 && contentLength > 0) {
            totalBytes = contentLength;
          }

          return SegmentDownloadResult(
            statusCode: statusCode,
            byteStart: effectiveStart,
            byteEnd: effectiveEnd,
            totalContentLength: totalBytes,
            etag: etag,
            mimeType: contentType.isNotEmpty ? contentType : 'audio/mp4',
            bytes: bytes,
            resolvedUri: resolvedUri,
          );
        } catch (e) {
          attempt++;
          if (attempt > maxRetries) {
            debugPrint('Segment download failed after $maxRetries attempts: $e');
            return null;
          }
          final baseDelay = (attempt - 1 < backoffDelaysMs.length)
              ? backoffDelaysMs[attempt - 1]
              : 2000;
          final jitter = _random.nextInt(150);
          await Future.delayed(Duration(milliseconds: baseDelay + jitter));
        }
      }
      return null;
    } finally {
      _releaseLock(lockKey);
    }
  }
}
