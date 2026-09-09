import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'offline.dart';
import 'services.dart';
import 'cache/audio_cache.dart';
import 'search/search_engine.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.auth,
    required this.api,
    required this.player,
    required this.downloads,
    this.audioCache,
  }) {
    player.resolveTrack = api.resolvePlayableTrack;
    player.loadRelatedTracks = (track) async {
      try {
        if (auth.isSignedIn) {
          final recs = await api.recommendations(limit: 10);
          if (recs.isNotEmpty) return recs;
        }
      } catch (_) {}
      try {
        if (track.artist.isNotEmpty) {
          final tracks = await api.searchTracks(track.artist, limit: 10);
          if (tracks.isNotEmpty) return tracks;
        }
      } catch (_) {}
      try {
        final lang = track.language.isNotEmpty ? track.language : 'hindi';
        final trend = await api.trending(language: lang, limit: 10);
        if (trend.isNotEmpty) return trend;
      } catch (_) {}
      return <Track>[];
    };
    downloads.resolveTrack = api.resolvePlayableTrack;
    auth.addListener(_onAuthChanged);
    player.addListener(_onPlayerStateChanged);
    downloads.addListener(notifyListeners);
  }
  final AuthService auth;
  final MusicApi api;
  final PlayerController player;
  final DownloadManager downloads;
  final AudioCache? audioCache;
  String? _lastPreloadedTrackId;

  void _onPlayerStateChanged() {
    notifyListeners();
    final cur = player.current;
    if (cur != null && cur.id != _lastPreloadedTrackId) {
      _lastPreloadedTrackId = cur.id;
      api.preloadLyrics(cur.seokey, title: cur.title, artist: cur.artist);
    }
  }
  int tab = 0;
  bool loading = false;
  String? error;
  List<Track> trending = [],
      recommendations = [],
      favorites = [],
      recentlyPlayed = [];
  List<Map<String, dynamic>> userPlaylists = [], languages = [];
  List<CollectionItem> collections = [];
  List<Artist> onboardingArtists = [];
  String? onboardingArtistsCursor;
  bool onboardingArtistsHasMore = false;
  bool onboardingArtistsLoading = false;
  Map<String, dynamic> profile = {
    'languages': <String>[],
    'language_ids': <String>[],
    'favorite_genres': <String>[],
    'favorite_artists': <String>[],
  };
  final Set<String> selectedArtists = {}, selectedLanguages = {};
  String? _lastUserId;
  bool onboardingCompleted = false;
  int libraryFilter = 0;

  final RecommendationEngine recommendationEngine = RecommendationEngine();
  HomeFeedSections get homeSections => recommendationEngine.currentSections;
  bool get isHomeRefreshing => recommendationEngine.isRefreshing;
  bool get isHomeLoadingMore => recommendationEngine.isLoadingMore;
  DateTime? _lastHomeRefreshTime;

  void setLibraryFilter(int value) {
    libraryFilter = value;
    notifyListeners();
  }

  Future<void> restoreLocal() async {
    _lastUserId = auth.user?.uid;
    player.authUserId = _lastUserId ?? 'guest';
    await audioCache?.initialize();
    await downloads.initialize(_lastUserId);
    final local = await SharedPreferences.getInstance();
    tab = 0;
    onboardingCompleted = local.getBool('onboarding_completed') ?? false;

    // Restore dedicated language and artist preferences
    final savedLangIds = local.getStringList('saved_language_ids');
    if (savedLangIds != null && savedLangIds.isNotEmpty) {
      selectedLanguages.addAll(savedLangIds);
    }
    final savedArtistIds = local.getStringList('saved_artist_ids');
    if (savedArtistIds != null && savedArtistIds.isNotEmpty) {
      selectedArtists.addAll(savedArtistIds);
    }

    final profileJson = local.getString('cached_profile');
    if (profileJson != null) {
      try {
        profile = Map<String, dynamic>.from(jsonDecode(profileJson) as Map);
      } catch (_) {}
    }

    // Keep profile aligned with saved preferences
    if (selectedLanguages.isNotEmpty) {
      profile['language_ids'] = selectedLanguages.toList();
      final savedLangNames = local.getStringList('saved_language_names');
      if (savedLangNames != null && savedLangNames.isNotEmpty) {
        profile['languages'] = savedLangNames;
      }
    }
    if (selectedArtists.isNotEmpty) {
      profile['favorite_artist_ids'] = selectedArtists.toList();
      final savedArtistNames = local.getStringList('saved_artist_names');
      if (savedArtistNames != null && savedArtistNames.isNotEmpty) {
        profile['favorite_artists'] = savedArtistNames;
      }
    }

    final savedGoogleId = local.getString('saved_google_id');
    if (savedGoogleId != null && savedGoogleId.isNotEmpty) {
      profile['google_id'] = savedGoogleId;
    }
    if (auth.user?.uid != null) {
      profile['google_id'] = auth.user!.uid;
      await local.setString('saved_google_id', auth.user!.uid);
      if (auth.user?.email != null) {
        await local.setString('saved_user_email', auth.user!.email!);
      }
    }

    // If user has saved languages and artists, consider onboarding completed
    if (selectedLanguages.isNotEmpty && selectedArtists.isNotEmpty) {
      onboardingCompleted = true;
      await local.setBool('onboarding_completed', true);
    }

    final cached = await api.cachedHome();
    if (cached != null) _applyHome(cached);
    final playerJson = local.getString('player_state');
    if (playerJson != null) {
      try {
        final data = jsonDecode(playerJson) as Map;
        final trackData = data['track'];
        if (trackData is Map) {
          final track = Track.fromJson(Map<String, dynamic>.from(trackData));
          final savedQueue = Track.list(data['queue']);
          final posMs = (data['position_ms'] as num?)?.toInt() ?? 0;
          final wasPlaying = data['was_playing'] == true;
          final repeatStr = data['repeat_mode'] as String?;
          final repeat = PlaybackRepeatMode.values.firstWhere(
            (e) => e.name == repeatStr,
            orElse: () => PlaybackRepeatMode.off,
          );
          final isShuffled = data['is_shuffled'] == true;
          final savedIndex = (data['current_index'] as num?)?.toInt();
          unawaited(player.restorePlaybackSession(
            track,
            savedQueue,
            Duration(milliseconds: posMs),
            wasPlaying: wasPlaying,
            repeat: repeat,
            shuffled: isShuffled,
            savedIndex: savedIndex,
          ));
        }
      } catch (_) {}
    }

    final savedFavs = local.getStringList('local_favorites');
    if (savedFavs != null && savedFavs.isNotEmpty) {
      final loaded = <Track>[];
      for (final s in savedFavs) {
        try {
          final t = Track.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
          if (!loaded.any((existing) => _isSameTrack(existing, t))) {
            loaded.add(t);
          }
        } catch (_) {}
      }
      if (loaded.isNotEmpty) {
        favorites = loaded;
      }
    }
    notifyListeners();
  }

  Future<void> persistLocal() async {
    final local = await SharedPreferences.getInstance();
    await local.setBool('onboarding_completed', onboardingCompleted);

    final langIds = (profile['language_ids'] as List? ?? selectedLanguages.toList())
        .map((e) => '$e')
        .toList();
    if (langIds.isNotEmpty) {
      await local.setStringList('saved_language_ids', langIds);
    }
    final langNames = (profile['languages'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    if (langNames.isNotEmpty) {
      await local.setStringList('saved_language_names', langNames);
    }
    final artistIds = (profile['favorite_artist_ids'] as List? ?? selectedArtists.toList())
        .map((e) => '$e')
        .toList();
    if (artistIds.isNotEmpty) {
      await local.setStringList('saved_artist_ids', artistIds);
    }
    final artistNames = (profile['favorite_artists'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    if (artistNames.isNotEmpty) {
      await local.setStringList('saved_artist_names', artistNames);
    }

    final googleId = auth.user?.uid ?? profile['google_id'] as String?;
    if (googleId != null && googleId.isNotEmpty) {
      await local.setString('saved_google_id', googleId);
      profile['google_id'] = googleId;
    }
    if (auth.user?.email != null) {
      await local.setString('saved_user_email', auth.user!.email!);
    }

    await local.setString('cached_profile', jsonEncode(profile));
    await player.persistStateNow();
  }

  void applyProfile(Map<String, dynamic> me) {
    final remoteProfile = Map<String, dynamic>.from(me['profile'] as Map? ?? me);
    profile = {
      ...profile,
      ...remoteProfile,
      if ((remoteProfile['language_ids'] as List? ?? const []).isEmpty &&
          (profile['language_ids'] as List? ?? const []).isNotEmpty)
        'language_ids': profile['language_ids'],
      if ((remoteProfile['languages'] as List? ?? const []).isEmpty &&
          (profile['languages'] as List? ?? const []).isNotEmpty)
        'languages': profile['languages'],
      if ((remoteProfile['favorite_artist_ids'] as List? ?? const []).isEmpty &&
          (profile['favorite_artist_ids'] as List? ?? const []).isNotEmpty)
        'favorite_artist_ids': profile['favorite_artist_ids'],
      if ((remoteProfile['favorite_artists'] as List? ?? const []).isEmpty &&
          (profile['favorite_artists'] as List? ?? const []).isNotEmpty)
        'favorite_artists': profile['favorite_artists'],
    };
    if (auth.user?.uid != null) {
      profile['google_id'] = auth.user!.uid;
    }
    onboardingCompleted = onboardingCompleted ||
        me['onboarding_completed'] == true ||
        profile['onboarding_completed'] == true ||
        ((profile['language_ids'] as List? ?? const []).isNotEmpty &&
            (profile['favorite_artist_ids'] as List? ?? const []).isNotEmpty);
    unawaited(persistLocal());
    notifyListeners();
  }

  Future<void> updateLanguages(List<String> ids, List<String> names) async {
    profile = {
      ...profile,
      'language_ids': ids,
      'languages': names,
    };
    selectedLanguages
      ..clear()
      ..addAll(ids);
    await persistLocal();
    notifyListeners();
  }

  Future<void> bootstrap({bool refresh = false}) async {
    if (refresh && (recommendations.isNotEmpty || trending.isNotEmpty)) {
      await refreshHome();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      if (auth.isSignedIn) await loadPersonalized(refresh: refresh);
      error = null;
    } catch (exception) {
      error = '$exception';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadPersonalized({bool refresh = false}) async {
    if (!auth.isSignedIn) return;
    try {
      await api.ensureAccount();
      final values = await Future.wait([
        api.me(),
        api.favorites(),
        api.userPlaylists(),
        // Preferences are saved immediately before this call in onboarding and
        // settings, so always bypass the short-lived home cache here.
        api.home(refresh: true),
      ]);
      final me = values[0] as Map<String, dynamic>;
      profile = Map<String, dynamic>.from(me['profile'] as Map? ?? const {});
      final remoteFavs = values[1] as List<Track>;
      final combined = <Track>[...remoteFavs, ...favorites];
      final deduped = <Track>[];
      for (final t in combined) {
        if (!deduped.any((existing) => _isSameTrack(existing, t))) {
          deduped.add(t);
        }
      }
      favorites = deduped;
      LocalSearchEngine.instance.indexTracks(favorites);
      unawaited(_persistFavoritesLocal());
      userPlaylists = values[2] as List<Map<String, dynamic>>;
      _applyHome(values[3] as Map<String, dynamic>);
      error = null;
      notifyListeners();
    } catch (_) {
      notifyListeners();
    }
  }

  Future<void> loadLanguages() async {
    languages = await api.languages();
    notifyListeners();
  }

  Future<void> saveLanguages() async {
    final ids = selectedLanguages.toList();
    final names = ids
        .map(
          (id) => languages
              .cast<Map<String, dynamic>?>()
              .firstWhere(
                (item) => '${item?['id'] ?? ''}' == id,
                orElse: () => null,
              )?['name'],
        )
        .whereType<String>()
        .toList();
    profile = {
      ...profile,
      'language_ids': ids,
      'languages': names,
    };
    await persistLocal();
    notifyListeners();
    if (!auth.isSignedIn) return;
    try {
      final response = await api.saveLanguageIds(ids);
      final saved = (response['language_ids'] as List? ?? ids)
          .map((value) => '$value')
          .toList();
      profile['language_ids'] = saved;
      await persistLocal();
    } catch (_) {
      // Keep onboarding usable offline. The selected IDs remain stored on
      // device and can be synced by a later signed-in settings update.
    }
  }

  Future<void> loadOnboardingArtists() async {
    final ids = (profile['language_ids'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    onboardingArtistsCursor = null;
    onboardingArtistsHasMore = false;
    onboardingArtists = [];
    if (ids.isNotEmpty) {
      final result = await api.onboardingArtistPage(ids);
      onboardingArtists = result['items'] as List<Artist>;
      onboardingArtistsCursor = result['next_cursor'] as String?;
      onboardingArtistsHasMore = result['has_more'] == true;
    }
    notifyListeners();
  }

  Future<void> loadMoreOnboardingArtists() async {
    if (onboardingArtistsLoading || !onboardingArtistsHasMore || onboardingArtistsCursor == null) return;
    final ids = (profile['language_ids'] as List? ?? const []).map((e) => '$e').toList();
    onboardingArtistsLoading = true;
    notifyListeners();
    try {
      final result = await api.onboardingArtistPage(ids, cursor: onboardingArtistsCursor);
      onboardingArtists = [...onboardingArtists, ...(result['items'] as List<Artist>)];
      onboardingArtistsCursor = result['next_cursor'] as String?;
      onboardingArtistsHasMore = result['has_more'] == true;
    } finally {
      onboardingArtistsLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveArtistPreferences() async {
    final ids = selectedArtists.toList();
    profile = {
      ...profile,
      'favorite_artist_ids': ids,
      'favorite_artists': onboardingArtists
          .where((artist) => selectedArtists.contains(artist.seokey))
          .map((artist) => artist.name)
          .toList(),
    };
    onboardingCompleted = true;
    await persistLocal();
    if (auth.isSignedIn) {
      try {
        await api.saveArtistIds(ids);
        await loadPersonalized(refresh: true);
      } catch (_) {
        // Local onboarding is complete even when cloud sync is temporarily
        // unavailable. The app can refresh personalization on a later launch.
      }
    }
    notifyListeners();
  }

  Future<void> downloadTrack(Track track) => downloads.enqueue(track);
  Future<void> downloadTracks(Iterable<Track> tracks) => downloads.enqueueAll(tracks);
  Future<void> removeDownload(String id) => downloads.remove(id);
  Future<void> deleteDownloadedTrack(Track track) async {
    if (track.seokey.isNotEmpty) await downloads.remove(track.seokey);
    if (track.id.isNotEmpty) await downloads.remove(track.id);
    if (track.trackId.isNotEmpty) await downloads.remove(track.trackId);
    notifyListeners();
  }

  void toggleLanguage(String id) {
    selectedLanguages.contains(id)
        ? selectedLanguages.remove(id)
        : selectedLanguages.add(id);
    notifyListeners();
  }

  void toggleArtist(String id) {
    selectedArtists.contains(id)
        ? selectedArtists.remove(id)
        : selectedArtists.add(id);
    notifyListeners();
  }

  List<Track> _filterExplicit(List<Track> list) {
    if (profile['explicit_content_enabled'] == true) return list;
    return list.where((track) => !track.isExplicit).toList();
  }

  void _applyHome(Map<String, dynamic> data) {
    var rawRecs = <Track>[];
    var rawTrending = <Track>[];
    var rawRecent = <Track>[];
    var rawReleases = <Track>[];
    var rawAlbums = <Album>[];
    var rawArtists = <Artist>[];
    var rawPlaylists = <CollectionItem>[];

    for (final raw in data['sections'] as List? ?? const []) {
      if (raw is! Map) continue;
      final section = Map<String, dynamic>.from(raw);
      final id = section['id'] as String? ?? '';
      final items = section['items'];

      if (id == 'recently_played') {
        rawRecent = _filterExplicit(Track.list(items));
      } else if (id == 'made_for_you' || id == 'recommended') {
        rawRecs = _filterExplicit(Track.list(items));
      } else if (id == 'trending') {
        rawTrending = _filterExplicit(Track.list(items));
      } else if (id == 'new_releases') {
        rawReleases = _filterExplicit(Track.list(items));
        rawAlbums.addAll(Album.list(items));
      } else if (id == 'saved_albums') {
        rawAlbums.addAll(Album.list(items));
      } else if (id == 'followed_artists') {
        rawArtists.addAll(Artist.list(items));
      } else if (id == 'your_playlists') {
        // Playlists
      }
    }

    // Compose rich, diverse, cross-deduplicated sections
    final composed = recommendationEngine.composeSections(
      rawRecommendations: rawRecs,
      rawTrending: rawTrending,
      rawRecent: rawRecent.isNotEmpty ? rawRecent : recentlyPlayed,
      rawNewReleases: rawReleases,
      rawAlbums: rawAlbums,
      rawArtists: rawArtists,
      rawPlaylists: rawPlaylists,
      isNewUser: favorites.isEmpty && recentlyPlayed.isEmpty,
    );

    recommendationEngine.currentSections = composed;
    recommendations = composed.recommendedForYou;
    trending = composed.trending;
    recentlyPlayed = composed.recentlyPlayed;

    LocalSearchEngine.instance.indexTracks(recentlyPlayed);
    LocalSearchEngine.instance.indexTracks(recommendations);
    LocalSearchEngine.instance.indexTracks(trending);
  }

  /// Pull-to-refresh home feed with a fresh recommendation batch.
  /// Implements stale-while-revalidate (UI stays visible), race condition protection,
  /// and zero playback disruption.
  Future<void> refreshHome({bool force = true, bool silent = false}) async {
    final refreshId = recommendationEngine.session.nextRefreshId();
    recommendationEngine.session.advanceGeneration();
    final gen = recommendationEngine.session.refreshGeneration;
    final sessId = recommendationEngine.session.sessionId;
    final excludes = [
      ...recommendationEngine.freshness.recentlyRecommendedKeys,
      ...recommendationEngine.freshness.currentlyVisibleKeys,
    ];

    if (!silent) {
      recommendationEngine.isRefreshing = true;
      notifyListeners();
    }

    try {
      if (auth.isSignedIn) {
        final homeData = await api.home(
          refresh: true,
          refreshGeneration: gen,
          sessionId: sessId,
          excludeIds: excludes,
          limit: 24,
        );
        if (refreshId != recommendationEngine.session.activeRefreshId) {
          // Discard stale out-of-order response
          return;
        }
        _applyHome(homeData);
      } else {
        await _refreshGuestHome(gen, excludes, refreshId);
      }
      _lastHomeRefreshTime = DateTime.now();
      recommendationEngine.lastRefreshTime = _lastHomeRefreshTime;
      error = null;
    } catch (e) {
      if (recommendations.isEmpty && trending.isEmpty) {
        error = '$e';
      }
    } finally {
      if (refreshId == recommendationEngine.session.activeRefreshId) {
        recommendationEngine.isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshGuestHome(int gen, List<String> excludes, int refreshId) async {
    final langs = (profile['languages'] as List? ?? ['English']).map((e) => '$e').toList();
    final topLang = langs.isNotEmpty ? langs[gen % langs.length] : 'English';
    final artists = (profile['favorite_artists'] as List? ?? const []).map((e) => '$e').toList();
    final seedArtist = artists.isNotEmpty ? artists[gen % artists.length] : '';

    final results = await Future.wait([
      if (seedArtist.isNotEmpty)
        api.searchTracks(seedArtist, limit: 12)
      else
        api.trending(language: topLang, limit: 12),
      api.trending(language: topLang, limit: 12),
      api.favorites(),
    ], eagerError: false);

    if (refreshId != recommendationEngine.session.activeRefreshId) return;

    final recs = _filterExplicit((results[0] as List? ?? const []).whereType<Track>().toList());
    final trend = _filterExplicit((results[1] as List? ?? const []).whereType<Track>().toList());

    final composed = recommendationEngine.composeSections(
      rawRecommendations: recs,
      rawTrending: trend,
      rawRecent: recentlyPlayed,
      isNewUser: true,
    );

    recommendationEngine.currentSections = composed;
    recommendations = composed.recommendedForYou;
    trending = composed.trending;
    recentlyPlayed = composed.recentlyPlayed;
  }

  /// Appends next unique recommendation batch for infinite scroll / pagination
  Future<void> loadMoreRecommendations() async {
    if (recommendationEngine.isLoadingMore || !recommendationEngine.hasMore) return;
    recommendationEngine.isLoadingMore = true;
    notifyListeners();
    try {
      final gen = recommendationEngine.session.refreshGeneration;
      final sessId = recommendationEngine.session.sessionId;
      final excludes = [
        ...recommendationEngine.freshness.recentlyRecommendedKeys,
        ...recommendationEngine.freshness.currentlyVisibleKeys,
      ];
      final newTracks = await api.recommendations(
        limit: 12,
        refreshGeneration: gen,
        sessionId: sessId,
        excludeIds: excludes,
        cursor: recommendationEngine.cursor,
      );
      if (newTracks.isEmpty) {
        recommendationEngine.hasMore = false;
      } else {
        recommendationEngine.appendPage(_filterExplicit(newTracks));
        recommendations = recommendationEngine.currentSections.recommendedForYou;
      }
    } catch (_) {
    } finally {
      recommendationEngine.isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Called when app resumes from background
  void onAppResumed() {
    final now = DateTime.now();
    if (_lastHomeRefreshTime == null ||
        now.difference(_lastHomeRefreshTime!) >= const Duration(minutes: 30)) {
      unawaited(refreshHome(silent: true));
    }
  }

  bool _isSameTrack(Track a, Track b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty && a.id == b.id) return true;
    if (a.seokey.isNotEmpty && b.seokey.isNotEmpty && a.seokey == b.seokey) return true;
    if (a.trackId.isNotEmpty && b.trackId.isNotEmpty && a.trackId == b.trackId) return true;
    if (a.id.isNotEmpty && b.seokey.isNotEmpty && a.id == b.seokey) return true;
    if (a.seokey.isNotEmpty && b.id.isNotEmpty && a.seokey == b.id) return true;
    if (a.title.isNotEmpty &&
        b.title.isNotEmpty &&
        a.title.toLowerCase().trim() == b.title.toLowerCase().trim() &&
        a.artist.toLowerCase().trim() == b.artist.toLowerCase().trim()) {
      return true;
    }
    return false;
  }

  Future<void> _persistFavoritesLocal() async {
    try {
      final local = await SharedPreferences.getInstance();
      final list = favorites.map((t) => jsonEncode(t.toJson())).toList();
      await local.setStringList('local_favorites', list);
    } catch (_) {}
  }

  Future<void> toggleFavorite(Track track) async {
    final exists = isFavorite(track);
    if (exists) {
      favorites.removeWhere((item) => _isSameTrack(item, track));
      notifyListeners();
      unawaited(_persistFavoritesLocal());
      if (auth.isSignedIn) {
        try {
          await api.removeFavorite(track.seokey.isNotEmpty ? track.seokey : (track.trackId.isNotEmpty ? track.trackId : track.id));
        } catch (_) {}
      }
    } else {
      // Deduplicate strictly before inserting to guarantee it only appears once
      favorites.removeWhere((item) => _isSameTrack(item, track));
      favorites.insert(0, track);
      notifyListeners();
      unawaited(_persistFavoritesLocal());
      if (auth.isSignedIn) {
        try {
          await api.addFavorite(track);
        } catch (_) {}
      }
    }
  }

  Future<void> play(Track track, List<Track> queue) async {
    var playable = track;
    if (track.streamUrl.isEmpty) {
      try {
        playable = await api.resolvePlayableTrack(track) ?? track;
      } catch (_) {
        // Keep the original snapshot so offline playback and the normal
        // player error state remain available when catalog lookup fails.
      }
    }
    final resolvedQueue = queue
        .map((item) => (_isSameTrack(item, track) || _isSameTrack(item, playable)) ? playable : item)
        .toList();
    await player.play(playable, fromQueue: resolvedQueue);
    if (auth.isSignedIn) {
      try {
        await api.addHistory(playable);
      } catch (_) {}
    }
  }

  Future<void> playWithShuffle(List<Track> queue, {Track? startTrack}) async {
    await player.playWithShuffle(queue, startTrack: startTrack);
  }

  Future<void> createPlaylist(String name) async {
    if (!auth.isSignedIn) return;
    userPlaylists.insert(0, await api.createPlaylist(name));
    notifyListeners();
  }

  bool isFavorite(Track track) =>
      favorites.any((item) => _isSameTrack(item, track));

  void setTab(int value) {
    tab = value;
    notifyListeners();
  }

  void _onAuthChanged() {
    final userId = auth.user?.uid;
    player.authUserId = userId ?? 'guest';
    final previousUser = _lastUserId;
    _lastUserId = userId;
    if (previousUser != null && userId != null && previousUser != userId) {
      // Only clear playback session when switching between two different signed-in accounts
      unawaited(player.clear());
      unawaited(downloads.setUser(userId));
    }
    if (auth.isSignedIn) loadPersonalized();
    notifyListeners();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    player.removeListener(notifyListeners);
    downloads.removeListener(notifyListeners);
    super.dispose();
  }
}
