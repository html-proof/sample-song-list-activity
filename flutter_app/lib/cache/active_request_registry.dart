import 'dart:async';
import 'package:flutter/foundation.dart';
import 'segment_downloader.dart';

/// Single-pipeline registry to prevent duplicate concurrent network transfers.
///
/// Ensures that player, preloader, cache manager, and download manager never
/// fetch the exact same byte range of the same track simultaneously.
class ActiveRequestRegistry {
  ActiveRequestRegistry._();
  static final ActiveRequestRegistry instance = ActiveRequestRegistry._();

  final Map<String, Future<SegmentDownloadResult?>> _inFlightRequests = {};
  int _duplicateCount = 0;

  int get duplicateCount => _duplicateCount;

  /// Generate a unique stable key for an audio request segment.
  static String generateKey({
    required String trackId,
    required String quality,
    required int start,
    int? end,
    String codec = 'aac',
  }) {
    final t = trackId.trim();
    final q = quality.trim().toLowerCase();
    final c = codec.trim().toLowerCase();
    final e = end ?? -1;
    return '${t}_${q}_${c}_${start}_$e';
  }

  /// Check if a request for this key is currently in flight.
  bool isInFlight(String key) => _inFlightRequests.containsKey(key);

  /// Run or attach to an existing in-flight download request.
  Future<SegmentDownloadResult?> runOrAttach(
    String key,
    Future<SegmentDownloadResult?> Function() requestFactory, {
    VoidCallback? onDuplicatePrevented,
  }) {
    if (_inFlightRequests.containsKey(key)) {
      _duplicateCount++;
      debugPrint('[ActiveRequestRegistry] Reusing in-flight network request for key: $key');
      onDuplicatePrevented?.call();
      return _inFlightRequests[key]!;
    }

    final future = requestFactory().whenComplete(() {
      _inFlightRequests.remove(key);
    });

    _inFlightRequests[key] = future;
    return future;
  }

  /// Cancel and remove all in-flight references (e.g. during test cleanup or full reset).
  void clear() {
    _inFlightRequests.clear();
    _duplicateCount = 0;
  }
}
