import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models.dart';
import '../network_policy.dart';
import 'throughput_estimator.dart';

/// Manages Spotify-style dynamic adaptive stream quality with hysteresis.
///
/// Ensures uninterrupted playback:
/// - Downgrades quickly when buffer health drops or stalls occur.
/// - Upgrades gradually only after sustained network stability (>= 15s).
/// - Respects user preferences, Data Saver, and available qualities.
class AdaptiveQualityManager extends ChangeNotifier {
  AdaptiveQualityManager({
    ThroughputEstimator? estimator,
    this.connection,
    this.policy,
  }) : _estimator = estimator ?? ThroughputEstimator.instance;

  final ThroughputEstimator _estimator;
  final ConnectionMonitor? connection;
  final DataUsagePolicy? policy;

  final StreamController<String> _qualityController =
      StreamController<String>.broadcast();
  Stream<String> get onQualityChanged => _qualityController.stream;

  String _currentQuality = 'normal';
  double _bufferHealthSeconds = 10.0;
  int _consecutiveStableUpSeconds = 0;
  Timer? _stabilityTicker;
  int _stallsInWindow = 0;
  DateTime _lastStallTime = DateTime.fromMillisecondsSinceEpoch(0);

  String get currentQuality => _currentQuality;
  double get bufferHealthSeconds => _bufferHealthSeconds;

  static const Map<String, int> qualityBitratesBps = {
    'low': 64000, // 64 kbps
    'normal': 128000, // 128 kbps
    'high': 192000, // 192 kbps
    'very_high': 320000, // 320 kbps
  };

  void start() {
    _stabilityTicker?.cancel();
    _stabilityTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickStability();
    });
  }

  void stop() {
    _stabilityTicker?.cancel();
    _stabilityTicker = null;
  }

  void recordPlaybackProgress() {
    // Active playback progress confirmed
  }

  void recordStall() {
    _stallsInWindow++;
    _lastStallTime = DateTime.now();
    _consecutiveStableUpSeconds = 0;
    final prev = _currentQuality;
    // Fast downgrade on playback stall
    if (_currentQuality == 'very_high') {
      _currentQuality = 'high';
    } else if (_currentQuality == 'high') {
      _currentQuality = 'normal';
    } else if (_currentQuality == 'normal') {
      _currentQuality = 'low';
    }
    if (prev != _currentQuality) {
      notifyListeners();
      _qualityController.add(_currentQuality);
    }
  }

  /// Update current buffer health metric (buffered position - playback position).
  void updateBufferHealth(Duration position, Duration buffered) {
    final diffMs = buffered.inMilliseconds - position.inMilliseconds;
    _bufferHealthSeconds = diffMs > 0 ? diffMs / 1000.0 : 0.0;

    // Urgent buffer risk (buffer health < 3.5s)
    if (_bufferHealthSeconds < 3.5 && _currentQuality != 'low') {
      final prev = _currentQuality;
      _consecutiveStableUpSeconds = 0;
      if (_bufferHealthSeconds < 2.0) {
        _currentQuality = 'low';
      } else if (_currentQuality == 'very_high') {
        _currentQuality = 'normal';
      } else if (_currentQuality == 'high') {
        _currentQuality = 'normal';
      }
      if (prev != _currentQuality) {
        notifyListeners();
        _qualityController.add(_currentQuality);
      }
    }
  }

  void _tickStability() {
    // Clear old stalls after 45 seconds
    if (_stallsInWindow > 0 &&
        DateTime.now().difference(_lastStallTime).inSeconds > 45) {
      _stallsInWindow = 0;
    }

    final throughput = _estimator.estimatedBps;
    final nextHigher = _getNextHigherTier(_currentQuality);

    if (nextHigher != null) {
      final requiredBps = (qualityBitratesBps[nextHigher] ?? 128000) * 1.6; // 60% headroom
      if (throughput >= requiredBps && _bufferHealthSeconds >= 14.0 && _stallsInWindow == 0) {
        _consecutiveStableUpSeconds++;
        // Upgrade only after 15 seconds of sustained stability
        if (_consecutiveStableUpSeconds >= 15) {
          _currentQuality = nextHigher;
          _consecutiveStableUpSeconds = 0;
          notifyListeners();
          _qualityController.add(_currentQuality);
        }
      } else {
        _consecutiveStableUpSeconds = 0;
      }
    } else {
      _consecutiveStableUpSeconds = 0;
    }
  }

  String? _getNextHigherTier(String tier) => switch (tier) {
    'low' => 'normal',
    'normal' => 'high',
    _ => null,
  };

  /// Compute optimal stream quality for a given track, factoring in user settings.
  String resolveQualityForTrack(
    Track track, {
    String? configuredPreference,
    bool? isWifi,
    bool? isCellular,
    bool? isDataSaver,
  }) {
    final netState = connection?.state ?? const NetworkState();
    final wifi = isWifi ?? (netState.connected && netState.connectionType == ConnectionType.wifi);
    final cellular = isCellular ?? (netState.connected && netState.connectionType == ConnectionType.cellular);
    final dataSaver = isDataSaver ?? (policy?.dataSaverEnabled == true);
    final pref = configuredPreference ??
        (wifi
            ? (policy?.wifiAudioQuality ?? 'automatic')
            : (cellular
                ? (policy?.cellularAudioQuality ?? 'automatic')
                : (policy?.qualityFor(netState) ?? 'automatic')));

    // If user explicitly set a fixed non-automatic quality, honor it
    if (pref != 'automatic') {
      // If data saver is active on cellular, cap at normal
      if (dataSaver && cellular && pref == 'very_high') {
        return 'normal';
      }
      return pref;
    }

    // Automatic mode:
    if (dataSaver && cellular) {
      return 'low';
    }

    // Smart initial quality: estimate available bandwidth
    final bwClass = _estimator.bandwidthClass;
    if (_bufferHealthSeconds <= 3.0) {
      return 'low';
    }

    switch (bwClass) {
      case NetworkBandwidthClass.poor:
        return 'low';
      case NetworkBandwidthClass.moderate:
        return 'normal';
      case NetworkBandwidthClass.good:
        return cellular ? 'normal' : 'high';
      case NetworkBandwidthClass.excellent:
        return 'high';
    }
  }

  @override
  void dispose() {
    stop();
    _qualityController.close();
    super.dispose();
  }
}
