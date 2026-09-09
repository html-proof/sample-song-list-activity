import '../models.dart';

class SearchResultEntry {
  SearchResultEntry({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.playlists,
    this.topResult,
    this.isFromCache = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Map<String, dynamic>> playlists;
  final SearchTopResult? topResult;
  final bool isFromCache;
  final DateTime timestamp;

  bool get isEmpty =>
      tracks.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty &&
      topResult == null;

  bool get isNotEmpty => !isEmpty;

  SearchResultEntry copyWith({
    List<Track>? tracks,
    List<Album>? albums,
    List<Artist>? artists,
    List<Map<String, dynamic>>? playlists,
    SearchTopResult? topResult,
    bool? isFromCache,
  }) =>
      SearchResultEntry(
        tracks: tracks ?? this.tracks,
        albums: albums ?? this.albums,
        artists: artists ?? this.artists,
        playlists: playlists ?? this.playlists,
        topResult: topResult ?? this.topResult,
        isFromCache: isFromCache ?? this.isFromCache,
        timestamp: timestamp,
      );
}

/// A high-performance in-memory search engine providing instant Spotify-style
/// search results (< 10ms) from memory cache and catalog pools before remote refinement.
class LocalSearchEngine {
  LocalSearchEngine._();
  static final LocalSearchEngine instance = LocalSearchEngine._();

  static const int _maxCacheEntries = 400;

  final Map<String, SearchResultEntry> _prefixCache = {};
  final Map<String, Track> _trackPool = {};
  final Map<String, Album> _albumPool = {};
  final Map<String, Artist> _artistPool = {};
  final Map<String, Map<String, dynamic>> _playlistPool = {};

  // ---------------------------------------------------------------------------
  // Catalog Pool Ingestion
  // ---------------------------------------------------------------------------

  String _trackKey(Track t) {
    if (t.id.isNotEmpty) return t.id.toLowerCase();
    return '${normalizeSearchText(t.title)}_${normalizeSearchText(t.artist)}';
  }

  String _albumKey(Album a) {
    if (a.id.isNotEmpty) return a.id.toLowerCase();
    return '${normalizeSearchText(a.title)}_${normalizeSearchText(a.artist)}';
  }

  String _artistKey(Artist a) {
    if (a.id.isNotEmpty) return a.id.toLowerCase();
    return normalizeSearchText(a.name);
  }

  void indexTrack(Track track) {
    final key = _trackKey(track);
    if (key.isNotEmpty) _trackPool[key] = track;
  }

  void indexTracks(Iterable<Track> tracks) {
    for (final t in tracks) {
      indexTrack(t);
    }
  }

  void indexAlbum(Album album) {
    final key = _albumKey(album);
    if (key.isNotEmpty) _albumPool[key] = album;
  }

  void indexAlbums(Iterable<Album> albums) {
    for (final a in albums) {
      indexAlbum(a);
    }
  }

  void indexArtist(Artist artist) {
    final key = _artistKey(artist);
    if (key.isNotEmpty) _artistPool[key] = artist;
  }

  void indexArtists(Iterable<Artist> artists) {
    for (final a in artists) {
      indexArtist(a);
    }
  }

  void indexPlaylists(Iterable<Map<String, dynamic>> playlists) {
    for (final p in playlists) {
      final id = '${p['id'] ?? p['seokey'] ?? p['name'] ?? ''}'.trim().toLowerCase();
      if (id.isNotEmpty) _playlistPool[id] = p;
    }
  }

  // ---------------------------------------------------------------------------
  // Cache Management
  // ---------------------------------------------------------------------------

  void recordSearchResult(String query, SearchResultEntry entry) {
    final q = normalizeSearchText(query);
    if (q.isEmpty) return;

    indexTracks(entry.tracks);
    indexAlbums(entry.albums);
    indexArtists(entry.artists);
    indexPlaylists(entry.playlists);

    _prefixCache[q] = entry.copyWith(isFromCache: true);
    if (_prefixCache.length > _maxCacheEntries) {
      _prefixCache.remove(_prefixCache.keys.first);
    }
  }

  void clearCache() {
    _prefixCache.clear();
  }

  void clear() {
    _prefixCache.clear();
    _trackPool.clear();
    _albumPool.clear();
    _artistPool.clear();
    _playlistPool.clear();
  }

  SearchResultEntry? getCachedOrParentPrefix(String rawQuery) {
    final q = normalizeSearchText(rawQuery);
    if (q.isEmpty) return null;
    if (_prefixCache.containsKey(q)) {
      return _prefixCache[q];
    }
    for (int len = q.length - 1; len >= 1; len--) {
      final prefix = q.substring(0, len);
      final parent = _prefixCache[prefix];
      if (parent != null && parent.isNotEmpty) {
        return parent;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Instant Search (< 10ms)
  // ---------------------------------------------------------------------------

  /// Convenience alias for [searchInstant].
  SearchResultEntry search(
    String rawQuery, {
    String filter = 'All',
    List<String>? userLanguages,
    List<String>? userArtists,
  }) =>
      searchInstant(
        rawQuery,
        filter: filter,
        userLanguages: userLanguages,
        userArtists: userArtists,
      );

  /// Execute a pure in-memory search instantly for [rawQuery].
  /// Tries exact prefix cache → parent prefix filtering → global pool search.
  SearchResultEntry searchInstant(
    String rawQuery, {
    String filter = 'All',
    List<String>? userLanguages,
    List<String>? userArtists,
  }) {
    final q = normalizeSearchText(rawQuery);
    if (q.isEmpty) {
      return SearchResultEntry(
        tracks: const [],
        albums: const [],
        artists: const [],
        playlists: const [],
      );
    }

    // 1. Exact cache hit
    if (_prefixCache.containsKey(q)) {
      final hit = _prefixCache[q]!;
      return _applyFilter(hit, filter);
    }

    // 2. Parent prefix walk (e.g. user typed "ghi", check "gh", then "g")
    for (int len = q.length - 1; len >= 1; len--) {
      final prefix = q.substring(0, len);
      final parent = _prefixCache[prefix];
      if (parent != null && parent.isNotEmpty) {
        final filteredTracks = parent.tracks
            .where((t) => scoreTrack(t, q, userLanguages: userLanguages, userArtists: userArtists) >= 80)
            .toList();
        final filteredAlbums = parent.albums
            .where((a) => scoreAlbum(a, q, userLanguages: userLanguages, userArtists: userArtists) >= 80)
            .toList();
        final filteredArtists = parent.artists
            .where((a) => scoreArtist(a, q, userArtists: userArtists) >= 80)
            .toList();
        final filteredPlaylists = parent.playlists.where((p) {
          final name = normalizeSearchText('${p['name'] ?? ''}');
          return name.contains(q) || name.startsWith(q);
        }).toList();

        final rankedTracks = rankTracksForQuery(
          filteredTracks,
          q,
          userLanguages: userLanguages,
          userArtists: userArtists,
        );
        final rankedAlbums = rankAlbumsForQuery(
          filteredAlbums,
          q,
          userLanguages: userLanguages,
          userArtists: userArtists,
        );
        final rankedArtists = rankArtistsForQuery(
          filteredArtists,
          q,
          userArtists: userArtists,
        );

        final top = computeTopResult(
          q,
          tracks: rankedTracks,
          albums: rankedAlbums,
          artists: rankedArtists,
        );

        final orderedTracks = _correlateTracksWithTopAlbum(top, rankedTracks);

        final result = SearchResultEntry(
          tracks: orderedTracks,
          albums: rankedAlbums,
          artists: rankedArtists,
          playlists: filteredPlaylists,
          topResult: top,
          isFromCache: true,
        );

        if (result.isNotEmpty) {
          _prefixCache[q] = result;
          return _applyFilter(result, filter);
        }
      }
    }

    // 3. Search the indexed global pool (recent, trending, favorites, past searches)
    final matchedTracks = _trackPool.values
        .where((t) => scoreTrack(t, q, userLanguages: userLanguages, userArtists: userArtists) >= 80)
        .toList();
    final matchedAlbums = _albumPool.values
        .where((a) => scoreAlbum(a, q, userLanguages: userLanguages, userArtists: userArtists) >= 80)
        .toList();
    final matchedArtists = _artistPool.values
        .where((a) => scoreArtist(a, q, userArtists: userArtists) >= 80)
        .toList();
    final matchedPlaylists = _playlistPool.values.where((p) {
      final name = normalizeSearchText('${p['name'] ?? ''}');
      return name.contains(q) || name.startsWith(q);
    }).toList();

    final rankedTracks = rankTracksForQuery(
      matchedTracks,
      q,
      userLanguages: userLanguages,
      userArtists: userArtists,
    );
    final rankedAlbums = rankAlbumsForQuery(
      matchedAlbums,
      q,
      userLanguages: userLanguages,
      userArtists: userArtists,
    );
    final rankedArtists = rankArtistsForQuery(
      matchedArtists,
      q,
      userArtists: userArtists,
    );

    final top = computeTopResult(
      q,
      tracks: rankedTracks,
      albums: rankedAlbums,
      artists: rankedArtists,
    );

    final orderedTracks = _correlateTracksWithTopAlbum(top, rankedTracks);

    final poolResult = SearchResultEntry(
      tracks: orderedTracks,
      albums: rankedAlbums,
      artists: rankedArtists,
      playlists: matchedPlaylists,
      topResult: top,
      isFromCache: true,
    );

    if (poolResult.isNotEmpty) {
      _prefixCache[q] = poolResult;
    }
    return _applyFilter(poolResult, filter);
  }

  // ---------------------------------------------------------------------------
  // Merge Remote & Local Results
  // ---------------------------------------------------------------------------

  /// Merges remote results with local items, deduplicates, re-ranks with
  /// Spotify scoring weights, and saves into prefix cache.
  SearchResultEntry mergeAndRank({
    required String query,
    required SearchResultEntry remote,
    SearchResultEntry? local,
    List<String>? userLanguages,
    List<String>? userArtists,
  }) {
    final q = normalizeSearchText(query);
    if (q.isEmpty) return remote;

    // Index remote items into pool
    indexTracks(remote.tracks);
    indexAlbums(remote.albums);
    indexArtists(remote.artists);
    indexPlaylists(remote.playlists);

    // Multi-source deduplication
    final deduplicator = SearchDeduplicator.instance;
    final combinedTracks = deduplicator.deduplicateTracks([
      ...remote.tracks,
      ...?(local?.tracks),
    ]);
    final combinedAlbums = deduplicator.deduplicateAlbums([
      ...remote.albums,
      ...?(local?.albums),
    ]);
    final combinedArtists = deduplicator.deduplicateArtists([
      ...remote.artists,
      ...?(local?.artists),
    ]);
    final combinedPlaylists = deduplicator.deduplicatePlaylists([
      ...remote.playlists,
      ...?(local?.playlists),
    ]);

    final rankedTracks = rankTracksForQuery(
      combinedTracks,
      q,
      userLanguages: userLanguages,
      userArtists: userArtists,
    );
    final rankedAlbums = rankAlbumsForQuery(
      combinedAlbums,
      q,
      userLanguages: userLanguages,
      userArtists: userArtists,
    );
    final rankedArtists = rankArtistsForQuery(
      combinedArtists,
      q,
      userArtists: userArtists,
    );

    // Compute top result if remote doesn't have a high confidence one
    final top = (remote.topResult != null && remote.topResult!.confidence >= 0.7)
        ? remote.topResult
        : computeTopResult(
            q,
            tracks: rankedTracks,
            albums: rankedAlbums,
            artists: rankedArtists,
          ) ??
          remote.topResult;

    // When top result is an Album/Movie, correlate its songs to the top of the track list
    final orderedTracks = _correlateTracksWithTopAlbum(top, rankedTracks);

    final merged = SearchResultEntry(
      tracks: orderedTracks,
      albums: rankedAlbums,
      artists: rankedArtists,
      playlists: combinedPlaylists,
      topResult: top,
      isFromCache: false,
    );

    recordSearchResult(query, merged);
    return merged;
  }

  /// When Top Result is an Album/Movie (e.g. "Ghilli"), prioritize songs
  /// belonging to that album at the top of the Songs list.
  List<Track> _correlateTracksWithTopAlbum(SearchTopResult? top, List<Track> tracks) {
    if (top == null || top.type != 'album' || top.album == null || tracks.isEmpty) {
      return tracks;
    }

    final albumTitle = normalizeSearchText(top.album!.title);
    final albumId = top.album!.id.toLowerCase();
    final albumSeokey = top.album!.seokey.toLowerCase();

    final albumTracks = <Track>[];
    final otherTracks = <Track>[];

    for (final t in tracks) {
      final tAlbum = normalizeSearchText(t.album);
      final isFromAlbum = (albumTitle.isNotEmpty && tAlbum == albumTitle) ||
          (albumId.isNotEmpty && (t.albumId.toLowerCase() == albumId || t.id.toLowerCase() == albumId)) ||
          (albumSeokey.isNotEmpty && t.albumSeokey.toLowerCase() == albumSeokey);

      if (isFromAlbum) {
        albumTracks.add(t);
      } else {
        otherTracks.add(t);
      }
    }

    return [...albumTracks, ...otherTracks];
  }

  SearchResultEntry _applyFilter(SearchResultEntry entry, String filter) {
    if (filter == 'All') return entry;
    return SearchResultEntry(
      tracks: filter == 'Songs' ? entry.tracks : const [],
      albums: filter == 'Albums' ? entry.albums : const [],
      artists: filter == 'Artists' ? entry.artists : const [],
      playlists: filter == 'Playlists' ? entry.playlists : const [],
      topResult: (filter == 'Songs' && entry.topResult?.type == 'song') ||
              (filter == 'Albums' && entry.topResult?.type == 'album') ||
              (filter == 'Artists' && entry.topResult?.type == 'artist') ||
              (filter == 'Playlists' && entry.topResult?.type == 'playlist')
          ? entry.topResult
          : null,
      isFromCache: entry.isFromCache,
      timestamp: entry.timestamp,
    );
  }
}
