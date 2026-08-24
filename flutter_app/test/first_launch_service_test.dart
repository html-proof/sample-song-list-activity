import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/startup/first_launch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shows the custom splash once and persists completion', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final service = FirstLaunchService(preferences);

    expect(await service.isFirstLaunch(), isTrue);

    await service.markSplashSeen();

    expect(await service.isFirstLaunch(), isFalse);
    expect(preferences.getBool(FirstLaunchService.splashSeenKey), isTrue);
  });

  test('keeps the splash hidden when the stored flag already exists', () async {
    SharedPreferences.setMockInitialValues({
      FirstLaunchService.splashSeenKey: true,
    });
    final preferences = await SharedPreferences.getInstance();

    expect(await FirstLaunchService(preferences).isFirstLaunch(), isFalse);
  });
}
