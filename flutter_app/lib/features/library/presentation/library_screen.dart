import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/artists/presentation/artist_controller.dart';
import 'package:music_hub_app/features/artists/presentation/artist_views.dart';
import 'package:music_hub_app/features/downloads/presentation/downloads_screen.dart';
import 'package:music_hub_app/features/library/presentation/library_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/utils/item_actions.dart';
import 'package:music_hub_app/shared/widgets/music_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final palette = AppPalette.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 78,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Collections',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              Text(
                'Your saved soundtracks',
                style: TextStyle(
                  fontSize: 12,
                  color: palette.muted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => _createPlaylist(context, ref),
              style: IconButton.styleFrom(
                backgroundColor: palette.navBar,
                foregroundColor: palette.onNavBar,
              ),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicatorColor: palette.ink,
            labelColor: palette.ink,
            unselectedLabelColor: palette.muted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: const [
              Tab(text: 'Songs'),
              Tab(text: 'Playlists'),
              Tab(text: 'Artists'),
              Tab(text: 'Downloads'),
            ],
          ),
        ),
        body: library.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _LibraryError(
            message: error.toString(),
            retry: () => ref.read(libraryControllerProvider.notifier).load(),
          ),
          data: (data) => TabBarView(
            children: [
              _SavedSongs(liked: data.likedSongs, recent: data.recent),
              _Playlists(playlists: data.playlists),
              _Artists(followed: data.artists),
              const DownloadsView(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final description = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      await ref
          .read(libraryControllerProvider.notifier)
          .createPlaylist(name.text.trim(), description.text.trim());
    }
    name.dispose();
    description.dispose();
  }
}

class _SavedSongs extends ConsumerWidget {
  const _SavedSongs({required this.liked, required this.recent});

  final List<MusicItem> liked;
  final List<MusicItem> recent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (liked.isEmpty && recent.isEmpty) {
      return const _Empty(label: 'Like a song to start your library');
    }
    final palette = AppPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 130),
      children: [
        _LibraryHeading(
          icon: Icons.favorite_rounded,
          color: palette.peach,
          title: 'Liked songs',
          count: liked.length,
        ),
        if (liked.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Text(
              'Songs you like will appear here.',
              style: TextStyle(color: palette.muted),
            ),
          )
        else
          for (var index = 0; index < liked.length; index++)
            MusicTile(
              item: liked[index],
              onTap: () => openMusicItem(
                context,
                ref,
                liked[index],
                queue: liked,
                index: index,
                source: 'liked_songs',
              ),
            ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 18),
          _LibraryHeading(
            icon: Icons.history_rounded,
            color: palette.blue,
            title: 'Recently played',
            count: recent.length,
          ),
          for (var index = 0; index < recent.length; index++)
            MusicTile(
              item: recent[index],
              onTap: () => openMusicItem(
                context,
                ref,
                recent[index],
                queue: recent,
                index: index,
                source: 'recently_played',
              ),
            ),
        ],
      ],
    );
  }
}

class _LibraryHeading extends StatelessWidget {
  const _LibraryHeading({
    required this.icon,
    required this.color,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, size: 22, color: AppPalette.of(context).onTile),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(
          '$count tracks',
          style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
        ),
      ],
    ),
  );
}

/// The artist surface: search when the user is typing, recommendations
/// otherwise. The artists already followed lead the recommendation list rather
/// than being a separate static grid.
class _Artists extends ConsumerWidget {
  const _Artists({required this.followed});

  final List<MusicItem> followed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searching = ref.watch(
      artistControllerProvider.select(
        (state) => state.mode == ArtistMode.search,
      ),
    );
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ArtistSearchField(),
        ),
        Expanded(
          child: searching
              ? const ArtistSearchResults()
              : _FollowedThenRecommended(followed: followed),
        ),
      ],
    );
  }
}

/// Followed artists stay pinned at the top so the tab still answers "who do I
/// follow", with discovery continuing below it.
class _FollowedThenRecommended extends StatelessWidget {
  const _FollowedThenRecommended({required this.followed});

  final List<MusicItem> followed;

  @override
  Widget build(BuildContext context) {
    if (followed.isEmpty) return const RecommendedArtistsView();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Your artists',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: followed.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: 104,
                child: ArtistCard(
                  artist: followed[index],
                  variant: index,
                  source: 'library_artists',
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
            child: Text(
              'Recommended for you',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: true,
          child: RecommendedArtistsView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 130),
          ),
        ),
      ],
    );
  }
}

class _Playlists extends StatelessWidget {
  const _Playlists({required this.playlists});

  final List<Map<String, dynamic>> playlists;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return const _Empty(label: 'Create your first playlist');
    }
    final palette = AppPalette.of(context);
    final colors = [palette.peach, palette.blue, palette.lilac, palette.mint];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 130),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors[index % colors.length],
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  // The puck stays white in both themes, so pin the glyph
                  // dark instead of letting it follow the foreground.
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    size: 48,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      playlist['name']?.toString() ?? 'Playlist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(Icons.more_horiz_rounded, size: 18),
                ],
              ),
              Text(
                '${playlist['track_count'] ?? 0} tracks',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: palette.panelHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.library_music_outlined, size: 38),
          ),
          const SizedBox(height: 14),
          Text(label, style: TextStyle(color: palette.muted)),
        ],
      ),
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}
