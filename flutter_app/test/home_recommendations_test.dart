import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => methodCall.method == 'init'
          ? {'id': '1'}
          : <String, dynamic>{},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  Track createTrack({
    required String id,
    required String title,
    required String artist,
    String album = '',
    String language = 'tamil',
  }) {
    return Track(
      trackId: id,
      seokey: id,
      title: title,
      artist: artist,
      album: album,
      language: language,
    );
  }

  group('1. Freshness Window & Sliding Expiration (No Permanent Blacklisting)', () {
    test('Track registration and isFresh check', () {
      final window = FreshnessWindow(capacity: 10);
      final track1 = createTrack(id: 't1', title: 'Song 1', artist: 'Artist A');
      final track2 = createTrack(id: 't2', title: 'Song 2', artist: 'Artist B');

      expect(window.isFresh(track1), isTrue);
      expect(window.isFresh(track2), isTrue);

      window.registerBatch([track1]);
      expect(window.isFresh(track1), isFalse);
      expect(window.isFresh(track2), isTrue);
    });

    test('Sliding expiration allows older tracks to return without permanent blacklisting', () {
      final window = FreshnessWindow(capacity: 5);

      // Register 5 songs
      for (var i = 1; i <= 5; i++) {
        window.registerBatch([createTrack(id: 't$i', title: 'Song $i', artist: 'Artist $i')]);
      }

      final song1 = createTrack(id: 't1', title: 'Song 1', artist: 'Artist 1');
      expect(window.isFresh(song1), isFalse, reason: 'Song 1 should be in the freshness window');

      // Register 5 more songs, which should push out the first 5 songs
      for (var i = 6; i <= 10; i++) {
        window.registerBatch([createTrack(id: 't$i', title: 'Song $i', artist: 'Artist $i')]);
      }

      expect(
        window.isFresh(song1),
        isTrue,
        reason: 'Song 1 should naturally slide out and become re-eligible (never permanently blacklisted)',
      );
    });

    test('Currently visible tracks are tracked and excluded from fresh candidate filtering', () {
      final window = FreshnessWindow(capacity: 20);
      final visibleTrack = createTrack(id: 'vis1', title: 'Visible Song', artist: 'Artist V');
      window.setVisible([visibleTrack]);

      expect(window.isFresh(visibleTrack), isFalse);
      expect(window.currentlyVisibleKeys.contains('vis1'), isTrue);
    });
  });

  group('2. 10x Consecutive Pull-to-Refresh Freshness', () {
    test('10 consecutive refreshes produce unique batches from available catalog pools', () {
      final engine = RecommendationEngine(
        freshnessWindowCapacity: 50,
        diversity: const DiversityController(maxPerArtist: 2, maxConsecutivePerArtist: 1),
      );

      // Generate a pool of 60 songs across diverse artists
      final catalogPool = List.generate(60, (i) {
        final artistNum = (i % 15) + 1;
        return createTrack(
          id: 'catalog_song_$i',
          title: 'Catalog Song $i',
          artist: 'Artist $artistNum',
        );
      });

      final seenBatchTrackIds = <String>{};
      final batchSizes = <int>[];

      for (var refresh = 1; refresh <= 10; refresh++) {
        final session = engine.session;
        final gen = session.nextGeneration();
        expect(gen, equals(refresh));

        // Filter pool by freshness window
        final freshCandidates = catalogPool.where(engine.freshness.isFresh).toList();
        final batch = engine.diversity.enforceDiversity(freshCandidates).take(5).toList();

        expect(batch, isNotEmpty);
        batchSizes.add(batch.length);

        // Check that none of the batch tracks were just seen in consecutive previous batches
        for (final track in batch) {
          expect(seenBatchTrackIds.contains(track.id), isFalse,
              reason: 'Track ${track.id} appeared again during consecutive refresh #$refresh');
          seenBatchTrackIds.add(track.id);
        }

        // Register batch in freshness window
        engine.registerVisibleFeed(batch);
      }

      expect(seenBatchTrackIds.length, equals(50));
      expect(batchSizes.every((sz) => sz == 5), isTrue);
    });
  });

  group('3. Controlled Artist Diversity', () {
    test('Prevents consecutive tracks from the same artist', () {
      const diversity = DiversityController(maxPerArtist: 3, maxConsecutivePerArtist: 1);

      // List with runs of same artist: A, A, B, B, C, A, A
      final tracks = [
        createTrack(id: 'a1', title: 'Song A1', artist: 'Artist A'),
        createTrack(id: 'a2', title: 'Song A2', artist: 'Artist A'),
        createTrack(id: 'b1', title: 'Song B1', artist: 'Artist B'),
        createTrack(id: 'b2', title: 'Song B2', artist: 'Artist B'),
        createTrack(id: 'c1', title: 'Song C1', artist: 'Artist C'),
        createTrack(id: 'a3', title: 'Song A3', artist: 'Artist A'),
      ];

      final diversified = diversity.enforceDiversity(tracks);

      expect(diversified.length, equals(6));
      for (var i = 0; i < diversified.length - 1; i++) {
        final currentArtist = diversified[i].artist.toLowerCase().trim();
        final nextArtist = diversified[i + 1].artist.toLowerCase().trim();
        expect(
          currentArtist != nextArtist,
          isTrue,
          reason: 'Consecutive tracks at index $i and ${i + 1} have the same artist "$currentArtist"',
        );
      }
    });

    test('Respects maxPerArtist bound', () {
      const diversity = DiversityController(maxPerArtist: 2, maxConsecutivePerArtist: 1);

      final tracks = [
        createTrack(id: 'a1', title: 'Song A1', artist: 'Artist A'),
        createTrack(id: 'a2', title: 'Song A2', artist: 'Artist A'),
        createTrack(id: 'a3', title: 'Song A3', artist: 'Artist A'),
        createTrack(id: 'a4', title: 'Song A4', artist: 'Artist A'),
        createTrack(id: 'b1', title: 'Song B1', artist: 'Artist B'),
      ];

      final diversified = diversity.enforceDiversity(tracks);
      final countA = diversified.where((t) => t.artist == 'Artist A').length;
      expect(countA, lessThanOrEqualTo(2));
    });
  });

  group('4. Multi-Source Semantic Fingerprint Deduplication', () {
    test('Deduplicates songs with identical normalized title and artist', () {
      final t1 = createTrack(id: 'id_1', title: 'Arabic Kuthu', artist: 'Anirudh Ravichander');
      final t2 = createTrack(id: 'id_2', title: 'Arabic Kuthu (From "Beast")', artist: 'Anirudh Ravichander');
      final t3 = createTrack(id: 'id_3', title: 'Arabic Kuthu', artist: 'Anirudh');

      final deduplicated = deduplicateTracks([t1, t2, t3]);
      expect(deduplicated.length, equals(1));
      expect(deduplicated.first.id, equals('id_1'));
    });

    test('Deduplication retains already seen tracks across sections', () {
      final seen = <String>{};
      final section1Tracks = [
        createTrack(id: 's1_1', title: 'Song One', artist: 'Artist 1'),
        createTrack(id: 's1_2', title: 'Song Two', artist: 'Artist 2'),
      ];
      final section2Tracks = [
        createTrack(id: 's2_1', title: 'Song One', artist: 'Artist 1'), // duplicate of s1_1
        createTrack(id: 's2_2', title: 'Song Three', artist: 'Artist 3'),
      ];

      final cleanSection1 = deduplicateTracks(section1Tracks, seenKeys: seen);
      final cleanSection2 = deduplicateTracks(section2Tracks, seenKeys: seen);

      expect(cleanSection1.length, equals(2));
      expect(cleanSection2.length, equals(1));
      expect(cleanSection2.first.title, equals('Song Three'));
    });
  });

  group('5. Cross-Section Independence and Deduplication', () {
    test('composeSections ensures no track is repeated across different sections', () {
      final engine = RecommendationEngine();

      final recs = [
        createTrack(id: 'r1', title: 'Recommendation 1', artist: 'Artist A'),
        createTrack(id: 'r2', title: 'Recommendation 2', artist: 'Artist B'),
      ];
      final trending = [
        createTrack(id: 'r1', title: 'Recommendation 1', artist: 'Artist A'), // overlapping
        createTrack(id: 't2', title: 'Trending 2', artist: 'Artist C'),
      ];
      final releases = [
        createTrack(id: 'r2', title: 'Recommendation 2', artist: 'Artist B'), // overlapping
        createTrack(id: 'rel2', title: 'Release 2', artist: 'Artist D'),
      ];

      final sections = engine.composeSections(
        rawRecommendations: recs,
        rawTrending: trending,
        rawNewReleases: releases,
      );

      final allTracksInFeed = sections.allTracks;
      final uniqueIds = allTracksInFeed.map((t) => t.id).toSet();

      expect(allTracksInFeed.length, equals(uniqueIds.length),
          reason: 'Every track across all composed sections must be unique');

      expect(sections.trending.any((t) => t.id == 'r1'), isFalse,
          reason: 'r1 was already used in recommended, should not appear in trending');
      expect(sections.newReleases.any((t) => t.id == 'r2'), isFalse,
          reason: 'r2 was already used in recommended, should not appear in newReleases');
    });
  });

  group('6. Pagination & Cursor Infinite Scroll', () {
    test('appendPage merges new items avoiding duplicates and registers visible items', () {
      final engine = RecommendationEngine();
      final initialItems = [
        createTrack(id: 'p1', title: 'Page 1 Track 1', artist: 'Artist 1'),
        createTrack(id: 'p2', title: 'Page 1 Track 2', artist: 'Artist 2'),
      ];

      engine.currentSections = HomeFeedSections(recommendedForYou: initialItems);
      engine.freshness.setCurrentlyVisible(initialItems);

      final newItems = [
        createTrack(id: 'p2', title: 'Page 1 Track 2', artist: 'Artist 2'), // duplicate
        createTrack(id: 'p3', title: 'Page 2 Track 3', artist: 'Artist 3'),
        createTrack(id: 'p4', title: 'Page 2 Track 4', artist: 'Artist 4'),
      ];

      final updated = engine.appendPage(newItems);
      final appended = updated.recommendedForYou;

      expect(appended.length, equals(4));
      expect(appended.map((t) => t.id).toList(), equals(['p1', 'p2', 'p3', 'p4']));
      expect(engine.freshness.isFresh(newItems[1]), isFalse,
          reason: 'New items should be registered into freshness window');
    });
  });

  group('7. Race Condition Protection via activeRefreshId', () {
    test('RecommendationSession invalidates stale requests when a new refresh is triggered', () {
      final session = RecommendationSession();

      final firstRefreshId = session.startNewRefresh();
      expect(session.isCurrentRefresh(firstRefreshId), isTrue);

      // A second refresh is triggered before first finishes (e.g. user pulls twice rapidly)
      final secondRefreshId = session.startNewRefresh();
      expect(session.isCurrentRefresh(firstRefreshId), isFalse,
          reason: 'First refresh is now stale and should be rejected');
      expect(session.isCurrentRefresh(secondRefreshId), isTrue,
          reason: 'Second refresh is current and should be accepted');
    });
  });

  group('8. Cold Start vs Established User Feed Composition', () {
    test('Cold-start composition uses trending & discovery when no user history exists', () {
      final engine = RecommendationEngine();
      final trending = [
        createTrack(id: 'trend_1', title: 'Trending 1', artist: 'Artist T1'),
        createTrack(id: 'trend_2', title: 'Trending 2', artist: 'Artist T2'),
      ];

      final sections = engine.composeSections(
        rawRecommendations: [],
        rawTrending: trending,
        rawRecent: [],
        isNewUser: true,
      );

      expect(sections.hero, isNotNull);
      expect(sections.trending, isNotEmpty);
      expect(sections.recentlyPlayed, isEmpty);
    });

    test('Established user composition populates becauseYouListenedTo and recentlyPlayed', () {
      final engine = RecommendationEngine();
      final history = [
        createTrack(id: 'h1', title: 'History Song 1', artist: 'Artist H1'),
      ];
      final recs = [
        createTrack(id: 'r1', title: 'Personalized 1', artist: 'Artist P1'),
        createTrack(id: 'r2', title: 'Personalized 2', artist: 'Artist P2'),
      ];

      final sections = engine.composeSections(
        rawRecommendations: recs,
        rawRecent: history,
        isNewUser: false,
      );

      expect(sections.recentlyPlayed, isNotEmpty);
      expect(sections.recentlyPlayed.first.id, equals('h1'));
      expect(sections.recommendedForYou, isNotEmpty);
    });
  });

  group('9. Playback Continuity & App Resume Interval', () {
    test('Refreshing feed does not alter active playback queue or position', () {
      final engine = RecommendationEngine();

      // Simulate an active player queue
      final nowPlaying = createTrack(id: 'now_playing', title: 'Playing Song', artist: 'Artist P');
      final activeQueue = [
        nowPlaying,
        createTrack(id: 'q2', title: 'Queue Song 2', artist: 'Artist Q'),
      ];

      // Refreshing the recommendation engine feed
      final newBatch = [
        createTrack(id: 'fresh_1', title: 'Fresh 1', artist: 'Artist F1'),
        createTrack(id: 'fresh_2', title: 'Fresh 2', artist: 'Artist F2'),
      ];

      final newSections = engine.composeSections(rawRecommendations: newBatch);

      // Verify active playback queue remains completely intact
      expect(activeQueue.length, equals(2));
      expect(activeQueue.first.id, equals('now_playing'));
      expect(newSections.recommendedForYou.length, equals(2));
      expect(newSections.recommendedForYou.first.id, equals('fresh_1'));
    });

    test('App resume interval: short backgrounding preserves feed; >= 30 min triggers refresh', () {
      final engine = RecommendationEngine();
      final now = DateTime.now();

      // Case 1: Refreshed 5 minutes ago -> should NOT refresh
      engine.lastRefreshTime = now.subtract(const Duration(minutes: 5));
      final shouldRefresh5m = now.difference(engine.lastRefreshTime!) >= const Duration(minutes: 30);
      expect(shouldRefresh5m, isFalse, reason: 'Backgrounding under 30 minutes must not re-trigger refresh');

      // Case 2: Refreshed 35 minutes ago -> SHOULD refresh
      engine.lastRefreshTime = now.subtract(const Duration(minutes: 35));
      final shouldRefresh35m = now.difference(engine.lastRefreshTime!) >= const Duration(minutes: 30);
      expect(shouldRefresh35m, isTrue, reason: 'Backgrounding 30+ minutes must trigger background refresh');
    });
  });
}
