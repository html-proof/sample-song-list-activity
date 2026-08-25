import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/auth/presentation/auth_controller.dart';
import 'package:music_hub_app/features/home/presentation/home_controller.dart';
import 'package:music_hub_app/shared/models/home_feed.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/utils/item_actions.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent * 0.8) {
        ref.read(homeControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeControllerProvider);
    final user = ref.watch(sessionProvider).value;
    final palette = AppPalette.of(context);
    return Scaffold(
      body: RefreshIndicator(
        color: palette.ink,
        onRefresh: () =>
            ref.read(homeControllerProvider.notifier).load(refresh: true),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 86,
              backgroundColor: palette.background.withValues(alpha: 0.96),
              titleSpacing: 18,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(),
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                  const Text(
                    'My Soundwaves',
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.3,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 16),
                  child: Artwork(
                    url: user?.photoUrl,
                    size: 42,
                    radius: 21,
                    round: true,
                  ),
                ),
              ],
            ),
            home.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                child: _HomeError(
                  message: error.toString(),
                  retry: () => ref.read(homeControllerProvider.notifier).load(),
                ),
              ),
              data: (feed) => _HomeContent(feed: feed),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.feed});

  final HomeFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playable = feed.sections
        .expand((section) => section.items)
        .where((item) => item.playable)
        .toList(growable: false);
    final featured = playable.isEmpty ? null : playable.first;
    return SliverList.builder(
      itemCount: feed.sections.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return featured == null
              ? const SizedBox.shrink()
              : _FeaturedCard(
                  item: featured,
                  onTap: () => openMusicItem(
                    context,
                    ref,
                    featured,
                    source: 'home_featured',
                  ),
                );
        }
        final sectionIndex = index - 1;
        if (sectionIndex == feed.sections.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
            child: Center(
              child: feed.nextCursor == null
                  ? Text(
                      'Made for your next listen',
                      style: TextStyle(color: AppPalette.of(context).muted),
                    )
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return _HomeSectionView(
          section: feed.sections[sectionIndex],
          sectionIndex: sectionIndex,
        );
      },
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item, required this.onTap});

  final MusicItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          height: 168,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.navBar,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              Artwork(url: item.imageUrl, size: 136, radius: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NEW RELEASE',
                      style: TextStyle(
                        color: palette.onNavBar.withValues(alpha: 0.54),
                        fontSize: 10,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.onNavBar,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.subtitle ?? 'Selected for you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.onNavBar.withValues(alpha: 0.54),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.onNavBar,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: palette.navBar,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSectionView extends ConsumerWidget {
  const _HomeSectionView({required this.section, required this.sectionIndex});

  final HomeSection section;
  final int sectionIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = section.type == 'recommended_artists';
    final large = !artists && sectionIndex % 3 == 1;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Icon(Icons.arrow_outward_rounded, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: artists
                ? 152
                : large
                ? 238
                : 186,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: section.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = section.items[index];
                return _MusicCard(
                  item: item,
                  index: index,
                  artist: artists,
                  large: large,
                  onTap: () => openMusicItem(
                    context,
                    ref,
                    item,
                    queue: section.items
                        .where((entry) => entry.playable)
                        .toList(),
                    index: section.items
                        .take(index)
                        .where((entry) => entry.playable)
                        .length,
                    source: section.type,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicCard extends StatelessWidget {
  const _MusicCard({
    required this.item,
    required this.index,
    required this.artist,
    required this.large,
    required this.onTap,
  });

  final MusicItem item;
  final int index;
  final bool artist;
  final bool large;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = artist
        ? 104.0
        : large
        ? 176.0
        : 128.0;
    final artSize = artist
        ? 102.0
        : large
        ? 176.0
        : 128.0;
    final palette = AppPalette.of(context);
    final colors = [palette.peach, palette.blue, palette.lilac, palette.mint];
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: artist
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: artist ? const EdgeInsets.all(2) : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: colors[index % colors.length],
                borderRadius: BorderRadius.circular(26),
              ),
              child: artist
                  ? OrganicArtwork(
                      url: item.imageUrl,
                      size: artSize,
                      variant: index,
                    )
                  : Artwork(
                      url: item.imageUrl,
                      size: artSize,
                      radius: large ? 30 : 22,
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!artist)
              Text(
                item.subtitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.message, required this.retry});

  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: palette.peach,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 38,
                color: palette.onTile,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Your soundwaves are offline',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: retry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
