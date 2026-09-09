import 'dart:math';
import '../models.dart';

/// Cleans song titles by removing parenthetical/bracketed provider qualifiers
/// e.g. "Arabic Kuthu (From 'Beast')" -> "arabic kuthu"
String cleanSongTitle(String title) {
  var clean = title.toLowerCase();
  clean = clean.replaceAll(
      RegExp(r'\((?:from|feat\.?|ft\.?|ost|original|lyric|video|audio|remix)[^\)]*\)', caseSensitive: false), ' ');
  clean = clean.replaceAll(
      RegExp(r'\[(?:from|feat\.?|ft\.?|ost|original|lyric|video|audio|remix)[^\]]*\]', caseSensitive: false), ' ');
  clean = clean.replaceAll(RegExp(r'[\(\)\[\]\{\}"' "'" r'.,:;!/?\\|_~@#$%^&*+=<>`-]'), ' ');
  return clean.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Normalizes artist name to primary artist identifier
String cleanArtistName(String artist) {
  if (artist.isEmpty) return '';
  final primary = artist.split(RegExp(r'[,&/]')).first.trim().toLowerCase();
  final clean = primary.replaceAll(RegExp(r'[\(\)\[\]\{\}"' "'" r'.,:;!/?\\|_~@#$%^&*+=<>`-]'), ' ').trim();
  return clean.split(RegExp(r'\s+')).first;
}

/// Semantic fingerprint to unify tracks across multiple providers (Gaana, JioSaavn, etc.)
String semanticTrackFingerprint(Track track) {
  final title = cleanSongTitle(track.title);
  final primaryArtist = cleanArtistName(track.artist);
  return '$title::$primaryArtist';
}

/// Normalized canonical key for tracking track identity across ID and SEOKey variations
String canonicalTrackKey(Track track) {
  if (track.id.isNotEmpty) return track.id.toLowerCase().trim();
  if (track.seokey.isNotEmpty) return track.seokey.toLowerCase().trim();
  if (track.trackId.isNotEmpty) return track.trackId.toLowerCase().trim();
  return semanticTrackFingerprint(track);
}

/// Primary artist identifier for diversity filtering
String primaryArtistKey(Track track) {
  if (track.artist.isEmpty) return '__unknown__';
  final first = track.artist.split(RegExp(r'[,&/]')).first.trim().toLowerCase();
  return first.isNotEmpty ? first : '__unknown__';
}

/// Tracks recommendation session tokens and generation counter
class RecommendationSession {
  RecommendationSession({String? initialSessionId})
      : sessionId = initialSessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

  final String sessionId;
  int refreshGeneration = 0;
  int activeRefreshId = 0;

  int nextRefreshId() {
    activeRefreshId++;
    return activeRefreshId;
  }

  int startNewRefresh() => nextRefreshId();

  bool isCurrentRefresh(int id) => id == activeRefreshId;

  void advanceGeneration() {
    refreshGeneration++;
  }

  int nextGeneration() {
    advanceGeneration();
    return refreshGeneration;
  }
}

/// Sliding freshness window keeping recently recommended songs temporarily excluded
/// without permanently blacklisting them.
class FreshnessWindow {
  FreshnessWindow({int? maxCapacity, int? capacity})
      : maxCapacity = capacity ?? maxCapacity ?? 160;

  final int maxCapacity;
  final List<String> _recentlyRecommendedKeys = [];
  final Map<String, String> _fingerprintsByTrackKey = {};
  final Set<String> _recentlyRecommendedSet = {};
  final Set<String> currentlyVisibleKeys = {};
  final Set<String> recentlyPlayedKeys = {};

  List<String> get recentlyRecommendedKeys => List.unmodifiable(_recentlyRecommendedKeys);

  void registerBatch(Iterable<Track> tracks) => recordRecommended(tracks);

  void setVisible(Iterable<Track> tracks) => setCurrentlyVisible(tracks);

  /// Check if a track is fresh (not currently visible and not recently recommended)
  bool isFresh(Track track) {
    final key = canonicalTrackKey(track);
    final fp = semanticTrackFingerprint(track);
    if (currentlyVisibleKeys.contains(key) || currentlyVisibleKeys.contains(fp)) {
      return false;
    }
    if (_recentlyRecommendedSet.contains(key) || _recentlyRecommendedSet.contains(fp)) {
      return false;
    }
    return true;
  }

  /// Records newly recommended tracks into the sliding freshness window.
  /// When capacity exceeds maxCapacity, oldest tracks naturally expire and become re-eligible.
  void recordRecommended(Iterable<Track> tracks) {
    for (final track in tracks) {
      final key = canonicalTrackKey(track);
      final fp = semanticTrackFingerprint(track);
      if (!_recentlyRecommendedSet.contains(key)) {
        _recentlyRecommendedKeys.add(key);
        _recentlyRecommendedSet.add(key);
        _recentlyRecommendedSet.add(fp);
        _fingerprintsByTrackKey[key] = fp;
      }
    }
    while (_recentlyRecommendedKeys.length > maxCapacity) {
      final removedKey = _recentlyRecommendedKeys.removeAt(0);
      _recentlyRecommendedSet.remove(removedKey);
      final removedFp = _fingerprintsByTrackKey.remove(removedKey);
      if (removedFp != null) {
        _recentlyRecommendedSet.remove(removedFp);
      }
    }
  }

  /// Sets the track keys currently rendered on the screen
  void setCurrentlyVisible(Iterable<Track> tracks) {
    currentlyVisibleKeys.clear();
    for (final track in tracks) {
      currentlyVisibleKeys.add(canonicalTrackKey(track));
      currentlyVisibleKeys.add(semanticTrackFingerprint(track));
    }
  }

  /// Records tracks that have been played by the user
  void setRecentlyPlayed(Iterable<Track> tracks) {
    recentlyPlayedKeys.clear();
    for (final track in tracks) {
      recentlyPlayedKeys.add(canonicalTrackKey(track));
      recentlyPlayedKeys.add(semanticTrackFingerprint(track));
    }
  }

  void clear() {
    _recentlyRecommendedKeys.clear();
    _recentlyRecommendedSet.clear();
    currentlyVisibleKeys.clear();
    recentlyPlayedKeys.clear();
  }
}

/// Enforces controlled artist diversity: prevents consecutive tracks from the same artist
/// and bounds total tracks per artist within any section.
class DiversityController {
  const DiversityController({
    this.maxPerArtist = 2,
    this.maxConsecutivePerArtist = 1,
  });

  final int maxPerArtist;
  final int maxConsecutivePerArtist;

  List<Track> enforceDiversity(
    List<Track> tracks, {
    int? maxPerArtist,
    int? maxConsecutivePerArtist,
    int? overrideMaxPerArtist,
    int? overrideMaxConsecutive,
  }) {
    if (tracks.isEmpty) return const [];
    final maxArtist = maxPerArtist ?? overrideMaxPerArtist ?? this.maxPerArtist;
    final maxConsecutive = maxConsecutivePerArtist ?? overrideMaxConsecutive ?? this.maxConsecutivePerArtist;

    final artistCounts = <String, int>{};
    final result = <Track>[];
    final deferred = <Track>[];

    for (final track in tracks) {
      final artist = primaryArtistKey(track);
      final count = artistCounts[artist] ?? 0;

      if (count >= maxArtist) {
        continue;
      }

      bool isConsecutive = false;
      if (result.isNotEmpty && maxConsecutive >= 1) {
        final lastArtist = primaryArtistKey(result.last);
        if (lastArtist != '__unknown__' && lastArtist == artist) {
          isConsecutive = true;
        }
      }

      if (!isConsecutive) {
        artistCounts[artist] = count + 1;
        result.add(track);
      } else {
        deferred.add(track);
      }
    }

    // Attempt to interleave deferred tracks where they won't cause consecutive duplicates
    for (final track in deferred) {
      final artist = primaryArtistKey(track);
      final count = artistCounts[artist] ?? 0;
      if (count >= maxArtist) continue;

      bool inserted = false;
      for (var i = result.length - 1; i > 0; i--) {
        final prev = primaryArtistKey(result[i - 1]);
        final next = primaryArtistKey(result[i]);
        if (prev != artist && next != artist) {
          result.insert(i, track);
          artistCounts[artist] = count + 1;
          inserted = true;
          break;
        }
      }
      if (!inserted && (result.isEmpty || primaryArtistKey(result.last) != artist)) {
        result.add(track);
        artistCounts[artist] = count + 1;
      }
    }

    return result;
  }
}

/// Container for independent, cross-deduplicated home feed sections
class HomeFeedSections {
  const HomeFeedSections({
    this.hero,
    this.recommendedForYou = const [],
    this.becauseYouListenedTo = const [],
    this.favoriteArtistsTracks = const [],
    this.newReleases = const [],
    this.trending = const [],
    this.recentlyPopular = const [],
    this.discoverSomethingNew = const [],
    this.recentlyPlayed = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  final Track? hero;
  final List<Track> recommendedForYou;
  final List<Track> becauseYouListenedTo;
  final List<Track> favoriteArtistsTracks;
  final List<Track> newReleases;
  final List<Track> trending;
  final List<Track> recentlyPopular;
  final List<Track> discoverSomethingNew;
  final List<Track> recentlyPlayed;
  final List<Album> albums;
  final List<Artist> artists;
  final List<CollectionItem> playlists;

  List<Artist> get favoriteArtists => artists;

  bool get isEmpty =>
      hero == null &&
      recommendedForYou.isEmpty &&
      trending.isEmpty &&
      newReleases.isEmpty &&
      recentlyPlayed.isEmpty;

  List<Track> get allTracks {
    final seen = <String>{};
    final list = <Track>[];
    for (final track in [
      ?hero,
      ...recommendedForYou,
      ...becauseYouListenedTo,
      ...favoriteArtistsTracks,
      ...newReleases,
      ...trending,
      ...recentlyPopular,
      ...discoverSomethingNew,
      ...recentlyPlayed,
    ]) {
      final key = canonicalTrackKey(track);
      if (seen.add(key)) {
        list.add(track);
      }
    }
    return list;
  }

  HomeFeedSections copyWith({
    Track? hero,
    List<Track>? recommendedForYou,
    List<Track>? becauseYouListenedTo,
    List<Track>? favoriteArtistsTracks,
    List<Track>? newReleases,
    List<Track>? trending,
    List<Track>? recentlyPopular,
    List<Track>? discoverSomethingNew,
    List<Track>? recentlyPlayed,
    List<Album>? albums,
    List<Artist>? artists,
    List<CollectionItem>? playlists,
  }) {
    return HomeFeedSections(
      hero: hero ?? this.hero,
      recommendedForYou: recommendedForYou ?? this.recommendedForYou,
      becauseYouListenedTo: becauseYouListenedTo ?? this.becauseYouListenedTo,
      favoriteArtistsTracks: favoriteArtistsTracks ?? this.favoriteArtistsTracks,
      newReleases: newReleases ?? this.newReleases,
      trending: trending ?? this.trending,
      recentlyPopular: recentlyPopular ?? this.recentlyPopular,
      discoverSomethingNew: discoverSomethingNew ?? this.discoverSomethingNew,
      recentlyPlayed: recentlyPlayed ?? this.recentlyPlayed,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      playlists: playlists ?? this.playlists,
    );
  }
}

/// Top-level helper to deduplicate tracks against a seen set and internal duplicates
List<Track> deduplicateTracks(Iterable<Track> tracks, {Set<String>? seenKeys}) =>
    RecommendationEngine().deduplicateTracks(tracks, seenKeys: seenKeys);

/// Central Recommendation Engine managing state, freshness, diversity, and pagination
class RecommendationEngine {
  RecommendationEngine({
    RecommendationSession? session,
    FreshnessWindow? freshness,
    DiversityController? diversity,
    int? freshnessWindowCapacity,
  })  : session = session ?? RecommendationSession(),
        freshness = freshness ??
            FreshnessWindow(
              maxCapacity: freshnessWindowCapacity ?? 160,
            ),
        diversity = diversity ?? const DiversityController();

  final RecommendationSession session;
  final FreshnessWindow freshness;
  final DiversityController diversity;

  HomeFeedSections currentSections = const HomeFeedSections();
  bool isRefreshing = false;
  bool isLoadingMore = false;
  bool hasMore = true;
  int cursor = 0;

  DateTime? lastRefreshTime;

  /// Registers tracks as visible in the feed and sliding window
  void registerVisibleFeed(Iterable<Track> tracks) {
    freshness.recordRecommended(tracks);
    freshness.setCurrentlyVisible(tracks);
  }

  /// Deduplicates an input track list against a seen set and internal duplicates
  List<Track> deduplicateTracks(Iterable<Track> tracks, {Set<String>? seenKeys}) {
    final seen = seenKeys ?? <String>{};
    final unique = <Track>[];
    for (final track in tracks) {
      final key = canonicalTrackKey(track);
      final fp = semanticTrackFingerprint(track);
      if (!seen.contains(key) && !seen.contains(fp)) {
        seen.add(key);
        seen.add(fp);
        unique.add(track);
      }
    }
    return unique;
  }

  /// Composes distinct, non-overlapping home sections from raw candidate pools
  HomeFeedSections composeSections({
    List<Track> rawRecommendations = const [],
    List<Track> rawTrending = const [],
    List<Track> rawRecent = const [],
    List<Track> rawNewReleases = const [],
    List<Track> rawArtistTracks = const [],
    List<Track> rawDiscovery = const [],
    List<Album> rawAlbums = const [],
    List<Artist> rawArtists = const [],
    List<CollectionItem> rawPlaylists = const [],
    bool isNewUser = false,
  }) {
    final sectionSeen = <String>{};

    // 1. Recently Played (if available) takes first identity reservation
    final cleanRecent = deduplicateTracks(rawRecent, seenKeys: sectionSeen);
    freshness.setRecentlyPlayed(cleanRecent);

    // 2. Recommended for You (diverse, filtered by freshness window)
    final freshRecCandidates = rawRecommendations.where(freshness.isFresh).toList();
    final recPool = freshRecCandidates.isNotEmpty ? freshRecCandidates : rawRecommendations;
    final diverseRecs = diversity.enforceDiversity(
      deduplicateTracks(recPool, seenKeys: sectionSeen),
      maxPerArtist: 2,
    );

    // 3. Hero Featured Track
    final hero = diverseRecs.isNotEmpty
        ? diverseRecs.first
        : (cleanRecent.isNotEmpty
            ? cleanRecent.first
            : (rawTrending.isNotEmpty ? rawTrending.first : null));

    // 4. Because You Listened To (seeded from history or top artists)
    final becauseListenedCandidates = rawRecent.isNotEmpty
        ? rawRecommendations.where((t) => !diverseRecs.contains(t)).toList()
        : rawArtistTracks;
    final becauseListened = diversity.enforceDiversity(
      deduplicateTracks(becauseListenedCandidates, seenKeys: sectionSeen),
      maxPerArtist: 2,
    );

    // 5. Trending in Your Languages
    final cleanTrending = diversity.enforceDiversity(
      deduplicateTracks(rawTrending, seenKeys: sectionSeen),
      maxPerArtist: 2,
    );

    // 6. New Releases
    final cleanReleases = diversity.enforceDiversity(
      deduplicateTracks(rawNewReleases, seenKeys: sectionSeen),
      maxPerArtist: 2,
    );

    // 7. Favorite Artists Tracks
    final cleanArtistTracks = diversity.enforceDiversity(
      deduplicateTracks(rawArtistTracks, seenKeys: sectionSeen),
      maxPerArtist: 2,
    );

    // 8. Discover Something New (exploratory, diverse)
    final cleanDiscovery = diversity.enforceDiversity(
      deduplicateTracks(rawDiscovery, seenKeys: sectionSeen),
      maxPerArtist: 1,
    );

    // 9. Albums, Artists, Playlists
    final seenAlbumKeys = <String>{};
    final uniqueAlbums = <Album>[];
    for (final album in rawAlbums) {
      final key = album.id.isNotEmpty ? album.id : album.title.toLowerCase().trim();
      if (seenAlbumKeys.add(key)) {
        uniqueAlbums.add(album);
      }
    }

    final seenArtistKeys = <String>{};
    final uniqueArtists = <Artist>[];
    for (final artist in rawArtists) {
      final key = artist.name.toLowerCase().trim();
      if (key.isNotEmpty && seenArtistKeys.add(key)) {
        uniqueArtists.add(artist);
      }
    }

    final cleanPopular = diversity.enforceDiversity(
      deduplicateTracks(rawTrending, seenKeys: sectionSeen),
      maxPerArtist: 2,
    );

    final sections = HomeFeedSections(
      hero: hero,
      recommendedForYou: diverseRecs,
      becauseYouListenedTo: becauseListened,
      favoriteArtistsTracks: cleanArtistTracks,
      newReleases: cleanReleases,
      trending: cleanTrending,
      recentlyPopular: cleanPopular,
      discoverSomethingNew: cleanDiscovery,
      recentlyPlayed: cleanRecent,
      albums: uniqueAlbums,
      artists: uniqueArtists,
      playlists: rawPlaylists,
    );

    // Record recommended items into sliding freshness window
    freshness.recordRecommended(diverseRecs);
    freshness.recordRecommended(cleanTrending);
    freshness.recordRecommended(cleanReleases);
    freshness.setCurrentlyVisible(sections.allTracks);

    return sections;
  }

  /// Appends a new page of unique recommendations
  HomeFeedSections appendPage(List<Track> newTracks) {
    final currentSeen = Set<String>.from(freshness.currentlyVisibleKeys);
    final freshNewTracks = deduplicateTracks(newTracks, seenKeys: currentSeen);
    final diversePage = diversity.enforceDiversity(freshNewTracks);

    final updatedRecs = [...currentSections.recommendedForYou, ...diversePage];
    freshness.recordRecommended(diversePage);
    freshness.setCurrentlyVisible([...currentSections.allTracks, ...diversePage]);

    currentSections = currentSections.copyWith(
      recommendedForYou: updatedRecs,
    );
    cursor += diversePage.length;
    return currentSections;
  }
}
