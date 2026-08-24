import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/core/audio/playback_queue_policy.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

void main() {
  MusicItem song(String id) => MusicItem.fromJson({
    'track_id': id,
    'title': 'Song $id',
    'stream_urls': {
      'urls': {'high_quality': 'https://example.test/$id.mp3'},
    },
  });

  test('removes accidental consecutive duplicates from generated queues', () {
    final queue = PlaybackQueuePolicy.prepare([
      song('one'),
      song('one'),
      song('two'),
      song('one'),
    ]);

    expect(queue.map((item) => item.id), ['one', 'two', 'one']);
  });

  test('keeps user-intended duplicates when explicitly enabled', () {
    final queue = PlaybackQueuePolicy.prepare([
      song('one'),
      song('one'),
    ], allowConsecutiveDuplicates: true);

    expect(queue, hasLength(2));
  });
}
