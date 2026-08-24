import 'package:music_hub_app/shared/models/music_item.dart';

abstract interface class PlaybackAnalytics {
  void track(
    String event,
    MusicItem item, {
    required String source,
    int? positionMs,
    Map<String, dynamic>? metadata,
  });

  void recordListen(
    MusicItem item, {
    required String source,
    int playedMs,
    bool completed,
  });
}
