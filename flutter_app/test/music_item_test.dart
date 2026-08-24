import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

void main() {
  test('parses a playable Gaana track', () {
    final item = MusicItem.fromJson({
      'track_id': '42',
      'title': 'Night Drive',
      'artists': 'Example Artist',
      'duration': '180',
      'stream_urls': {
        'urls': {'high_quality': 'https://example.test/song.mp3'},
      },
      'images': {
        'urls': {'large_artwork': 'https://example.test/cover.jpg'},
      },
    });

    expect(item.id, '42');
    expect(item.type, MusicItemType.song);
    expect(item.playable, isTrue);
    expect(item.duration, const Duration(minutes: 3));
  });

  test('parses downloaded metadata as a local song', () {
    final item = MusicItem.fromJson({
      'id': 'download-1',
      'song_name': 'Offline Track',
      'local_uri': 'file:///music/download-1.audio',
    });

    expect(item.id, 'download-1');
    expect(item.type, MusicItemType.song);
    expect(item.playable, isTrue);
  });
}
