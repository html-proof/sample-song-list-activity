import 'package:music_hub_app/shared/models/music_item.dart';

class PlaybackQueuePolicy {
  const PlaybackQueuePolicy._();

  static List<MusicItem> prepare(
    Iterable<MusicItem> items, {
    bool allowConsecutiveDuplicates = false,
  }) {
    final result = <MusicItem>[];
    String? previousIdentity;
    for (final item in items) {
      if (item.type != MusicItemType.song) continue;
      final identity = _identity(item);
      if (!allowConsecutiveDuplicates && identity == previousIdentity) {
        continue;
      }
      result.add(item);
      previousIdentity = identity;
    }
    return result;
  }

  static String _identity(MusicItem item) {
    if (item.id.isNotEmpty) return 'id:${item.id}';
    final title = item.title.trim().toLowerCase();
    final artist = item.subtitle?.trim().toLowerCase() ?? '';
    return 'metadata:$title|$artist';
  }
}
