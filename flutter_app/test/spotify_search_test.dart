import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/search/search_engine.dart';

void main() {
  setUp(() {
    LocalSearchEngine.instance.clear();
  });

  group('1. Spotify-Style 1000-Point Relevance Scale & Hierarchy', () {
    test('Exact query match always beats popularity and partial matches', () {
      const exactTrack = Track(
        trackId: '1',
        seokey: 'ghilli',
        title: 'Ghilli',
        artist: 'Vidyasagar',
        album: 'Ghilli',
        popularityScore: 0.1, // low popularity
      );
      const popularCompilation = Track(
        trackId: '2',
        seokey: 'best-of-ghilli',
        title: 'Best of Ghilli Hits Nonstop',
        artist: 'Various',
        album: 'Mega Hits',
        popularityScore: 1.0, // max popularity
      );

      final exactScore = scoreTrack(exactTrack, 'Ghilli');
      final compScore = scoreTrack(popularCompilation, 'Ghilli');

      expect(exactScore, equals(1000));
      expect(exactScore, greaterThan(compScore));
    });

    test('Hierarchy order: exact > prefix > word prefix > contains > typo', () {
      const exact = Track(trackId: '1', seokey: 'e', title: 'Azhagiye', artist: 'AR Rahman');
      const prefix = Track(trackId: '2', seokey: 'p', title: 'Azhagiye Marry Me', artist: 'AR Rahman');
      const wordPrefix = Track(trackId: '3', seokey: 'wp', title: 'Singam Azhagiye', artist: 'AR Rahman');
      const contains = Track(trackId: '4', seokey: 'c', title: 'Theazhagiye Song', artist: 'AR Rahman');
      const typo = Track(trackId: '5', seokey: 't', title: 'Azhagiyea', artist: 'AR Rahman');

      final sExact = scoreTrack(exact, 'Azhagiye');
      final sPrefix = scoreTrack(prefix, 'Azhagiye');
      final sWordPrefix = scoreTrack(wordPrefix, 'Azhagiye');
      final sContains = scoreTrack(contains, 'Azhagiye');
      final sTypo = scoreTrack(typo, 'Azhagiye');

      expect(sExact, equals(1000));
      expect(sPrefix, equals(850));
      expect(sWordPrefix, equals(750));
      expect(sContains, equals(600));
      expect(sTypo, equals(150));

      expect(sExact, greaterThan(sPrefix));
      expect(sPrefix, greaterThan(sWordPrefix));
      expect(sWordPrefix, greaterThan(sContains));
      expect(sContains, greaterThan(sTypo));
    });
  });

  group('2. Typo Tolerance & Phonetic Matching', () {
    test('Levenshtein typo matches minor spelling mistakes', () {
      const track = Track(trackId: '1', seokey: 'ghilli', title: 'Ghilli', artist: 'Vidyasagar');
      final typoScore = scoreTrack(track, 'gilli');
      expect(typoScore, greaterThanOrEqualTo(150));
    });

    test('Phonetic transliteration handles common Indic variations (zh <-> l, th <-> t, ee <-> i)', () {
      const trackZh = Track(trackId: '1', seokey: 'kozhi', title: 'Kozhi Veda', artist: 'Artist');
      final scoreL = scoreTrack(trackZh, 'koli');
      expect(scoreL, greaterThanOrEqualTo(220));

      const trackEe = Track(trackId: '2', seokey: 'preethi', title: 'Preethi', artist: 'Artist');
      final scoreI = scoreTrack(trackEe, 'priti');
      expect(scoreI, greaterThanOrEqualTo(220));
    });

    test('Exact match ALWAYS beats typo or phonetic match', () {
      const exact = Track(trackId: '1', seokey: 'anirudh', title: 'Anirudh', artist: 'Composer');
      const typo = Track(trackId: '2', seokey: 'anirud', title: 'Anirud', artist: 'Singer');

      final exactScore = scoreTrack(exact, 'anirudh');
      final typoScore = scoreTrack(typo, 'anirudh');

      expect(exactScore, equals(1000));
      expect(typoScore, lessThan(exactScore));
    });
  });

  group('3. Language Intent & Preference Handling', () {
    test('Explicit language query boosts target language', () {
      const malayalamTrack = Track(
        trackId: '1',
        seokey: 'malare',
        title: 'Malare',
        artist: 'Vijay Yesudas',
        album: 'Premam',
        language: 'malayalam',
      );
      const teluguTrack = Track(
        trackId: '2',
        seokey: 'evare',
        title: 'Evare',
        artist: 'Vijay Prakash',
        album: 'Premam',
        language: 'telugu',
      );

      final malScore = scoreTrack(malayalamTrack, 'premam malayalam');
      final telScore = scoreTrack(teluguTrack, 'premam malayalam');

      expect(malScore, greaterThan(telScore));
    });

    test('Explicit search query overrides onboarding language preference', () {
      const tamilTrack = Track(
        trackId: '1',
        seokey: 'ghilli',
        title: 'Ghilli',
        artist: 'Vidyasagar',
        album: 'Ghilli',
        language: 'tamil',
      );
      const malayalamTrack = Track(
        trackId: '2',
        seokey: 'ghilli-mal',
        title: 'Ghilli Malayalam Dubbed',
        artist: 'Singer',
        album: 'Ghilli',
        language: 'malayalam',
      );

      // User preference is Malayalam, but user typed "Ghilli"
      final ranked = rankTracksForQuery(
        [malayalamTrack, tamilTrack],
        'Ghilli',
        userLanguages: ['malayalam'],
      );

      // Exact title match (tamilTrack) must be first, not the partial preference match
      expect(ranked.first.id, equals(tamilTrack.id));
    });
  });

  group('4. Multi-Source Deduplication (JioSaavn + Gaana)', () {
    test('Deduplicates identical track across multiple providers via semantic fingerprint', () {
      const gaanaTrack = Track(
        trackId: 'gaana_123',
        seokey: 'azhagiye-1',
        title: 'Azhagiye',
        artist: 'A.R. Rahman, Arjun Chandy',
        album: 'Kaatru Veliyidai',
        durationSeconds: 224,
      );
      const jioTrack = Track(
        trackId: 'jio_456',
        seokey: 'azhagiye-2',
        title: 'Azhagiye',
        artist: 'A. R. Rahman, Haricharan',
        album: 'Kaatru Veliyidai',
        durationSeconds: 226,
      );

      final deduplicated = SearchDeduplicator.instance.deduplicateTracks([gaanaTrack, jioTrack]);
      expect(deduplicated.length, equals(1));
    });

    test('Does NOT deduplicate distinct songs with same title but different artists/albums', () {
      const song1 = Track(
        trackId: '1',
        seokey: 'kanmani-1',
        title: 'Kanmani Anbodu',
        artist: 'Kamal Haasan',
        album: 'Gunaa',
        durationSeconds: 290,
      );
      const song2 = Track(
        trackId: '2',
        seokey: 'kanmani-2',
        title: 'Kanmani',
        artist: 'Anirudh',
        album: 'Naanum Rowdy Dhaan',
        durationSeconds: 210,
      );

      final deduplicated = SearchDeduplicator.instance.deduplicateTracks([song1, song2]);
      expect(deduplicated.length, equals(2));
    });
  });

  group('5. Album Intent & Soundtrack Correlation', () {
    test('Movie/album search ranks album as top result and surfaces album tracks', () {
      final engine = LocalSearchEngine.instance;
      engine.clear();

      const album = Album(
        id: 'alb_ghilli',
        seokey: 'ghilli',
        title: 'Ghilli',
        artist: 'Vidyasagar',
      );
      const song1 = Track(
        trackId: 't1',
        seokey: 'appadi-podu',
        title: 'Appadi Podu',
        artist: 'KK, Anuradha Sriram',
        album: 'Ghilli',
      );
      const song2 = Track(
        trackId: 't2',
        seokey: 'arjunar-villu',
        title: 'Arjunar Villu',
        artist: 'Sukhwinder Singh',
        album: 'Ghilli',
      );
      const unrelatedSong = Track(
        trackId: 't3',
        seokey: 'other',
        title: 'Other Song',
        artist: 'Other',
        album: 'Other Album',
      );

      engine.indexAlbums([album]);
      engine.indexTracks([unrelatedSong, song1, song2]);

      final result = engine.searchInstant('Ghilli');

      expect(result.topResult, isNotNull);
      expect(result.topResult!.type, equals('album'));
      expect(result.topResult!.album?.title, equals('Ghilli'));

      // Songs from Ghilli should be correlated to the top of the songs list
      expect(result.tracks.isNotEmpty, isTrue);
      expect(result.tracks.first.album.toLowerCase(), equals('ghilli'));
    });
  });

  group('6. Unofficial Noise Penalty', () {
    test('Heavily penalizes karaoke, cover, ringtones, slowed reverb', () {
      const official = Track(trackId: '1', seokey: 'hymn', title: 'Hymn for the Weekend', artist: 'Coldplay');
      const cover = Track(trackId: '2', seokey: 'hymn-cover', title: 'Hymn for the Weekend (Cover)', artist: 'Artist');
      const karaoke = Track(trackId: '3', seokey: 'hymn-karaoke', title: 'Hymn for the Weekend Karaoke', artist: 'Artist');
      const ringtone = Track(trackId: '4', seokey: 'hymn-ringtone', title: 'Hymn for the Weekend Ringtone', artist: 'Artist');

      final sOff = scoreTrack(official, 'hymn for the weekend');
      final sCov = scoreTrack(cover, 'hymn for the weekend');
      final sKar = scoreTrack(karaoke, 'hymn for the weekend');
      final sRing = scoreTrack(ringtone, 'hymn for the weekend');

      expect(sOff, equals(1000));
      expect(sOff - sCov, greaterThanOrEqualTo(400));
      expect(sOff - sKar, greaterThanOrEqualTo(400));
      expect(sOff - sRing, greaterThanOrEqualTo(400));
    });
  });

  group('7. Progressive Keystroke Matching (G -> Gh -> Ghi -> Ghil -> Ghilli)', () {
    test('Narrows search candidates character-by-character', () {
      final engine = LocalSearchEngine.instance;
      engine.clear();

      engine.indexTracks([
        const Track(trackId: '1', seokey: 'ghilli', title: 'Ghilli', artist: 'Vidyasagar'),
        const Track(trackId: '2', seokey: 'ghost', title: 'Ghost', artist: 'Anirudh'),
        const Track(trackId: '3', seokey: 'ghazal', title: 'Ghazal', artist: 'Pankaj'),
        const Track(trackId: '4', seokey: 'uyire', title: 'Uyire', artist: 'Hariharan'),
      ]);

      var r = engine.searchInstant('G');
      expect(r.tracks.length, greaterThanOrEqualTo(3));

      r = engine.searchInstant('Gh');
      expect(r.tracks.any((t) => t.title == 'Ghilli'), isTrue);
      expect(r.tracks.any((t) => t.title == 'Ghost'), isTrue);

      r = engine.searchInstant('Ghi');
      expect(r.tracks.any((t) => t.title == 'Ghilli'), isTrue);
      expect(r.tracks.any((t) => t.title == 'Ghost'), isFalse);

      r = engine.searchInstant('Ghilli');
      expect(r.topResult?.track?.title, equals('Ghilli'));
      expect(r.tracks.first.title, equals('Ghilli'));
    });
  });

  group('8. Deterministic Tie-Breakers', () {
    test('Ranks items deterministically when scores are tied', () {
      const t1 = Track(trackId: 't1', seokey: 'song-a', title: 'Song Alpha Long Title', artist: 'A');
      const t2 = Track(trackId: 't2', seokey: 'song-b', title: 'Song Alpha', artist: 'A');

      final ranked = rankTracksForQuery([t1, t2], 'Song');
      // Shorter title length should break tie
      expect(ranked.first.id, equals(t2.id));
    });
  });
}
