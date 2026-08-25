import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/notifications/notification_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.musichub.app/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reports the granted result from the platform', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ensureNotificationPermission');
      return true;
    });

    expect(await const NotificationPermission(channel).ensure(), isTrue);
  });

  test('reports a denied permission', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);

    expect(await const NotificationPermission(channel).ensure(), isFalse);
  });

  test('a platform failure never throws', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });

    expect(await const NotificationPermission(channel).ensure(), isFalse);
  });

  test('a missing implementation never throws', () async {
    expect(await const NotificationPermission(channel).ensure(), isFalse);
  });
}
