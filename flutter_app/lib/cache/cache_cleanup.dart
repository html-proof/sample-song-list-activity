import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_cache.dart';

class CacheCleanupWorker {
  CacheCleanupWorker(this.audioCache);

  final AudioCache audioCache;
  Timer? _periodicTimer;

  void startPeriodicCleanup({Duration interval = const Duration(hours: 6)}) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      unawaited(runCleanup());
    });
  }

  Future<void> runCleanup() async {
    try {
      await audioCache.cleanupExpired();
      await audioCache.enforceCacheLimit();
    } catch (e) {
      debugPrint('CacheCleanupWorker error: $e');
    }
  }

  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
