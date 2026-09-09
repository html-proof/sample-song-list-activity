import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../models.dart';
import 'search_engine.dart';

/// Centralized Spotify-Style Search Controller.
///
/// Encapsulates:
/// - Immediate 0ms local search & prefix cache
/// - Progressive keystroke narrowing
/// - Debounced remote API search (100ms)
/// - Sequence ID tracking to eliminate race conditions
/// - Multi-source deduplication & intent detection
/// - Stable isolated search state that never re-renders unexpectedly
class MusicSearchController extends ChangeNotifier {
  MusicSearchController({required this.state}) {
    seedLocalCatalog();
    loadRecentSearches();
  }

  final AppState state;

  Timer? _debounce;
  int _sequence = 0;
  String _activeQuery = '';
  String _selectedFilter = 'All';

  bool _isRemoteLoading = false;
  bool _hasCompletedSearch = false;
  String? _searchError;
  SearchTopResult? _topResult;
  List<Track> _tracks = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> _recentSearches = [];

  String get activeQuery => _activeQuery;
  String get selectedFilter => _selectedFilter;
  bool get isRemoteLoading => _isRemoteLoading;
  bool get hasCompletedSearch => _hasCompletedSearch;
  String? get searchError => _searchError;
  SearchTopResult? get topResult => _topResult;
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Album> get albums => List.unmodifiable(_albums);
  List<Artist> get artists => List.unmodifiable(_artists);
  List<Map<String, dynamic>> get playlists => List.unmodifiable(_playlists);
  List<Map<String, dynamic>> get recentSearches => List.unmodifiable(_recentSearches);
  bool get hasResults =>
      _tracks.isNotEmpty ||
      _albums.isNotEmpty ||
      _artists.isNotEmpty ||
      _playlists.isNotEmpty ||
      _topResult != null;

  void setFilter(String filter) {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    search(_activeQuery, forceFilterChange: true);
  }

  List<String> get _userLanguages {
    final list = state.profile['language_ids'] as List?;
    if (list != null && list.isNotEmpty) {
      return list.map((e) => '$e').toList();
    }
    return state.selectedLanguages.toList();
  }

  List<String> get _userArtists {
    final list = state.profile['favorite_artists'] as List?;
    if (list != null && list.isNotEmpty) {
      return list.map((e) => '$e').toList();
    }
    return state.selectedArtists.toList();
  }

  void seedLocalCatalog() {
    final engine = LocalSearchEngine.instance;
    engine.indexTracks(state.trending);
    engine.indexTracks(state.recommendations);
    engine.indexTracks(state.recentlyPlayed);
    engine.indexTracks(state.favorites);
    engine.indexArtists(state.onboardingArtists);
    for (final c in state.collections) {
      if (c.title.isNotEmpty) {
        engine.indexPlaylists([
          {
            'id': c.id,
            'seokey': c.seokey,
            'name': c.title,
            'title': c.title,
            'image_url': c.imageUrl,
          }
        ]);
      }
    }
    engine.indexPlaylists(state.userPlaylists);
  }

  Future<void> loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localList = prefs.getStringList('local_recent_searches') ?? [];
      List<Map<String, dynamic>> list =
          localList.map((q) => <String, dynamic>{'query': q}).toList();

      if (state.auth.isSignedIn) {
        try {
          final remote = await state.api.recentSearches();
          if (remote.isNotEmpty) {
            final mergedQueries = <String>{};
            final merged = <Map<String, dynamic>>[];
            for (final item in [...remote, ...list]) {
              final q = '${item['query'] ?? ''}'.trim();
              if (q.isNotEmpty && mergedQueries.add(q.toLowerCase())) {
                merged.add({'id': item['id'], 'query': q});
              }
            }
            list = merged;
          }
        } catch (_) {}
      }

