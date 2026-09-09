import 'dart:async';
import 'package:flutter/foundation.dart';

/// Monitors playback continuity and detects genuine network/stream stalls.
///
/// If playback is active, network is connected, but position fails to advance
/// for > 8 seconds while buffering, triggers silent recovery at current position.
class PlaybackWatchdog {
  PlaybackWatchdog({
    required this.onStallDetected,
    this.checkInterval = const Duration(milliseconds: 2500),
    this.stallThreshold = const Duration(seconds: 8),
  });

  final Future<void> Function(Duration position) onStallDetected;
  final Duration checkInterval;
  final Duration stallThreshold;

  Timer? _timer;
  Duration _lastPosition = Duration.zero;
  DateTime _lastAdvanceTime = DateTime.now();
  bool _isRecovering = false;

  void start() {
    _timer?.cancel();
    _lastAdvanceTime = DateTime.now();
    _isRecovering = false;
    _timer = Timer.periodic(checkInterval, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRecovering = false;
  }

  void reset(Duration currentPosition) {
    _lastPosition = currentPosition;
    _lastAdvanceTime = DateTime.now();
    _isRecovering = false;
  }

  void updatePosition(Duration position) {
    if (position > _lastPosition) {
      _lastPosition = position;
      _lastAdvanceTime = DateTime.now();
      _isRecovering = false;
    }
  }

  /// Run watchdog check
  Future<void> _check() async {
    if (_isRecovering) return;
  }

  /// Explicit check called from player tick
  Future<void> evaluate({
    required bool isPlaying,
    dynamic processingState,
    bool? isBuffering,
    bool? isConnected,
    Duration? position,
    Duration? currentPosition,
    Duration? bufferedPosition,
  }) async {
    final effectiveConnected = isConnected ?? true;
    final pos = currentPosition ?? position ?? Duration.zero;
    final buffering = isBuffering ?? (processingState != null && '$processingState'.toLowerCase().contains('buffering'));

    if (!isPlaying || !effectiveConnected || _isRecovering) {
      _lastAdvanceTime = DateTime.now();
      _lastPosition = pos;
      return;
    }

    if (pos > _lastPosition) {
      _lastPosition = pos;
      _lastAdvanceTime = DateTime.now();
      return;
    }

    // If position has not advanced and player is stuck in buffering
    if (buffering) {
      final stalledDuration = DateTime.now().difference(_lastAdvanceTime);
      if (stalledDuration >= stallThreshold) {
        _isRecovering = true;
        debugPrint('[PlaybackWatchdog] Detected stream stall at ${pos.inSeconds}s (stalled for ${stalledDuration.inSeconds}s). Triggering silent recovery.');
        try {
          await onStallDetected(pos);
        } finally {
          _lastAdvanceTime = DateTime.now();
          _isRecovering = false;
        }
      }
    } else {
      // Normal playing state with position advancing
      _lastAdvanceTime = DateTime.now();
    }
  }

  void dispose() {
    stop();
  }
}
