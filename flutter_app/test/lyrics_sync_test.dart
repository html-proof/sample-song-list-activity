import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyric_line.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyrics.dart';
import 'package:music_hub_app/features/lyrics/presentation/controllers/lyrics_controller.dart';

void main() {
  const lines = [
    LyricLine(
      start: Duration(seconds: 10),
      end: Duration(seconds: 12),
      text: 'First',
    ),
    LyricLine(
      start: Duration(seconds: 15),
      end: Duration(seconds: 18),
      text: 'Second',
    ),
  ];

  test('binary lookup highlights only inside actual line timestamps', () {
    expect(findCurrentLyricLine(lines, const Duration(seconds: 10)), 0);
    expect(findCurrentLyricLine(lines, const Duration(seconds: 12)), -1);
    expect(findCurrentLyricLine(lines, const Duration(seconds: 14)), -1);
    expect(findCurrentLyricLine(lines, const Duration(seconds: 17)), 1);
  });

  test('global timing offset is applied without changing line data', () {
    expect(
      findCurrentLyricLine(
        lines,
        const Duration(milliseconds: 10_250),
        offset: const Duration(milliseconds: 250),
      ),
      0,
    );
  });

  test('lyrics model preserves Tamil Unicode and timestamps', () {
    final lyrics = Lyrics.fromJson({
      'song_id': 'simtaangaran',
      'status': 'available',
      'sync_type': 'line',
      'offset_ms': -200,
      'lines': [
        {'start_ms': 1200, 'end_ms': 3400, 'text': 'முதல் வரி'},
      ],
    });

    expect(lyrics.lines.single.text, 'முதல் வரி');
    expect(lyrics.offset, const Duration(milliseconds: -200));
    expect(lyrics.toJson()['lines'], isNotEmpty);
  });

  test('lyrics requests use stable seokey instead of tokenized media URL', () {
    final request = lyricsRequestForMedia(
      const MediaItem(
        id: '91821',
        title: 'Simtaangaran',
        artist: 'A.R. Rahman',
        extras: {
          'raw': {
            'seokey': 'simtaangaran',
            'provider_id': '91821',
            'stream_urls': {
              'urls': {'high_quality': 'https://signed.example/changes'},
            },
          },
        },
      ),
    );

    expect(request?.songId, 'simtaangaran');
    expect(request?.identityKey, hasLength(8));
  });
}
