import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:uuid/uuid.dart';

class DeviceRegistrar {
  DeviceRegistrar(this._api, this._store);

  final ApiClient _api;
  final LocalStore _store;

  Future<void> register() async {
    var deviceId = _store.readSetting('device_id', '');
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _store.saveSetting('device_id', deviceId);
    }
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      // Notification permission/configuration is optional during registration.
    }
    await _api.post(
      ApiEndpoints.devices,
      data: {
        'device_id': deviceId,
        'platform': _platform,
        'device_name': _deviceName,
        'fcm_token': token,
        'app_version': '1.0.0',
        'notifications_enabled': token != null,
      },
    );
  }

  Future<void> unregister() async {
    final deviceId = _store.readSetting('device_id', '');
    if (deviceId.isEmpty) return;
    await _api.delete(
      '${ApiEndpoints.devices}/${Uri.encodeComponent(deviceId)}',
    );
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux || TargetPlatform.fuchsia => 'linux',
    };
  }

  String get _deviceName =>
      kIsWeb ? 'Web browser' : '${defaultTargetPlatform.name} device';
}
