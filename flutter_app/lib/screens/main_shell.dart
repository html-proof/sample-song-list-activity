import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player_screen.dart';
import 'pulse_screen.dart';
import 'album_details_screen.dart';
import 'artist_profile_screen.dart';
import '../search/search_controller.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(state: state),
      SearchScreen(state: state),
      LibraryScreen(state: state),
      PulseScreen(state: state),
    ];
    return Scaffold(
      body: IndexedStack(index: state.tab, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(state: state, onOpen: () => unawaited(_openPlayer(context, state))),
          NavigationBar(
            selectedIndex: state.tab,
            onDestinationSelected: state.setTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.graphic_eq_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome_rounded),
                label: 'Pulse',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _openPlayer(BuildContext context, AppState state) => openFullPlayer(context, state);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;
  static const _accent = Color(0xFF6C35F2);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCategory = 0; // 0: All, 1: Songs, 2: Artists, 3: Albums, 4: Playlists
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    if (currentScroll >= (maxScroll - 320)) {
      widget.state.loadMoreRecommendations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final sections = state.homeSections;
    final offlinePicks = state.downloads.downloaded
        .map((entry) => entry.track)
        .toList();
    final picks = sections.recommendedForYou.isNotEmpty
        ? sections.recommendedForYou
        : state.recommendations.isNotEmpty
        ? state.recommendations
        : state.trending.isNotEmpty
        ? state.trending
        : offlinePicks;
    if (picks.isEmpty && sections.hero == null && sections.trending.isEmpty) {
      return SafeArea(
        child: RefreshIndicator(
          onRefresh: () => state.refreshHome(force: true),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Music Hub',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 80),
              if (state.loading || state.isHomeRefreshing)
                const Center(child: CircularProgressIndicator())
              else
                Column(
                  children: [
                    const Icon(
                      Icons.music_off_outlined,
                      size: 48,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.error ?? 'Your home feed is empty.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => state.refreshHome(force: true),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }
    final hero = sections.hero ?? picks.first;
    final recent = sections.recentlyPlayed.isNotEmpty
        ? sections.recentlyPlayed
        : (state.recentlyPlayed.isNotEmpty
            ? state.recentlyPlayed
            : picks.take(8).toList());
    final trending = sections.trending.isNotEmpty
        ? sections.trending
        : (state.trending.isNotEmpty ? state.trending : picks);
    final madeForYou = sections.recommendedForYou.isNotEmpty
        ? sections.recommendedForYou
        : (state.recommendations.isNotEmpty
            ? state.recommendations
            : picks);
    final becauseYouListenedTo = sections.becauseYouListenedTo;
    final newReleases = sections.newReleases.isNotEmpty
        ? sections.newReleases
        : picks.reversed.take(3).toList();
    final discoverSomethingNew = sections.discoverSomethingNew;

    // Collect distinct artists
    final allArtists = <Artist>[];
    final seenArtistKeys = <String>{};
    for (final artist in [...sections.favoriteArtists, ...state.onboardingArtists]) {
      if (artist.name.isNotEmpty && seenArtistKeys.add(artist.name.toLowerCase().trim())) {
        allArtists.add(artist);
      }
    }
    for (final track in [...picks, ...trending, ...madeForYou, ...recent, ...becauseYouListenedTo, ...discoverSomethingNew]) {
      final names = track.artist.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final ids = track.artistIds.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      for (var i = 0; i < names.length; i++) {
        final name = names[i];
        if (name.isNotEmpty && seenArtistKeys.add(name.toLowerCase().trim())) {
          final seokey = i < ids.length && ids[i].isNotEmpty ? ids[i] : name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
          final photo = ArtistPhotoResolver.getCached(name) ?? '';
          allArtists.add(Artist(seokey: seokey, name: name, imageUrl: photo));
        }
      }
    }

    // Collect distinct albums grouped by identity/title
    final albumTracksMap = <String, List<Track>>{};
    final albumMap = <String, Album>{};
    for (final album in sections.albums) {
      if (album.title.isNotEmpty) {
        albumMap[album.title.toLowerCase().trim()] = album;
      }
    }
    for (final track in [...picks, ...trending, ...madeForYou, ...recent, ...newReleases]) {
      if (track.album.isNotEmpty) {
        final albumKey = track.album.toLowerCase().trim();
        final albumId = track.albumSeokey.isNotEmpty
            ? track.albumSeokey
            : (track.albumId.isNotEmpty ? track.albumId : track.album.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'));
        final trackList = albumTracksMap.putIfAbsent(albumKey, () => []);
        if (!trackList.any((t) => t.id == track.id || t.title.toLowerCase().trim() == track.title.toLowerCase().trim())) {
          trackList.add(track);
        }
        albumMap.putIfAbsent(
          albumKey,
          () => Album(
            id: albumId,
            seokey: albumId,
            title: track.album,
            artist: track.artist,
            artistIds: track.artistIds
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            imageUrl: track.imageUrl,
            trackCount: 1,
            tracks: [track],
          ),
        );
      }
    }
    final allAlbums = albumMap.entries.map((e) {
      final alb = e.value;
      final trks = albumTracksMap[e.key] ?? alb.tracks;
      return alb.copyWith(trackCount: trks.length, tracks: trks);
    }).toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => state.refreshHome(force: true),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 34),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Music Hub',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => state.refreshHome(force: true),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
                GestureDetector(
                  onTap: () => state.setTab(3),
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: HomeScreen._accent,
                    child: CircleAvatar(
                      radius: 18.5,
                      backgroundColor: AppColors.warm,
                      backgroundImage: state.auth.user?.photoURL == null
                          ? null
                          : NetworkImage(state.auth.user!.photoURL!),
                      child: state.auth.user?.photoURL == null
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.error!,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            _SearchShortcut(onTap: () => state.setTab(1)),
            const SizedBox(height: 14),
            _HomeCategories(
              selected: _selectedCategory,
              onTap: (index) => setState(() => _selectedCategory = index),
            ),
            const SizedBox(height: 16),

            // Category 0: ALL
            if (_selectedCategory == 0) ...[
              _FeaturedBanner(
                track: hero,
                onTap: () async {
                  await state.play(hero, picks);
                  if (context.mounted) _openPlayer(context, state);
                },
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(title: 'Recently Played', onTap: () => state.setTab(2)),
                const SizedBox(height: 10),
                _AlbumStrip(tracks: recent, onPlay: (track) => state.play(track, recent)),
              ],
              const SizedBox(height: 22),
              _HomeSectionHeader(title: 'Recommended for You', onTap: () => state.setTab(3)),
              const SizedBox(height: 10),
              _MixStrip(tracks: madeForYou, onPlay: (track) => state.play(track, madeForYou)),
              if (becauseYouListenedTo.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(title: 'Because You Listened To...', onTap: () => state.setTab(3)),
                const SizedBox(height: 10),
                _MixStrip(tracks: becauseYouListenedTo, onPlay: (track) => state.play(track, becauseYouListenedTo)),
              ],
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final first = _CompactTrackSection(
                    title: 'Trending Now',
                    tracks: trending.take(3).toList(),
                    queue: trending,
                    state: state,
                  );
                  final second = _CompactTrackSection(
                    title: 'New Releases',
                    tracks: newReleases.take(3).toList(),
                    queue: newReleases,
                    state: state,
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(children: [first, const SizedBox(height: 18), second]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: first), const SizedBox(width: 24), Expanded(child: second)],
                  );
                },
              ),
              if (discoverSomethingNew.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(title: 'Discover Something New', onTap: () => state.setTab(3)),
                const SizedBox(height: 10),
                _AlbumStrip(tracks: discoverSomethingNew, onPlay: (track) => state.play(track, discoverSomethingNew)),
              ],
              if (allAlbums.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(
                  title: 'Popular & New Albums',
                  onTap: () => setState(() => _selectedCategory = 3),
                ),
                const SizedBox(height: 12),
                _AlbumCarousel(albums: allAlbums.take(10).toList(), state: state),
              ],
              if (allArtists.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(title: 'Popular Artists', onTap: () => setState(() => _selectedCategory = 2)),
                const SizedBox(height: 12),
                _ArtistStrip(artists: allArtists.take(10).toList(), state: state),
              ],
              if (state.collections.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(title: 'Top Playlists', onTap: () => state.setTab(2)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 185,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: state.collections.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, index) => SizedBox(
                      width: 145,
                      child: CollectionCard(
                        item: state.collections[index],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlaylistScreen(
                              state: state,
                              collection: state.collections[index],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (state.isHomeLoadingMore) ...[
                const SizedBox(height: 24),
                const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
            ]
            // Category 1: SONGS ONLY
            else if (_selectedCategory == 1) ...[
              _FeaturedBanner(
                track: hero,
                onTap: () async {
                  await state.play(hero, picks);
                  if (context.mounted) _openPlayer(context, state);
                },
              ),
              const SizedBox(height: 22),
              _HomeSectionHeader(
                title: 'Trending Songs',
                onTap: () {},
                showSeeAll: false,
              ),
              const SizedBox(height: 10),
              ...trending.map((track) => _buildTrackTile(context, state, track, trending)),
              const SizedBox(height: 22),
              _HomeSectionHeader(
                title: 'Recommended Songs',
                onTap: () {},
                showSeeAll: false,
              ),
              const SizedBox(height: 10),
              ...madeForYou.map((track) => _buildTrackTile(context, state, track, madeForYou)),
              if (becauseYouListenedTo.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(
                  title: 'Because You Listened To...',
                  onTap: () {},
                  showSeeAll: false,
                ),
                const SizedBox(height: 10),
                ...becauseYouListenedTo.map((track) => _buildTrackTile(context, state, track, becauseYouListenedTo)),
              ],
              const SizedBox(height: 22),
              _HomeSectionHeader(
                title: 'New Releases',
                onTap: () {},
                showSeeAll: false,
              ),
              const SizedBox(height: 10),
              ...newReleases.map((track) => _buildTrackTile(context, state, track, newReleases)),
              if (discoverSomethingNew.isNotEmpty) ...[
                const SizedBox(height: 22),
                _HomeSectionHeader(
                  title: 'Discover Something New',
                  onTap: () {},
                  showSeeAll: false,
                ),
                const SizedBox(height: 10),
                ...discoverSomethingNew.map((track) => _buildTrackTile(context, state, track, discoverSomethingNew)),
              ],
              if (state.isHomeLoadingMore) ...[
                const SizedBox(height: 24),
                const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
            ]
            // Category 2: ARTISTS ONLY
            else if (_selectedCategory == 2) ...[
              _HomeSectionHeader(
                title: 'Popular Artists',
                onTap: () {},
                showSeeAll: false,
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allArtists.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.78,
                ),
                itemBuilder: (context, index) {
                  final artist = allArtists[index];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistProfileScreen(artist: artist, state: state),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: HomeScreen._accent,
                          ),
                          child: SizedBox.square(
                            dimension: 86,
                            child: ClipOval(
                              child: Artwork(
                                url: artist.imageUrl,
                                label: artist.name,
                                radius: 999,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          'Artist',
                          style: TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ]
            // Category 3: ALBUMS ONLY
            else if (_selectedCategory == 3) ...[
              _HomeSectionHeader(
                title: 'Popular & New Albums',
                onTap: () {},
                showSeeAll: false,
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allAlbums.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.78,
                ),
                itemBuilder: (context, index) {
                  final album = allAlbums[index];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AlbumDetailsScreen(
                          state: state,
                          albumId: album.id,
                          preview: album,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox.expand(
                            child: Artwork(
                              url: album.imageUrl,
                              label: album.title,
                              radius: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ]
            // Category 4: PLAYLISTS ONLY
            else if (_selectedCategory == 4) ...[
              _HomeSectionHeader(
                title: 'Featured Playlists & Mixes',
                onTap: () {},
                showSeeAll: false,
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.collections.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.78,
                ),
                itemBuilder: (context, index) {
                  final collection = state.collections[index];
                  return CollectionCard(
                    item: collection,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlaylistScreen(
                          state: state,
                          collection: collection,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrackTile(
    BuildContext context,
    AppState state,
    Track track,
    List<Track> queue,
  ) {
    final isPlaying = state.player.current?.id == track.id && state.player.playing;
    return ListTile(
      key: ValueKey('song-tile-${track.seokey}'),
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: SizedBox.square(
        dimension: 50,
        child: Artwork(url: track.imageUrl, label: track.title, radius: 10),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: isPlaying ? HomeScreen._accent : null,
        ),
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DownloadIndicator(track: track, state: state),
          IconButton(
            onPressed: () {
              if (isPlaying) {
                state.player.toggle();
              } else {
                state.play(track, queue);
              }
            },
            icon: Icon(
              isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              color: HomeScreen._accent,
              size: 32,
            ),
          ),
        ],
      ),
      onTap: () async {
        await state.play(track, queue);
        if (context.mounted) _openPlayer(context, state);
      },
    );
  }
}

class _SearchShortcut extends StatelessWidget {
  const _SearchShortcut({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 2,
    shadowColor: Colors.black12,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: AppColors.muted),
            SizedBox(width: 12),
            Expanded(child: Text('Search songs, artists, albums, playlists...', style: TextStyle(color: AppColors.muted))),
            Icon(Icons.tune_rounded, color: HomeScreen._accent),
          ],
        ),
      ),
    ),
  );
}

class _HomeCategories extends StatelessWidget {
  const _HomeCategories({
    required this.selected,
    required this.onTap,
  });
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(width: 9),
      itemBuilder: (_, index) {
        const labels = ['All', 'Songs', 'Artists', 'Albums', 'Playlists'];
        final isSelected = selected == index;
        return ActionChip(
          onPressed: () => onTap(index),
          label: Text(labels[index]),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : null,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor: isSelected
              ? HomeScreen._accent
              : Theme.of(context).colorScheme.surface,
          side: BorderSide(
            color: isSelected
                ? HomeScreen._accent
                : Theme.of(context).dividerColor,
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        );
      },
    ),
  );
}

class _FeaturedBanner extends StatelessWidget {
  const _FeaturedBanner({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(url: track.imageUrl, label: track.title, radius: 22),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xED17103D), Color(0xA32C1262), Color(0x16000000)],
                stops: [0, .52, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFB653EE), borderRadius: BorderRadius.circular(12)),
                  child: const Text('FEATURED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
                const Spacer(),
                Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 28, height: .98, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_arrow_rounded, color: HomeScreen._accent, size: 20), SizedBox(width: 5), Text('Play Now', style: TextStyle(color: Color(0xFF141027), fontWeight: FontWeight.w800))]),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    required this.onTap,
    this.showSeeAll = true,
  });
  final String title;
  final VoidCallback onTap;
  final bool showSeeAll;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
      if (showSeeAll)
        TextButton(
          onPressed: onTap,
          child: const Text('See All', style: TextStyle(color: HomeScreen._accent)),
        ),
    ],
  );
}

class _AlbumStrip extends StatelessWidget {
  const _AlbumStrip({required this.tracks, required this.onPlay});
  final List<Track> tracks;
  final ValueChanged<Track> onPlay;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 162,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: tracks.take(10).length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, index) {
        final track = tracks[index];
        return GestureDetector(
          onTap: () => onPlay(track),
          child: SizedBox(
            width: 116,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(alignment: Alignment.bottomRight, children: [
                SizedBox.square(dimension: 116, child: Artwork(url: track.imageUrl, label: track.title, radius: 14)),
                const Padding(padding: EdgeInsets.all(7), child: CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.play_arrow_rounded, color: HomeScreen._accent, size: 19))),
              ]),
              const SizedBox(height: 6),
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
        );
      },
    ),
  );
}

class _MixStrip extends StatelessWidget {
  const _MixStrip({required this.tracks, required this.onPlay});
  final List<Track> tracks;
  final ValueChanged<Track> onPlay;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: tracks.take(8).length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, index) {
        final track = tracks[index];
        const labels = ['Daily Mix', 'Chill Vibes', 'Energy Boost', 'Discover Weekly'];
        return GestureDetector(
          onTap: () => onPlay(track),
          child: SizedBox(
            width: 180,
            child: Stack(fit: StackFit.expand, children: [
              Artwork(url: track.imageUrl, label: track.title, radius: 18),
              Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xD916103B)]))),
              Positioned(left: 14, right: 12, bottom: 13, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(labels[index % labels.length], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
            ]),
          ),
        );
      },
    ),
  );
}

