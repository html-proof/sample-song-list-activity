import 'package:shared_preferences/shared_preferences.dart';

class FirstLaunchService {
  FirstLaunchService(this._preferences);

  static const splashSeenKey = 'has_seen_intro_splash';

  final SharedPreferences _preferences;

  bool get shouldShowSplash => !(_preferences.getBool(splashSeenKey) ?? false);

  Future<bool> isFirstLaunch() async => shouldShowSplash;

  Future<void> markSplashSeen() async {
    await _preferences.setBool(splashSeenKey, true);
  }
}
