import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/details/data/details_repository.dart';
import 'package:music_hub_app/features/downloads/data/download_repository.dart';
import 'package:music_hub_app/features/library/presentation/library_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/utils/item_actions.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';
import 'package:music_hub_app/shared/widgets/music_tile.dart';

final detailsRepositoryProvider = Provider<DetailsRepository>((ref) {
  return DetailsRepository(ref.watch(apiClientProvider));
});

final artistDetailsProvider = FutureProvider.family<MusicDetails, String>((
  ref,
  key,
) {
  return ref.watch(detailsRepositoryProvider).artist(key);
});

final albumDetailsProvider = FutureProvider.family<MusicDetails, String>((
  ref,
  key,
) {
  return ref.watch(detailsRepositoryProvider).album(key);
});

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.seokey});

  final String seokey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailsScaffold(
      value: ref.watch(artistDetailsProvider(seokey)),
      source: 'artist',
      isArtist: true,
      retry: () => ref.invalidate(artistDetailsProvider(seokey)),
    );
  }
}

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.seokey});

  final String seokey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailsScaffold(
      value: ref.watch(albumDetailsProvider(seokey)),
      source: 'album',
      isArtist: false,
      retry: () => ref.invalidate(albumDetailsProvider(seokey)),
    );
  }
}

class _DetailsScaffold extends ConsumerWidget {
  const _DetailsScaffold({
    required this.value,
    required this.source,
    required this.isArtist,
    required this.retry,
  });

  final AsyncValue<MusicDetails> value;
  final String source;
  final bool isArtist;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: retry, child: const Text('Try again')),
            ],
          ),
        ),
        data: (details) => CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 382,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              actions: [
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.ios_share_rounded),
                ),
                const SizedBox(width: 12),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  margin: const EdgeInsets.fromLTRB(12, 58, 12, 8),
                  decoration: BoxDecoration(
                    color: isArtist ? AppTheme.blue : AppTheme.peach,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OrganicArtwork(
                        url: details.item.imageUrl,
                        size: 286,
                        variant: isArtist ? 1 : 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  children: [
                    Text(
                      details.item.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      details.item.subtitle ??
                          (isArtist ? 'Artist profile' : 'Album'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isArtist)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await ref
                                  .read(libraryRepositoryProvider)
                                  .follow(details.item);
                              ref.invalidate(libraryControllerProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Artist added to your library',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Follow'),
                          ),
                        if (isArtist) const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: details.tracks.isEmpty
                              ? null
                              : () => openMusicItem(
                                  context,
                                  ref,
                                  details.tracks.first,
                                  queue: details.tracks,
                                  source: source,
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('Play ${details.tracks.length} tracks'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (details.tracks.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('No playable tracks were returned'),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: details.tracks.length,
                itemBuilder: (context, index) {
                  final track = details.tracks[index];
                  return MusicTile(
                    item: track,
                    onTap: () => openMusicItem(
                      context,
                      ref,
                      track,
                      queue: details.tracks,
                      index: index,
                      source: source,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) =>
                          _trackAction(context, ref, track, action),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'like', child: Text('Like song')),
                        PopupMenuItem(
                          value: 'download',
                          child: Text('Download for offline'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (details.related.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 28, 16, 12),
                  child: Text(
                    'You may also like',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: details.related.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final item = details.related[index];
                      return SizedBox(
                        width: 120,
                        child: InkWell(
                          onTap: () => openMusicItem(
                            context,
                            ref,
                            item,
                            source: '${source}_related',
                          ),
                          child: Column(
                            children: [
                              item.type == MusicItemType.artist
                                  ? OrganicArtwork(
                                      url: item.imageUrl,
                                      size: 116,
                                      variant: index,
                                    )
                                  : Artwork(
                                      url: item.imageUrl,
                                      size: 116,
                                      radius: 24,
                                    ),
                              const SizedBox(height: 8),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  Future<void> _trackAction(
    BuildContext context,
    WidgetRef ref,
    MusicItem track,
    String action,
  ) async {
    try {
      if (action == 'like') {
        await ref.read(libraryRepositoryProvider).like(track);
        ref.invalidate(libraryControllerProvider);
      } else {
        await ref.read(downloadRepositoryProvider).download(track, (_) {});
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'like' ? 'Added to liked songs' : 'Download complete',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}