class _CompactTrackSection extends StatelessWidget {
  const _CompactTrackSection({required this.title, required this.tracks, required this.queue, required this.state});
  final String title;
  final List<Track> tracks, queue;
  final AppState state;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _HomeSectionHeader(title: title, onTap: () => state.setTab(1)),
      ...tracks.map((track) => ListTile(
        key: ValueKey('home-${track.seokey}'),
        onTap: () => state.play(track, queue),
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: SizedBox.square(dimension: 46, child: Artwork(url: track.imageUrl, label: track.title, radius: 8)),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const CircleAvatar(radius: 17, backgroundColor: Colors.white, child: Icon(Icons.play_arrow_rounded, color: HomeScreen._accent, size: 19)),
      )),
    ],
  );
}

class _ArtistStrip extends StatelessWidget {
  const _ArtistStrip({required this.artists, required this.state});
  final List<Artist> artists;
  final AppState state;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: artists.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final artist = artists[index];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistProfileScreen(artist: artist, state: state),
            ),
          ),
          child: SizedBox(
            width: 80,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: HomeScreen._accent),
                child: SizedBox.square(
                  dimension: 70,
                  child: ClipOval(
                    child: Artwork(url: artist.imageUrl, label: artist.name, radius: 999),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      },
    ),
  );
}

