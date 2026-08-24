import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/audio/playback_source_resolver.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

void main() {
  final item = MusicItem.fromJson({
    'track_id': 'quality-test',
    'title': 'Quality Test',
    'stream_urls': {
      'urls': {
        'low_quality': 'https://example.test/low.mp3',
        'medium_quality': 'https://example.test/medium.mp3',
        'high_quality': 'https://example.test/high.mp3',
      },
    },
  });

  test('respects an explicit low streaming quality', () {
    expect(
      PlaybackSourceResolver.selectNetworkUri(item, 'low'),
      Uri.parse('https://example.test/low.mp3'),
    );
  });

  test('falls back safely when the preferred quality is missing', () {
    final mediumOnly = MusicItem.fromJson({
      'track_id': 'fallback-test',
      'title': 'Fallback Test',
      'stream_urls': {
        'urls': {'medium_quality': 'https://example.test/medium.mp3'},
      },
    });

    expect(
      PlaybackSourceResolver.selectNetworkUri(mediumOnly, 'high'),
      Uri.parse('https://example.test/medium.mp3'),
    );
  });
}
