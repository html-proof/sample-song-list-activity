import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/search/search_engine.dart';

void main() {
  setUp(() {
    LocalSearchEngine.instance.clear();
  });

  group('Spotify-Style Relevance Scoring & Normalization', () {
    test('normalizeSearchText cleans punctuation, brackets, and extra spaces', () {
      expect(normalizeSearchText('Ghilli (Original Soundtrack)'), 'ghilli original soundtrack');
      expect(normalizeSearchText('Porkanda Singam [From "Vikram"]'), 'porkanda singam from vikram');
      expect(normalizeSearchText('  A.R.   Rahman  ! '), 'a r rahman');
    });

    test('Score hierarchy prioritizes exact > prefix > word prefix > contains > typo', () {
      const exactTrack = Track(
        trackId: '1',
        seokey: 'ghilli',
        title: 'Ghilli',
        artist: 'Vidyasagar',
      );
      const prefixTrack = Track(
        trackId: '2',
        seokey: 'ghilli-theme',
        title: 'Ghilli Theme',
        artist: 'Vidyasagar',
      );
      const wordPrefixTrack = Track(
        trackId: '3',
        seokey: 'best-of-ghilli',
        title: 'The Best of Ghilli',
        artist: 'Vidyasagar',
      );
      const containsTrack = Track(
        trackId: '4',
        seokey: 'megaghilli',
        title: 'Megaghilli Nonstop',
        artist: 'Vidyasagar',
      );
      const typoTrack = Track(
        trackId: '5',
        seokey: 'ghil',
        title: 'Ghil',
        artist: 'Unknown',
      );

      final exactScore = scoreTrack(exactTrack, 'ghilli');
      final prefixScore = scoreTrack(prefixTrack, 'ghilli');
      final wordPrefixScore = scoreTrack(wordPrefixTrack, 'ghilli');
      final containsScore = scoreTrack(containsTrack, 'ghilli');
      final typoScore = scoreTrack(typoTrack, 'ghilli');

      expect(exactScore, equals(1000));
      expect(prefixScore, equals(850));
      expect(wordPrefixScore, equals(750));
      expect(containsScore, equals(600));
      expect(typoScore, equals(150));

      expect(exactScore, greaterThan(prefixScore));
      expect(prefixScore, greaterThan(wordPrefixScore));
      expect(wordPrefixScore, greaterThan(containsScore));
      expect(containsScore, greaterThan(typoScore));
    });

    test('Noise penalty deprioritizes unofficial covers, 8D audio, and ringtones', () {
      const officialTrack = Track(
        trackId: '1',
        seokey: 'aradhya',
        title: 'Aradhya',
        artist: 'Sid Sriram',
      );
      const ringtoneTrack = Track(
        trackId: '2',
        seokey: 'aradhya-ringtone',
        title: 'Aradhya Ringtone (8D Audio)',
        artist: 'Sid Sriram',
      );

      final officialScore = scoreTrack(officialTrack, 'aradhya');
      final ringtoneScore = scoreTrack(ringtoneTrack, 'aradhya');

      expect(officialScore, greaterThan(ringtoneScore));
      expect(officialScore - ringtoneScore, greaterThanOrEqualTo(400));
    });

    test('rankTracksForQuery orders tracks strictly by Spotify-style relevance', () {
      final tracks = [
        const Track(trackId: '1', seokey: 't1', title: 'Aaradhya (Slowed + Reverb)', artist: 'Artist'),
        const Track(trackId: '2', seokey: 't2', title: 'Aradhya', artist: 'Sid Sriram'),
        const Track(trackId: '3', seokey: 't3', title: 'Aradhya Promo', artist: 'Sid Sriram'),
      ];

      final ranked = rankTracksForQuery(tracks, 'aradhya');
      expect(ranked.first.id, 't2'); // Exact match
      expect(ranked[1].id, 't3'); // Prefix match
      expect(ranked.last.id, 't1'); // Penalty match
    });
  });

  group('LocalSearchEngine Progressive Keystroke Matching', () {
    setUp(() {
      final engine = LocalSearchEngine.instance;
      engine.clear();
      engine.indexTracks([
        const Track(trackId: '1', seokey: 'ghilli-kabaddi', title: 'Ghilli Kabaddi', artist: 'Vidyasagar', album: 'Ghilli'),
        const Track(trackId: '2', seokey: 'ghilli', title: 'Ghilli', artist: 'Vidyasagar', album: 'Ghilli'),
        const Track(trackId: '3', seokey: 'ghost', title: 'Ghost Title Track', artist: 'Anirudh', album: 'Ghost'),
        const Track(trackId: '4', seokey: 'ghazal', title: 'Ghazal Night', artist: 'Pankaj Udhas', album: 'Ghazals'),
        const Track(trackId: '5', seokey: 'uyire', title: 'Uyire', artist: 'Hariharan', album: 'Bombay'),
      ]);
      engine.indexAlbums([
        const Album(id: 'a1', seokey: 'ghilli', title: 'Ghilli', artist: 'Vidyasagar'),
        const Album(id: 'a2', seokey: 'bombay', title: 'Bombay', artist: 'A R Rahman'),
      ]);
      engine.indexArtists([
        const Artist(artistId: 'ar1', seokey: 'vidyasagar', name: 'Vidyasagar'),
        const Artist(artistId: 'ar2', seokey: 'anirudh', name: 'Anirudh Ravichander'),
      ]);
    });

    test('Progressive typing: G -> Gh -> Ghi -> Ghil -> Ghilli', () {
      final engine = LocalSearchEngine.instance;

      // Keystroke 1: 'g'
      var res = engine.search('g');
      expect(res.tracks.isNotEmpty, isTrue);
      final titlesG = res.tracks.map((s) => s.title.toLowerCase()).toList();
      expect(titlesG.any((t) => t.contains('ghilli')), isTrue);
      expect(titlesG.any((t) => t.contains('ghost')), isTrue);
      expect(titlesG.any((t) => t.contains('ghazal')), isTrue);
      // 'uyire' has no 'g' anywhere in title, artist, or album
      expect(titlesG.any((t) => t.contains('uyire')), isFalse);

      // Keystroke 2: 'gh'
      res = engine.search('gh');
      final titlesGh = res.tracks.map((s) => s.title.toLowerCase()).toList();
      expect(titlesGh.any((t) => t.contains('ghilli')), isTrue);
      expect(titlesGh.any((t) => t.contains('ghost')), isTrue);
      expect(titlesGh.any((t) => t.contains('ghazal')), isTrue);

      // Keystroke 3: 'ghi'
      res = engine.search('ghi');
      final titlesGhi = res.tracks.map((s) => s.title.toLowerCase()).toList();
      expect(titlesGhi.first, contains('ghilli'));
      // ghost and ghazal should NOT match 'ghi'
      expect(titlesGhi.any((t) => t.contains('ghost')), isFalse);
      expect(titlesGhi.any((t) => t.contains('ghazal')), isFalse);

      // Keystroke 4: 'ghil'
      res = engine.search('ghil');
      expect(res.tracks.first.title.toLowerCase(), contains('ghilli'));

      // Keystroke 5: 'ghilli'
      res = engine.search('ghilli');
      expect(res.tracks.first.title, 'Ghilli'); // Exact title ranked first
      expect(res.albums.first.title, 'Ghilli');
    });

    test('Parent prefix cache immediately retrieves parent matches on new character', () {
      final engine = LocalSearchEngine.instance;

      // User types 'gh'
      final parentRes = engine.search('gh');
      expect(parentRes.tracks.length, greaterThanOrEqualTo(3));

      // User types 'ghi' - engine can retrieve parent prefix candidate pool
      final cachedParent = engine.getCachedOrParentPrefix('ghi');
      expect(cachedParent, isNotNull);
      // Parent cache was 'gh' which has the Ghilli songs
      expect(cachedParent!.tracks.any((s) => s.title.contains('Ghilli')), isTrue);
    });

    test('Typo tolerance matches closely misspelled search queries', () {
      final engine = LocalSearchEngine.instance;

      // 'gilli' (missing 'h' in 'ghilli')
      final res = engine.search('gilli');
      expect(res.tracks.isNotEmpty, isTrue);
      expect(res.tracks.first.title.toLowerCase(), contains('ghilli'));
    });

    test('computeTopResult identifies the best entity across tracks, albums, and artists', () {
      final tracks = [
        const Track(trackId: '1', seokey: 'naa-ready', title: 'Naa Ready', artist: 'Anirudh Ravichander'),
      ];
      final albums = [
        const Album(id: 'a1', seokey: 'leo', title: 'Leo', artist: 'Anirudh Ravichander'),
      ];
      final artists = [
        const Artist(artistId: 'ar1', seokey: 'anirudh-ravichander', name: 'Anirudh Ravichander'),
      ];

      // Query for artist name
      final topArtist = computeTopResult('Anirudh', tracks: tracks, albums: albums, artists: artists);
      expect(topArtist, isNotNull);
      expect(topArtist!.type, 'artist');
      expect(topArtist.artist!.name, 'Anirudh Ravichander');

      // Query for song name
      final topSong = computeTopResult('Naa Ready', tracks: tracks, albums: albums, artists: artists);
      expect(topSong, isNotNull);
      expect(topSong!.type, 'song');
      expect(topSong.track!.title, 'Naa Ready');
    });

    test('mergeAndRank combines local engine items and backend API items without duplicates', () {
      final engine = LocalSearchEngine.instance;
      final localTracks = [
        const Track(trackId: '1', seokey: 'song-1', title: 'Ghilli Song 1', artist: 'Vidyasagar'),
      ];
      final remoteTracks = [
        const Track(trackId: '1', seokey: 'song-1', title: 'Ghilli Song 1', artist: 'Vidyasagar'), // Duplicate
        const Track(trackId: '2', seokey: 'song-2', title: 'Ghilli Song 2', artist: 'Vidyasagar'), // New from remote
      ];

      final merged = engine.mergeAndRank(
        query: 'ghilli',
        remote: SearchResultEntry(
          tracks: remoteTracks,
          albums: const [],
          artists: const [],
          playlists: const [],
        ),
        local: SearchResultEntry(
          tracks: localTracks,
          albums: const [],
          artists: const [],
          playlists: const [],
        ),
      );

      expect(merged.tracks.length, 2);
      expect(merged.tracks.map((s) => s.id).toSet().length, 2);
    });
  });
}
