import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'now_playing_screen.dart';
import 'collections_screen.dart';
import 'artist_profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.musicApi, required this.auth});

  final MusicApi musicApi;
  final AuthService auth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  Track? _currentTrack;
  bool _isPlaying = false;

  List<Track> _recommendations = [];
  List<Track> _trending = [];
  List<Track> _recentPlays = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.musicApi.profile();
      final langs = (profile['languages'] as List? ?? ['English'])
          .map((e) => '$e')
          .toList();
      final topLang = langs.isNotEmpty ? langs.first : 'English';

      final results = await Future.wait([
        widget.musicApi.recommendations(limit: 20),
        widget.musicApi.trending(language: topLang, limit: 12),
        widget.musicApi.favorites(),
      ], eagerError: false);

      if (mounted) {
        setState(() {
          _recommendations = results[0];
          _trending = results[1];
          _recentPlays = results[2];
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load music. Check your connection.';
        });
      }
    }
  }

  void _playTrack(Track track) {
    setState(() {
      _currentTrack = track;
      _isPlaying = true;
    });
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            NowPlayingScreen(
              track: track,
              isPlaying: _isPlaying,
              onTogglePlay: () => setState(() => _isPlaying = !_isPlaying),
            ),
        transitionsBuilder: (context, anim, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                  ),
              child: child,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentTab,
        children: [
          _HomeTab(
            loading: _loading,
            error: _error,
            onRetry: _load,
            recommendations: _recommendations,
            trending: _trending,
            recentPlays: _recentPlays,
            onPlayTrack: _playTrack,
            onEditTaste: () => Navigator.pushNamed(context, '/preferences'),
          ),
          CollectionsScreen(musicApi: widget.musicApi),
          const ArtistProfileScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentTrack != null)
            MiniPlayer(
              track: _currentTrack!,
              isPlaying: _isPlaying,
              onTogglePlay: () => setState(() => _isPlaying = !_isPlaying),
              onTap: () => _playTrack(_currentTrack!),
            ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.graphic_eq_rounded,
                label: 'Home',
                selected: _currentTab == 0,
                onTap: () => setState(() => _currentTab = 0),
              ),
              _NavItem(
                icon: Icons.search_rounded,
                label: 'Search',
                selected: _currentTab == 1,
                onTap: () => setState(() => _currentTab = 1),
              ),
              _NavItem(
                icon: Icons.library_music_outlined,
                label: 'Media',
                selected: _currentTab == 2,
                onTap: () => setState(() => _currentTab = 2),
              ),
              _NavItem(
                icon: Icons.add_circle_outline_rounded,
                label: 'Create',
                selected: false,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? AppColors.primary : AppColors.muted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Home tab ─────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.recommendations,
    required this.trending,
    required this.recentPlays,
    required this.onPlayTrack,
    required this.onEditTaste,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final List<Track> recommendations;
  final List<Track> trending;
  final List<Track> recentPlays;
  final void Function(Track) onPlayTrack;
  final VoidCallback onEditTaste;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 56,
                color: AppColors.muted,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        if (trending.isNotEmpty)
          SliverToBoxAdapter(child: _buildHeroCard(trending.first)),
        SliverToBoxAdapter(child: _buildPickedForYou()),
        if (recentPlays.isNotEmpty) SliverToBoxAdapter(child: _buildOnRepeat()),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Music Hub',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: AppColors.primary,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, size: 24),
              onPressed: () {},
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  // Hero card: first trending track for the user's top language.
  Widget _buildHeroCard(Track track) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: GestureDetector(
        onTap: () => onPlayTrack(track),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: track.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.imageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _coverPlaceholder(64),
                      )
                    : _coverPlaceholder(64),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trending now',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.artist,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickedForYou() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Picked For You',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onEditTaste,
                child: const Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 15,
                      color: AppColors.secondary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Edit taste',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (recommendations.isEmpty)
          _buildNoRecsPrompt()
        else
          SizedBox(
            height: 190,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: recommendations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final t = recommendations[i];
                return GestureDetector(
                  onTap: () => onPlayTrack(t),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: t.imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: t.imageUrl,
                                width: 144,
                                height: 144,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    _coverPlaceholder(144),
                              )
                            : _coverPlaceholder(144),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 144,
                        child: Text(
                          t.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        t.artist,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildNoRecsPrompt() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: onEditTaste,
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note_rounded, color: AppColors.muted, size: 28),
              SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set your music taste',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Tap to pick languages, artists & genres',
                    style: TextStyle(fontSize: 12, color: AppColors.secondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnRepeat() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 14),
          child: Text(
            'On Repeat',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: -0.3,
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            itemCount: recentPlays.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final t = recentPlays[i];
              return GestureDetector(
                onTap: () => onPlayTrack(t),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: t.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: t.imageUrl,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => _coverPlaceholder(88),
                            )
                          : _coverPlaceholder(88),
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      width: 88,
                      child: Text(
                        t.title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder(double size) => Container(
    width: size,
    height: size,
    color: AppColors.surfaceCard,
    child: const Icon(Icons.music_note_rounded, color: AppColors.muted),
  );
}
