import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/shared/models/home_feed.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

Map<String, dynamic> song(
  String title, {
  String artist = 'Artist',
  String? id,
  int? duration,
}) => {
  'song_id': id ?? title,
  'seokey': (id ?? title).toLowerCase(),
  'title': title,
  'artists': artist,
  'duration': duration ?? 210,
  'stream_urls': {
    'urls': {'high_quality': 'https://audio.example/$title.mp3'},
  },
};

Map<String, dynamic> artistRow(String name, {String? id}) => {
  'artist_id': id ?? name,
  'seokey': (id ?? name).toLowerCase(),
  'name': name,
  'album': 'Some Album That Must Not Show',
};

Map<String, dynamic> albumRow(
  String name, {
  String artist = 'Artist',
  String? year,
}) => {
  'album_id': name,
  'seokey': name.toLowerCase(),
  'name': name,
  'artist_name': artist,
  'year': ?year,
};

Map<String, dynamic> playlistRow(String name, {int? songs}) => {
  'playlist_id': name,
  'seokey': name.toLowerCase(),
  'name': name,
  'song_count': ?songs,
};

void main() {
  group('content type', () {
    test('an explicit type always wins over key sniffing', () {
      final item = MusicItem.fromJson({
        'type': 'album',
        // An album payload that also carries a song-looking key must not be
        // mistaken for a song.
        'song_id': '12',
        'name': 'Greatest Hits',
        'artist_name': 'Someone',
      });
      expect(item.type, MusicItemType.album);
    });

    test('each declared type parses to its own model type', () {
      expect(
        MusicItem.fromJson({'type': 'song', 'title': 'A'}).type,
        MusicItemType.song,
      );
      expect(
        MusicItem.fromJson({'type': 'artist', 'name': 'A'}).type,
        MusicItemType.artist,
      );
      expect(
        MusicItem.fromJson({'type': 'playlist', 'name': 'A'}).type,
        MusicItemType.playlist,
      );
      expect(
        MusicItem.fromJson({'name': 'A'}).type,
        MusicItemType.unknown,
        reason: 'an untyped, unidentifiable row must not be guessed at',
      );
    });

    test('an artist never advertises an album or a song as its subtitle', () {
      final artist = MusicItem.fromJson(artistRow('Arijit Singh'));
      expect(artist.type, MusicItemType.artist);
      expect(artist.typedSubtitle, isNull);
      expect(artist.artistName, isNull);
    });

    test('a song shows its artist and an album shows its artist', () {
      expect(
        MusicItem.fromJson(song('Track', artist: 'Singer')).typedSubtitle,
        'Singer',
      );
      expect(
        MusicItem.fromJson(albumRow('Record', artist: 'Band')).typedSubtitle,
        'Band',
      );
    });

    test('a playlist reports its song count, never a borrowed artist', () {
      final playlist = MusicItem.fromJson(playlistRow('Chill', songs: 32));
      expect(playlist.typedSubtitle, '32 songs');
      expect(playlist.artistName, isNull);
    });
  });

  group('section isolation', () {
    test('a song row drops artists, albums and playlists mixed into it', () {
      final feed = HomeFeed.fromJson({
        'trending': [
          song('One'),
          artistRow('An Artist'),
          albumRow('An Album'),
          playlistRow('A Playlist'),
          song('Two'),
        ],
      });
      final trending = feed.sectionById('trending')!;
      expect(trending.contentType, MusicItemType.song);
      expect(trending.items.map((item) => item.title), ['One', 'Two']);
      expect(
        trending.items.every((item) => item.type == MusicItemType.song),
        isTrue,
      );
    });

    test('an artist row keeps only artists', () {
      final feed = HomeFeed.fromJson({
        'recommended_artists': [
          artistRow('First'),
          song('A Song'),
          artistRow('Second'),
        ],
      });
      final artists = feed.sectionById('recommended_artists')!;
      expect(artists.contentType, MusicItemType.artist);
      expect(artists.items.map((item) => item.title), ['First', 'Second']);
    });

    test('album and playlist rows stay separate', () {
      final feed = HomeFeed.fromJson({
        'recommended_albums': [albumRow('Album A'), playlistRow('Mix')],
        'recommended_playlists': [playlistRow('Mix'), albumRow('Album A')],
      });
      expect(
        feed.sectionById('recommended_albums')!.items.single.type,
        MusicItemType.album,
      );
      expect(
        feed.sectionById('recommended_playlists')!.items.single.type,
        MusicItemType.playlist,
      );
    });

    test('the sectioned response shape is parsed with its declared type', () {
      final feed = HomeFeed.fromJson({
        'sections': [
          {
            'id': 'recommended_playlists',
            'title': 'Recommended Playlists',
            'type': 'playlist',
            'items': [playlistRow('Malayalam Hits', songs: 50)],
          },
          {
            'id': 'trending_songs',
            'title': 'Trending Songs',
            'type': 'song',
            'items': [song('Hit')],
          },
        ],
      });
      expect(feed.sections.map((section) => section.title), [
        'Recommended Playlists',
        'Trending Songs',
      ]);
      expect(feed.sections.map((section) => section.contentType), [
        MusicItemType.playlist,
        MusicItemType.song,
      ]);
    });

    test('empty rows are dropped rather than shown as blank space', () {
      final feed = HomeFeed.fromJson({
        'trending': [song('One')],
        'recommended_albums': <dynamic>[],
      });
      expect(feed.sectionById('recommended_albums'), isNull);
      expect(feed.sections, hasLength(1));
    });
  });

  group('deduplication', () {
    test('songs collapse on normalized title, artist and duration', () {
      final items = dedupeItems([
        MusicItem.fromJson(song('Pattalam', artist: 'A. R. Rahman', id: '1')),
        MusicItem.fromJson(song('  pattalam ', artist: 'A R Rahman', id: '2')),
        MusicItem.fromJson(song('Pattalam', artist: 'Someone Else', id: '3')),
      ]);
      expect(items, hasLength(2));
    });

    test('artists collapse on normalized name regardless of casing', () {
      final items = dedupeItems([
        MusicItem.fromJson(artistRow('Arijit Singh', id: '1')),
        MusicItem.fromJson(artistRow('ARIJIT SINGH', id: '2')),
        MusicItem.fromJson(artistRow('arijit  singh', id: '3')),
      ]);
      expect(items, hasLength(1));
    });

    test('albums keep separate years apart', () {
      final items = dedupeItems([
        MusicItem.fromJson(albumRow('Live', year: '2011')),
        MusicItem.fromJson(albumRow('Live', year: '2019')),
        MusicItem.fromJson(albumRow('Live', year: '2011')),
      ]);
      expect(items, hasLength(2));
    });

    test('a song and an album sharing a name are never collapsed', () {
      final items = dedupeItems([
        MusicItem.fromJson(song('Rockstar')),
        MusicItem.fromJson(albumRow('Rockstar')),
      ]);
      expect(items, hasLength(2));
    });
  });

  group('cross-section diversity', () {
    test('one song may repeat across rows but not fill the screen', () {
      final repeated = song('Everywhere');
      final feed = HomeFeed.fromJson({
        'continue_listening': [
          repeated,
          song('B'),
          song('C'),
          song('D'),
          song('E'),
        ],
        'recommended_for_you': [
          repeated,
          song('F'),
          song('G'),
          song('H'),
          song('I'),
        ],
        'trending': [repeated, song('J'), song('K'), song('L'), song('M')],
        'language_mix': [repeated, song('N'), song('O'), song('P'), song('Q')],
      });
      int appearances(String title) => feed.sections
          .where((section) => section.items.any((i) => i.title == title))
          .length;
      expect(appearances('Everywhere'), 2);
      // The rows themselves stay full.
      for (final section in feed.sections) {
        expect(section.items, hasLength(greaterThanOrEqualTo(4)));
      }
    });

    test('a short row keeps its items rather than being emptied', () {
      final repeated = song('Only');
      final feed = HomeFeed.fromJson({
        'continue_listening': [repeated],
        'recommended_for_you': [repeated],
        'trending': [repeated],
        'language_mix': [repeated],
      });
      for (final section in feed.sections) {
        expect(section.items, isNotEmpty);
      }
    });
  });
}