class _AlbumCarousel extends StatelessWidget {
  const _AlbumCarousel({required this.albums, required this.state});
  final List<Album> albums;
  final AppState state;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: albums.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (context, index) {
        final album = albums[index];
        final albumId = album.id.isNotEmpty
            ? album.id
            : (album.seokey.isNotEmpty ? album.seokey : album.title);
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AlbumDetailsScreen(
                state: state,
                albumId: albumId,
                preview: album,
              ),
            ),
          ),
          child: SizedBox(
            width: 125,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 125,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Artwork(
                        url: album.imageUrl,
                        label: album.title,
                        radius: 16,
                      ),
                      const Padding(
                        padding: EdgeInsets.all(6),
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.album_rounded,
                            color: HomeScreen._accent,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});
  final AppState state;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final controller = TextEditingController();
  late final MusicSearchController _search;

  @override
  void initState() {
    super.initState();
    _search = MusicSearchController(state: widget.state);
  }

  @override
  void dispose() {
    _search.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListenableBuilder(
      listenable: _search,
      builder: (context, _) {
        final topResult = _search.topResult;
        final tracks = _search.tracks;
        final albums = _search.albums;
        final artists = _search.artists;
        final playlists = _search.playlists;
        final recentSearches = _search.recentSearches;
        final selectedFilter = _search.selectedFilter;
        final searchError = _search.searchError;
        final apiLoading = _search.isRemoteLoading;
        final hasCompletedSearch = _search.hasCompletedSearch;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            Text('Search', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              autofocus: false,
              onChanged: _search.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Songs, artists, albums',
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          controller.clear();
                          _search.search('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            if (controller.text.isNotEmpty) ...[
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Songs', 'Artists', 'Albums', 'Playlists']
                      .map(
                        (filter) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(filter),
                            selected: selectedFilter == filter,
                            onSelected: (_) => _search.setFilter(filter),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            if (apiLoading)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (!apiLoading && controller.text.isEmpty) ...[
              const SizedBox(height: 20),
              if (recentSearches.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SectionTitle('Recent searches'),
                    TextButton(
                      onPressed: _search.clearAllSearchHistory,
                      child: const Text(
                        'Clear all',
                        style: TextStyle(
                          color: AppColors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...recentSearches.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final query = '${item['query'] ?? ''}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_rounded, color: AppColors.muted),
                    title: Text(query, style: const TextStyle(fontSize: 15)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                      onPressed: () => _search.deleteRecentSearchItem(idx),
                    ),
                    onTap: () {
                      controller.text = query;
                      _search.search(query);
                    },
                  );
                }),
              ] else ...[
                const SizedBox(height: 60),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 52,
                        color: AppColors.muted.withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Search songs, artists, albums, or playlists',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (searchError != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    children: [
                      Text(searchError),
                      TextButton(
                        onPressed: () => _search.search(controller.text),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            if (topResult != null && (selectedFilter == 'All')) ...[
              const SizedBox(height: 18),
              const SectionTitle('Top result'),
              const SizedBox(height: 6),
              if (topResult.type == 'song' && topResult.track != null)
                Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 2,
                  child: InkWell(
                    onTap: () => widget.state.play(
                      topResult.track!,
                      tracks.isNotEmpty ? tracks : [topResult.track!],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 72,
                            child: Artwork(
                              url: topResult.track!.imageUrl,
                              label: topResult.track!.title,
                              radius: 14,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  topResult.track!.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  topResult.track!.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.hubColors.textMuted, fontSize: 13),
                                ),
                                if (topResult.track!.album.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    topResult.track!.album,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: context.hubColors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.orange,
                            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (topResult.type == 'album' && topResult.album != null)
                Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 2,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AlbumDetailsScreen(
                          state: widget.state,
                          albumId: topResult.album!.id.isNotEmpty
                              ? topResult.album!.id
                              : (topResult.album!.seokey.isNotEmpty
                                  ? topResult.album!.seokey
                                  : topResult.album!.title),
                          preview: topResult.album!,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 72,
                            child: Artwork(
                              url: topResult.album!.imageUrl,
                              label: topResult.album!.title,
                              radius: 14,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  topResult.album!.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  topResult.album!.artist.isNotEmpty ? topResult.album!.artist : 'Album',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.hubColors.textMuted, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Album${topResult.album!.trackCount > 0 ? ' • ${topResult.album!.trackCount} songs' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.hubColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                )
              else if (topResult.type == 'artist' && topResult.artist != null)
                Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 2,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistProfileScreen(
                          artist: topResult.artist,
                          state: widget.state,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 72,
                            child: Artwork(
                              url: topResult.artist!.imageUrl,
                              label: topResult.artist!.name,
                              radius: 36,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  topResult.artist!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.hubColors.textMuted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
            if (tracks.isNotEmpty && (selectedFilter == 'All' || selectedFilter == 'Songs')) ...[
              const SizedBox(height: 20),
              const SectionTitle('Songs'),
              ...tracks.map(
                (track) => TrackTile(
                  key: ValueKey('search_track_${track.id}'),
                  track: track,
                  state: widget.state,
                  queue: tracks,
                ),
              ),
            ],
            if (artists.isNotEmpty && (selectedFilter == 'All' || selectedFilter == 'Artists')) ...[
              const SizedBox(height: 24),
              const SectionTitle('Artists'),
              SizedBox(
                height: 105,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: artists.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final artist = artists[i];
                    return SizedBox(
                      key: ValueKey('search_artist_${artist.id}'),
                      width: 76,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(38),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArtistProfileScreen(
                              artist: artist,
                              state: widget.state,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            SizedBox.square(
                              dimension: 68,
                              child: Artwork(
                                url: artist.imageUrl,
                                label: artist.name,
                                radius: 34,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              artist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (albums.isNotEmpty && (selectedFilter == 'All' || selectedFilter == 'Albums')) ...[
              const SizedBox(height: 20),
              const SectionTitle('Albums'),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: albums.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final album = albums[i];
                    final albumId = album.id.isNotEmpty
                        ? album.id
                        : (album.seokey.isNotEmpty ? album.seokey : album.title);
                    return SizedBox(
                      key: ValueKey('search_album_${album.id}'),
                      width: 112,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailsScreen(
                              state: widget.state,
                              albumId: albumId,
                              preview: album,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox.square(
                              dimension: 108,
                              child: Artwork(
                                url: album.imageUrl,
                                label: album.title,
                                radius: 20,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              album.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (playlists.isNotEmpty && (selectedFilter == 'All' || selectedFilter == 'Playlists')) ...[
              const SizedBox(height: 20),
              const SectionTitle('Playlists'),
              ...playlists.map(
                (item) => ListTile(
                  key: ValueKey('search_playlist_${item['seokey'] ?? item['id'] ?? item['name'] ?? ''}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Artwork(
                    url: '${item['image_url'] ?? ''}',
                    label: '${item['name'] ?? ''}',
                    radius: 8,
                  ),
                  title: Text(
                    '${item['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Playlist'),
                ),
              ),
            ],
            if (hasCompletedSearch &&
                !apiLoading &&
                controller.text.trim().isNotEmpty &&
                topResult == null &&
                tracks.isEmpty &&
                artists.isEmpty &&
                albums.isEmpty &&
                playlists.isEmpty &&
                searchError == null)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: AppColors.muted.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No results found for "${controller.text.trim()}".',
                        style: const TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Collections',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => _createPlaylist(context),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          state.libraryFilter == 1
              ? '${state.favorites.length} favorite songs'
              : state.libraryFilter == 2
                  ? '${state.downloads.downloaded.length} offline tracks'
                  : '${state.userPlaylists.length + state.collections.length} playlists  ·  ${state.favorites.length} saved tracks  ·  ${state.downloads.downloaded.length} offline',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          children: ['All', 'Favorites', 'Downloaded']
              .asMap()
              .entries
              .map(
                (item) => ChoiceChip(
                  label: Text(item.value),
                  selected: state.libraryFilter == item.key,
                  onSelected: (_) => state.setLibraryFilter(item.key),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        if (state.libraryFilter == 1) ...[
          if (state.favorites.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No favorite songs added yet.\nTap the heart icon on any song to save it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else ...[
            SectionTitle('Favorites', action: '${state.favorites.length} songs'),
            ...state.favorites.map(
              (track) => TrackTile(
                track: track,
                state: state,
                queue: state.favorites,
              ),
            ),
          ],
        ],
        if (state.libraryFilter == 2) ...[
          if (state.downloads.downloaded.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No downloaded music yet.\nTap the download icon on any song to listen offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else ...[
            SectionTitle('Downloaded', action: '${state.downloads.downloaded.length} songs'),
            ...state.downloads.downloaded.map(
              (entry) => TrackTile(
                track: entry.track,
                state: state,
                queue: state.downloads.downloaded.map((e) => e.track).toList(),
                showDelete: true,
              ),
            ),
          ],
        ],
        if (state.libraryFilter == 0) ...[
          if (state.userPlaylists.isNotEmpty) ...[
            const SectionTitle('Your playlists'),
            ...state.userPlaylists.map(
              (playlist) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.orange,
                  child: Icon(Icons.queue_music_rounded, color: Colors.white),
                ),
                title: Text('${playlist['name'] ?? ''}'),
                subtitle: Text('${playlist['track_count'] ?? 0} songs'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (state.collections.isNotEmpty) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.collections.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: .82,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (_, index) => CollectionCard(
                item: state.collections[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistScreen(
                      state: state,
                      collection: state.collections[index],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (state.favorites.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionTitle('Favorites', action: '${state.favorites.length} songs'),
            ...state.favorites.map(
              (track) => TrackTile(track: track, state: state, queue: state.favorites),
            ),
          ],
          if (state.downloads.downloaded.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionTitle('Downloaded', action: '${state.downloads.downloaded.length} songs'),
            ...state.downloads.downloaded.map(
              (entry) => TrackTile(
                track: entry.track,
                state: state,
                queue: state.downloads.downloaded.map((e) => e.track).toList(),
                showDelete: true,
              ),
            ),
          ],
        ],
      ],
    ),
  );

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) await state.createPlaylist(name);
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final user = state.auth.user;
    final artists = (state.profile['favorite_artists'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    final genres = (state.profile['favorite_genres'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Profile',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: AppColors.warm,
                backgroundImage: user?.photoURL == null
                    ? null
                    : NetworkImage(user!.photoURL!),
                child: user?.photoURL == null
                    ? const Icon(Icons.person, size: 38)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Guest listener',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      user?.email ?? 'Sign in to sync your sound',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (user == null)
                FilledButton(
                  onPressed: state.auth.signInWithGoogle,
                  child: const Text('Sign in'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.warm,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(value: '${state.favorites.length}', label: 'Favorites'),
                _Stat(value: '${artists.length}', label: 'Artists'),
                _Stat(
                  value: '${state.recommendations.length}',
                  label: 'For you',
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const SectionTitle('Favorite artists'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: artists.map((name) => Chip(label: Text(name))).toList(),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Favorite genres'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genres.map((name) => Chip(label: Text(name))).toList(),
          ),
          const SizedBox(height: 30),
          if (user != null)
            OutlinedButton.icon(
              onPressed: state.auth.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ],
  );
}

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.state,
    required this.collection,
  });
  final AppState state;
  final CollectionItem collection;
  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final Future<List<Track>> future = _loadTracks();

  Future<List<Track>> _loadTracks() async {
    try {
      return await widget.state.api.playlist(widget.collection.seokey);
    } catch (_) {
      final local = widget.state.downloads.downloaded
          .map((e) => e.track)
          .where((track) => track.albumSeokey == widget.collection.seokey)
          .toList();
      if (local.isEmpty) rethrow;
      return local;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.ink,
    appBar: AppBar(
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          onPressed: () async {
            final tracks = await future;
            await widget.state.downloadTracks(tracks);
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Download playlist',
        ),
        IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)),
      ],
    ),
    body: SafeArea(
      top: false,
      child: FutureBuilder<List<Track>>(
        future: future,
        builder: (_, snapshot) {
          final tracks = snapshot.data ?? const <Track>[];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.blush,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'SELECTED FOR YOU',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.collection.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 210,
                        child: Artwork(
                          url: widget.collection.imageUrl,
                          label: widget.collection.title,
                          radius: 28,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            '${tracks.length} soundtracks',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          CircleAvatar(
                            backgroundColor: AppColors.ink,
                            child: IconButton(
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () =>
                                        widget.state.playWithShuffle(tracks),
                              color: Colors.white,
                              icon: const Icon(Icons.shuffle),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : snapshot.hasError
                      ? Center(child: Text('${snapshot.error}'))
                      : ListView(
                          children: tracks
                              .map(
                                (track) => TrackTile(
                                  track: track,
                                  state: widget.state,
                                  queue: tracks,
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    bottomNavigationBar: widget.state.player.current == null
        ? null
        : SafeArea(
            top: false,
            child: MiniPlayer(
              state: widget.state,
              onOpen: () => unawaited(openFullPlayer(context, widget.state)),
            ),
          ),
  );
}
