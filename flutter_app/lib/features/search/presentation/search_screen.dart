import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:music_hub_app/features/search/data/search_repository.dart';
import 'package:music_hub_app/features/search/presentation/search_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/utils/item_actions.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';
import 'package:music_hub_app/shared/widgets/music_tile.dart';

/// How many of each type the mixed tab shows before the rest are left to that
/// type's own tab, so artists and albums stay reachable without scrolling past
/// every song.
const _allTabLimits = {
  MusicItemType.song: 5,
  MusicItemType.artist: 3,
  MusicItemType.album: 3,
  MusicItemType.playlist: 3,
};

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    final languages =
        ref.watch(availableLanguagesProvider).value ?? const <String>[];
    final results = state.results;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: const Text(
          'Discover',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton.filledTonal(
              onPressed: () {
                _text.clear();
                controller.queryChanged('');
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: TextField(
              controller: _text,
              onChanged: controller.queryChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search songs, artists, albums',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (state.query.trim().length >= 2)
            SizedBox(
              height: 52,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final category in SearchCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: state.category == category,
                        label: Text(category.label),
                        onSelected: (_) => controller.selectCategory(category),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: state.query.trim().length < 2
                ? _SearchLanding(
                    recent: state.recent,
                    languages: languages,
                    onRecent: (query) {
                      _text.text = query;
                      controller.submitRecent(query);
                    },
                    onRemove: controller.removeRecent,
                    onLanguage: (language) {
                      final query = '$language songs';
                      _text.text = query;
                      controller.submitRecent(query);
                    },
                  )
                // Results already on screen stay there while the next request
                // runs, so typing another character never blanks the list.
                : results.hasValue
                ? _Results(
                    results: results.requireValue,
                    category: state.category,
                    query: state.query.trim(),
                    onTap: (item, queue, index) {
                      // The keyboard goes away before the push so it cannot
                      // cover the screen being opened.
                      FocusScope.of(context).unfocus();
                      controller.recordClick(item);
                      openMusicItem(
                        context,
                        ref,
                        item,
                        queue: queue,
                        index: index,
                        source: 'search',
                      );
                    },
                  )
                : results.hasError
                ? _SearchError(
                    error: results.error!,
                    onRetry: controller.retry,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}

/// A failed search leaves playback untouched; only this pane is affected.
class _SearchError extends StatelessWidget {
  const _SearchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _SearchLanding extends StatelessWidget {
  const _SearchLanding({
    required this.recent,
    required this.languages,
    required this.onRecent,
    required this.onRemove,
    required this.onLanguage,
  });

  final List<String> recent;
  final List<String> languages;
  final ValueChanged<String> onRecent;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onLanguage;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 130),
      children: [
        if (recent.isNotEmpty) ...[
          Text('Recent', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: palette.panel,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                for (final query in recent)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(
                      query,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => onRecent(query),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => onRemove(query),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
        Text(
          'Browse your sound',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text('Find music by language', style: TextStyle(color: palette.muted)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var index = 0; index < languages.length; index++)
              InkWell(
                onTap: () => onLanguage(languages[index]),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 150,
                  height: 86,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: [
                      palette.peach,
                      palette.blue,
                      palette.lilac,
                      palette.mint,
                    ][index % 4],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.waves_rounded, size: 20),
                      Text(
                        languages[index],
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.category,
    required this.query,
    required this.onTap,
  });

  final SearchResults results;
  final SearchCategory category;
  final String query;
  final void Function(MusicItem item, List<MusicItem> queue, int index) onTap;

  /// The items to show for one type on the current tab: everything on that
  /// type's own tab, a short lead-in on the mixed tab, and nothing at all when
  /// another tab is selected.
  List<MusicItem> _section(MusicItemType type) {
    if (category != SearchCategory.all && category.itemType != type) {
      return const [];
    }
    final items = results.of(type);
    if (category != SearchCategory.all) return items;
    final limit = _allTabLimits[type]!;
    return items.length <= limit ? items : items.sublist(0, limit);
  }

  @override
  Widget build(BuildContext context) {
    final songs = _section(MusicItemType.song);
    final artists = _section(MusicItemType.artist);
    final albums = _section(MusicItemType.album);
    final playlists = _section(MusicItemType.playlist);

    if (results.isEmptyFor(category)) {
      return Center(child: Text(_emptyMessage()));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 130),
      // Dragging the results dismisses the keyboard, which is what a user
      // reaching for a result further down expects.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        // An empty group contributes nothing at all, so a category with no
        // matches never leaves a heading over blank space.
        if (songs.isNotEmpty)
          _TileGroup(title: 'Songs', items: songs, onTap: onTap),
        if (artists.isNotEmpty) _ArtistGroup(items: artists, onTap: onTap),
        if (albums.isNotEmpty)
          _TileGroup(title: 'Albums', items: albums, onTap: onTap),
        if (playlists.isNotEmpty)
          _TileGroup(title: 'Playlists', items: playlists, onTap: onTap),
      ],
    );
  }

  String _emptyMessage() => switch (category) {
    SearchCategory.all => 'No results found for "$query"',
    SearchCategory.songs => 'No songs found for "$query"',
    SearchCategory.artists => 'No artists found for "$query"',
    SearchCategory.albums => 'No albums found for "$query"',
    SearchCategory.playlists => 'No playlists found for "$query"',
  };
}

/// The secondary line of a result card. Always names the content type, so a
/// song is never mistaken for the album it belongs to.
String _subtitleFor(MusicItem item) {
  final label = item.typeLabel;
  final parts = <String>[];
  switch (item.type) {
    case MusicItemType.song:
    case MusicItemType.album:
      if (item.artistName != null) parts.add(item.artistName!);
      if (label != null) parts.add(label);
    case MusicItemType.playlist:
      if (label != null) parts.add(label);
      final count = item.songCount;
      if (count != null && count > 0) parts.add('$count songs');
    case MusicItemType.artist:
    case MusicItemType.unknown:
      if (label != null) parts.add(label);
  }
  return parts.join(' • ');
}

class _TileGroup extends StatelessWidget {
  const _TileGroup({
    required this.title,
    required this.items,
    required this.onTap,
  });

  final String title;
  final List<MusicItem> items;
  final void Function(MusicItem item, List<MusicItem> queue, int index) onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      for (var i = 0; i < items.length; i++)
        MusicTile(
          item: items[i],
          subtitle: _subtitleFor(items[i]),
          onTap: () => onTap(items[i], items, i),
        ),
    ],
  );
}

class _ArtistGroup extends StatelessWidget {
  const _ArtistGroup({required this.items, required this.onTap});

  final List<MusicItem> items;
  final void Function(MusicItem item, List<MusicItem> queue, int index) onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Text('Artists', style: Theme.of(context).textTheme.titleLarge),
      ),
      SizedBox(
        height: 158,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (context, index) => SizedBox(
            width: 106,
            child: InkWell(
              onTap: () => onTap(items[index], items, index),
              child: Column(
                children: [
                  OrganicArtwork(
                    url: items[index].imageUrl,
                    size: 102,
                    variant: index,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    items[index].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
