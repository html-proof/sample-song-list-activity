import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/features/settings/data/app_settings.dart';

void main() {
  test('fills missing settings with safe defaults', () {
    final settings = AppSettings.fromJson({
      'playback': {'autoplay': false},
      'privacy': {'save_search_history': false},
    });

    expect(settings.playback['autoplay'], isFalse);
    expect(settings.playback['streaming_quality'], 'auto');
    expect(settings.privacy['save_search_history'], isFalse);
    expect(settings.downloads['wifi_only'], isTrue);
  });

  test('mergeGroup changes only the requested group', () {
    final original = AppSettings.defaults();
    final updated = original.mergeGroup('recommendations', {
      'exploration_level': 80,
    });

    expect(updated.recommendations['exploration_level'], 80);
    expect(updated.playback, original.playback);
    expect(updated.privacy, original.privacy);
  });
}