      _recentSearches = list;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> saveQueryToHistory(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var localList = prefs.getStringList('local_recent_searches') ?? [];
      localList.removeWhere((q) => q.toLowerCase() == cleanQuery.toLowerCase());
      localList.insert(0, cleanQuery);
      if (localList.length > 20) {
        localList = localList.sublist(0, 20);
      }
      await prefs.setStringList('local_recent_searches', localList);

      if (state.auth.isSignedIn) {
        unawaited(state.api.saveRecentSearch(cleanQuery).catchError((_) {}));
      }

      _recentSearches = localList.map((q) => {'query': q}).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> deleteRecentSearchItem(int index) async {
    if (index < 0 || index >= _recentSearches.length) return;
    final item = _recentSearches[index];
    final query = '${item['query'] ?? ''}'.trim();
    final searchId = item['id'] as String?;

    try {
      final prefs = await SharedPreferences.getInstance();
      var localList = prefs.getStringList('local_recent_searches') ?? [];
      localList.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
      await prefs.setStringList('local_recent_searches', localList);

      if (searchId != null && searchId.isNotEmpty && state.auth.isSignedIn) {
        unawaited(state.api.deleteRecentSearch(searchId).catchError((_) {}));
      }
    } catch (_) {}

    _recentSearches.removeAt(index);
    notifyListeners();
  }

  Future<void> clearAllSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('local_recent_searches');

      if (state.auth.isSignedIn) {
        unawaited(state.api.clearRecentSearches().catchError((_) {}));
      }
    } catch (_) {}

