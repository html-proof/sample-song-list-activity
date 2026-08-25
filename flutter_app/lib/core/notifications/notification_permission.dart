import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks Android 13+ for the notification permission the media notification
/// needs.
///
/// `audio_service` posts the playback notification but never requests the
/// permission, so on API 33+ a fresh install silently has no notification and
/// no lock-screen controls until the user is asked.
class NotificationPermission {
  const NotificationPermission([
    this._channel = const MethodChannel('com.musichub.app/notifications'),
  ]);

  final MethodChannel _channel;

  /// Returns whether notifications may be posted. Never throws: a failure here
  /// must not stop the app or interrupt playback.
  Future<bool> ensure() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'ensureNotificationPermission',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }
}
