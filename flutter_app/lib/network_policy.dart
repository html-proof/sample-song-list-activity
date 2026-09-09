import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ConnectionType { wifi, cellular, offline, unknown }

class NetworkState {
  const NetworkState({
    this.connected = true,
    this.connectionType = ConnectionType.unknown,
    this.isMetered = false,
    this.effectiveBandwidth = 0,
    this.connectionQuality = 'unknown',
  });

  final bool connected;
  final ConnectionType connectionType;
  final bool isMetered;
  final double effectiveBandwidth;
  final String connectionQuality;
}

class DataUsagePolicy extends ChangeNotifier {
  DataUsagePolicy({this._local});
  SharedPreferences? _local;
  bool dataSaverEnabled = false;
  bool allowMobileStreaming = true;
  bool allowMobileDownloads = false;
  bool offlineMode = false;
  String wifiAudioQuality = 'automatic';
  String cellularAudioQuality = 'automatic';
  String downloadQuality = 'high';
  bool preloadNextTrack = true;
  bool backgroundDataAllowed = true;
  String imageQuality = 'automatic';

  Future<void> load() async {
    _local ??= await SharedPreferences.getInstance();
    final p = _local!;
    dataSaverEnabled = p.getBool('data_saver_enabled') ?? false;
    allowMobileStreaming = p.getBool('stream_mobile_data') ?? true;
    allowMobileDownloads = p.getBool('download_mobile_data') ?? false;
    offlineMode = p.getBool('offline_mode') ?? false;
    wifiAudioQuality = p.getString('streaming_quality_wifi') ?? 'automatic';
    cellularAudioQuality = p.getString('streaming_quality_mobile') ?? 'automatic';
    downloadQuality = p.getString('download_quality') ?? 'high';
    preloadNextTrack = p.getBool('preload_next_song') ?? true;
    backgroundDataAllowed = p.getBool('background_data_allowed') ?? true;
    imageQuality = p.getString('image_quality') ?? 'automatic';
    notifyListeners();
  }

  Future<void> setValue(String key, Object value) async {
    _local ??= await SharedPreferences.getInstance();
    if (value is bool) await _local!.setBool(key, value);
    if (value is String) await _local!.setString(key, value);
    switch (key) {
      case 'data_saver_enabled': dataSaverEnabled = value as bool;
      case 'stream_mobile_data': allowMobileStreaming = value as bool;
      case 'download_mobile_data': allowMobileDownloads = value as bool;
      case 'offline_mode': offlineMode = value as bool;
      case 'streaming_quality_wifi': wifiAudioQuality = value as String;
      case 'streaming_quality_mobile': cellularAudioQuality = value as String;
      case 'download_quality': downloadQuality = value as String;
      case 'preload_next_song': preloadNextTrack = value as bool;
      case 'background_data_allowed': backgroundDataAllowed = value as bool;
      case 'image_quality': imageQuality = value as String;
    }
    notifyListeners();
  }

  bool canUseNetwork(NetworkState state, {required bool forDownload}) {
    if (!state.connected) return false;
    if (state.connectionType == ConnectionType.cellular) {
      return forDownload ? allowMobileDownloads : allowMobileStreaming;
    }
    return true;
  }

  String qualityFor(NetworkState state) {
    if (dataSaverEnabled && (state.connectionType == ConnectionType.cellular || state.isMetered)) {
      return 'low';
    }
    final isWifi = state.connectionType == ConnectionType.wifi;
    final isCellular = state.connectionType == ConnectionType.cellular || state.isMetered;

    final requested = isWifi
        ? wifiAudioQuality
        : isCellular
            ? cellularAudioQuality
            : (wifiAudioQuality != 'automatic' ? wifiAudioQuality : cellularAudioQuality);

    if (requested != 'automatic') return requested;

    if (isWifi) {
      return 'high';
    }
    if (isCellular) {
      if (state.connectionQuality == 'poor') return 'low';
      if (state.connectionQuality == 'excellent') return 'high';
      return 'normal';
    }
    return 'high';
  }

  bool canPreloadNextSong(NetworkState state) {
    if (!state.connected) return false;
    if (!preloadNextTrack) return false;
    if (dataSaverEnabled && state.connectionType == ConnectionType.cellular) return false;
    return true;
  }

  int imageSize(NetworkState state, {bool detail = false}) {
    if (dataSaverEnabled || state.connectionType == ConnectionType.cellular) return detail ? 320 : 160;
    return detail ? 640 : 320;
  }
}

class ConnectionMonitor extends ChangeNotifier {
  ConnectionMonitor() : _state = const NetworkState();
  NetworkState _state;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  NetworkState get state => _state;

  Future<void> start() async {
    if (kIsWeb) {
      _state = const NetworkState(
        connected: true,
        connectionType: ConnectionType.wifi,
        isMetered: false,
        connectionQuality: 'good',
      );
      notifyListeners();
      return;
    }
    final connectivity = Connectivity();
    await _update(await connectivity.checkConnectivity());
    _subscription = connectivity.onConnectivityChanged.listen(_update);
  }

  Future<void> checkNow() async {
    if (kIsWeb) return;
    try {
      final results = await Connectivity().checkConnectivity();
      await _update(results);
    } catch (_) {}
  }

  /// Wait for network connectivity to become active if it's currently disconnected.
  /// Returns true if connected within the timeout period, false otherwise.
  Future<bool> waitForConnection({Duration timeout = const Duration(seconds: 3)}) async {
    if (_state.connected) return true;
    await checkNow();
    if (_state.connected) return true;

    final completer = Completer<bool>();
    void listener() {
      if (_state.connected && !completer.isCompleted) {
        completer.complete(true);
      }
    }

    addListener(listener);
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(_state.connected);
      }
    });

    try {
      final result = await completer.future;
      timer.cancel();
      return result;
    } finally {
      removeListener(listener);
    }
  }

  Future<void> _update(List<ConnectivityResult> results) async {
    final bool hasWifi = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    final bool hasCellular = results.contains(ConnectivityResult.mobile);
    final bool hasOther = results.contains(ConnectivityResult.vpn) ||
        results.contains(ConnectivityResult.bluetooth) ||
        results.contains(ConnectivityResult.other);
    final bool isOffline = results.isEmpty ||
        (results.length == 1 && results.first == ConnectivityResult.none);

    final ConnectionType type = hasWifi
        ? ConnectionType.wifi
        : hasCellular
            ? ConnectionType.cellular
            : (hasOther || !isOffline)
                ? ConnectionType.unknown
                : ConnectionType.offline;

    _state = NetworkState(
      connected: type != ConnectionType.offline,
      connectionType: type,
      isMetered: type == ConnectionType.cellular,
      connectionQuality: type == ConnectionType.wifi
          ? 'good'
          : type == ConnectionType.cellular
              ? 'medium'
              : 'unknown',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