    _recentSearches = [];
    notifyListeners();
  }

  /// Primary search entry point. Reacts instantly to every keystroke (< 10ms),
  /// narrows visible results, and schedules debounced remote refinement.
  void search(String value, {bool forceFilterChange = false}) {
    _debounce?.cancel();
    final requestSeq = ++_sequence;
    final query = value.trim();
    final isNewQuery = query != _activeQuery;
    _activeQuery = query;

    if (query.isEmpty) {
      _topResult = null;
      _tracks = [];
      _albums = [];
      _artists = [];
      _playlists = [];
      _searchError = null;
      _isRemoteLoading = false;
      _hasCompletedSearch = false;
      notifyListeners();
      return;
    }

    seedLocalCatalog();

    // -------------------------------------------------------------------------
    // Phase 1: INSTANT LOCAL SEARCH (< 10 ms, zero network wait)
    // -------------------------------------------------------------------------
    final localResult = LocalSearchEngine.instance.searchInstant(
      query,
      filter: _selectedFilter,
      userLanguages: _userLanguages,
      userArtists: _userArtists,
    );

    if (localResult.isNotEmpty) {
      _topResult = localResult.topResult;
      _tracks = localResult.tracks;
      _albums = localResult.albums;
      _artists = localResult.artists;
      _playlists = localResult.playlists;
      _searchError = null;
      _hasCompletedSearch = true;
    } else if (isNewQuery && (_tracks.isNotEmpty || _albums.isNotEmpty || _artists.isNotEmpty)) {
      // Keystroke continuation: progressively filter existing visible results
      final filteredTracks = rankTracksForQuery(
        _tracks.where((t) => scoreTrack(t, query) >= 150).toList(),
        query,
        userLanguages: _userLanguages,
        userArtists: _userArtists,
      );
      final filteredAlbums = rankAlbumsForQuery(
        _albums.where((a) => scoreAlbum(a, query) >= 150).toList(),
        query,
        userLanguages: _userLanguages,
        userArtists: _userArtists,
      );
      final filteredArtists = rankArtistsForQuery(
        _artists.where((a) => scoreArtist(a, query) >= 150).toList(),
        query,
        userArtists: _userArtists,
      );

      if (filteredTracks.isNotEmpty || filteredAlbums.isNotEmpty || filteredArtists.isNotEmpty) {
        _tracks = filteredTracks;
        _albums = filteredAlbums;
        _artists = filteredArtists;
        _topResult = computeTopResult(
          query,
          tracks: _tracks,
          albums: _albums,
          artists: _artists,
        );
        _hasCompletedSearch = true;
      }
    }

    _isRemoteLoading = true;
    _searchError = null;
    notifyListeners();

    // -------------------------------------------------------------------------
    // Phase 2: DEBOUNCED BACKGROUND REMOTE REFINEMENT (~100 ms)
    // -------------------------------------------------------------------------
    _debounce = Timer(const Duration(milliseconds: 100), () async {
      if (requestSeq != _sequence || query != _activeQuery) return;

      try {
        Future<Map<String, dynamic>> executeSearch(String q) async {
          return _selectedFilter == 'All'
              ? await state.api.categorizedSearch(q)
              : <String, dynamic>{
                  'songs': _selectedFilter == 'Songs'
                      ? await state.api.typedSearch(q, 'songs')
                      : const [],
                  'artists': _selectedFilter == 'Artists'
                      ? await state.api.typedSearch(q, 'artists')
                      : const [],
                  'albums': _selectedFilter == 'Albums'
                      ? await state.api.typedSearch(q, 'albums')
                      : const [],
                  'playlists': _selectedFilter == 'Playlists'
                      ? await state.api.typedSearch(q, 'playlists')
                      : const [],
                };
        }

        Map<String, dynamic> result;
        try {
          result = await executeSearch(query);
        } catch (_) {
          if (requestSeq != _sequence || query != _activeQuery) return;
          await Future.delayed(const Duration(milliseconds: 200));
          if (requestSeq != _sequence || query != _activeQuery) return;
          result = await executeSearch(query);
        }

        if (requestSeq != _sequence || query != _activeQuery) return;

        var parsedTracks = Track.list(result['songs']);
        var parsedAlbums = (result['albums'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Album.fromJson(Map<String, dynamic>.from(item)))
            .toList();

        // Resilient expansion fallback for short/numeric keywords (e.g. "3", "24", "96")
        if (parsedTracks.isEmpty && parsedAlbums.isEmpty) {
          final cleanTerm = query.replaceAll(RegExp(r'[^a-zA-Z0-9\s]+'), ' ').trim();
          final expansions = [
            if (cleanTerm.isNotEmpty && cleanTerm != query) cleanTerm,
            '$query movie',
            '$query songs',
            '$query song',
          ];

          for (final exp in expansions) {
            if (requestSeq != _sequence || query != _activeQuery) return;
            try {
              final expResult = await executeSearch(exp);
              final expTracks = Track.list(expResult['songs']);
              final expAlbums = (expResult['albums'] as List? ?? const [])
                  .whereType<Map>()
                  .map((item) => Album.fromJson(Map<String, dynamic>.from(item)))
                  .toList();
              if (expTracks.isNotEmpty || expAlbums.isNotEmpty) {
                result = expResult;
                parsedTracks = expTracks;
                parsedAlbums = expAlbums;
                break;
              }
            } catch (_) {}
          }
        }

        if (requestSeq != _sequence || query != _activeQuery) return;

        final rawArtists = (result['artists'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Artist.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        final rawPlaylists = (result['playlists'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

        SearchTopResult? parsedTop;
        if (result['top_result'] is Map) {
          try {
            parsedTop = SearchTopResult.fromJson(
              Map<String, dynamic>.from(result['top_result']),
            );
          } catch (_) {}
        }

        final remoteEntry = SearchResultEntry(
          tracks: parsedTracks,
          albums: parsedAlbums,
          artists: rawArtists,
          playlists: rawPlaylists,
          topResult: parsedTop,
        );

        final currentLocal = SearchResultEntry(
          tracks: _tracks,
          albums: _albums,
          artists: _artists,
          playlists: _playlists,
          topResult: _topResult,
        );

        final merged = LocalSearchEngine.instance.mergeAndRank(
          query: query,
          remote: remoteEntry,
          local: currentLocal,
          userLanguages: _userLanguages,
          userArtists: _userArtists,
        );

        final filtered = (_selectedFilter == 'All')
            ? merged
            : SearchResultEntry(
                tracks: _selectedFilter == 'Songs' ? merged.tracks : const [],
                albums: _selectedFilter == 'Albums' ? merged.albums : const [],
                artists: _selectedFilter == 'Artists' ? merged.artists : const [],
                playlists: _selectedFilter == 'Playlists' ? merged.playlists : const [],
                topResult: (_selectedFilter == 'Songs' && merged.topResult?.type == 'song') ||
                        (_selectedFilter == 'Albums' && merged.topResult?.type == 'album') ||
                        (_selectedFilter == 'Artists' && merged.topResult?.type == 'artist') ||
                        (_selectedFilter == 'Playlists' && merged.topResult?.type == 'playlist')
                    ? merged.topResult
                    : null,
              );

        _topResult = filtered.topResult;
        _tracks = filtered.tracks;
        _albums = filtered.albums;
        _artists = filtered.artists;
        _playlists = filtered.playlists;
        _isRemoteLoading = false;
        _hasCompletedSearch = true;
        notifyListeners();

        unawaited(saveQueryToHistory(query));
      } catch (_) {
        if (requestSeq == _sequence && query == _activeQuery) {
          _isRemoteLoading = false;
          _hasCompletedSearch = true;
          if (_tracks.isEmpty && _albums.isEmpty && _artists.isEmpty) {
            _searchError = 'Couldn\'t load search results.';
          }
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
