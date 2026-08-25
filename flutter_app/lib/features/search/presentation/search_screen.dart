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
              style: TextStyle(color: context.primaryText, fontSize: 16),
              cursorColor: context.colors.primary,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums',
                hintStyle: TextStyle(color: context.secondaryText),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: context.secondaryText,
                ),
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
                  for (final type in const [
                    'all',
                    'songs',
                    'artists',
                    'albums',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: state.type == type,
                        label: Text(type[0].toUpperCase() + type.substring(1)),
                        onSelected: (_) => controller.selectType(type),
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
                : state.results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(child: Text(error.toString())),
                    data: (results) => _Results(
                      results: results,
                      type: state.type,
                      onTap: (item, queue, index) {
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
                    ),
                  ),
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 130),
    children: [
      if (recent.isNotEmpty) ...[
        Text('Recent', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
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
      Text('Browse your sound', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        'Find music by language',
        style: TextStyle(color: context.secondaryText),
      ),
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
                    context.accents.peach,
                    context.accents.blue,
                    context.accents.lilac,
                    context.accents.mint,
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

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.type,
    required this.onTap,
  });

  final SearchResults results;
  final String type;
  final void Function(MusicItem item, List<MusicItem> queue, int index) onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const Center(child: Text('No results found'));
    return ListView(
      padding: const EdgeInsets.only(bottom: 130),
      children: [
        if ((type == 'all' || type == 'songs') && results.songs.isNotEmpty)
          _Group(title: 'Songs', items: results.songs, onTap: onTap),
        if ((type == 'all' || type == 'artists') && results.artists.isNotEmpty)
          _ArtistGroup(items: results.artists, onTap: onTap),
        if ((type == 'all' || type == 'albums') && results.albums.isNotEmpty)
          _Group(title: 'Albums', items: results.albums, onTap: onTap),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items, required this.onTap});

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
        MusicTile(item: items[i], onTap: () => onTap(items[i], items, i)),
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
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
