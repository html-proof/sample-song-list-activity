import 'package:flutter/foundation.dart';

enum NetworkBandwidthClass {
  poor, // < 150 kbps (e.g. 2G / weak mobile)
  moderate, // 150 - 450 kbps (e.g. 3G / slow mobile data)
  good, // 450 - 1800 kbps (e.g. 4G / stable cellular)
  excellent, // > 1800 kbps (e.g. 5G / High-speed Wi-Fi)
}

/// Real-time Exponentially Weighted Moving Average (EWMA) Network Throughput Estimator.
///
/// Measures real download throughput from media chunk transfers and calculates
/// smoothed bandwidth (bps) and round-trip latency (ms) without artificial polling.
class ThroughputEstimator extends ChangeNotifier {
  ThroughputEstimator({
    double initialBps = 1000000.0, // 1 Mbps default safe baseline
    this.alpha = 0.25, // Smoothing factor (higher = more reactive, lower = smoother)
  })  : _estimatedBps = initialBps;

  static final ThroughputEstimator instance = ThroughputEstimator();

  final double alpha;
  double _estimatedBps;
  double _latencyMs = 80.0;
  int _samplesCount = 0;
  int _lastSampleTimeMs = 0;

  double get estimatedBps => _estimatedBps;
  double get estimatedKbps => _estimatedBps / 1000.0;
  double get latencyMs => _latencyMs;
  int get samplesCount => _samplesCount;
  int get lastSampleTimeMs => _lastSampleTimeMs;

  NetworkBandwidthClass get bandwidthClass {
    if (_estimatedBps < 150000) {
      return NetworkBandwidthClass.poor;
    } else if (_estimatedBps < 450000) {
      return NetworkBandwidthClass.moderate;
    } else if (_estimatedBps < 1800000) {
      return NetworkBandwidthClass.good;
    } else {
      return NetworkBandwidthClass.excellent;
    }
  }

  /// Record a completed chunk transfer and update EWMA throughput.
  void recordTransfer(int bytes, int durationMs, {int? latencyMs}) {
    if (bytes <= 0 || durationMs <= 0) return;

    // Filter out unrealistically tiny transfers that distort calculations (< 4KB in 1ms)
    final clampedDuration = durationMs < 5 ? 5 : durationMs;
    final sampleBps = (bytes * 8.0 * 1000.0) / clampedDuration;

    // Prevent extreme outlier spikes (> 500 Mbps or < 1 kbps)
    if (sampleBps < 1000.0 || sampleBps > 500000000.0) return;

    if (_samplesCount == 0) {
      _estimatedBps = sampleBps;
    } else {
      _estimatedBps = (alpha * sampleBps) + ((1.0 - alpha) * _estimatedBps);
    }

    if (latencyMs != null && latencyMs > 0) {
      _latencyMs = (alpha * latencyMs.toDouble()) + ((1.0 - alpha) * _latencyMs);
    }

    _samplesCount++;
    _lastSampleTimeMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Reset estimator metrics, e.g. after complete connection handover.
  void reset({double initialBps = 1000000.0}) {
    _estimatedBps = initialBps;
    _samplesCount = 0;
    _latencyMs = 80.0;
    notifyListeners();
  }
}
