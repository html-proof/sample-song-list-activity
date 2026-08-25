import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/artists/presentation/artist_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/utils/item_actions.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

/// Search field for the artist screen. Debouncing and request cancellation
/// live in the controller; this only reports keystrokes.
class ArtistSearchField extends ConsumerStatefulWidget {
  const ArtistSearchField({super.key, this.hintText = 'Search artists'});

  final String hintText;

  @override
  ConsumerState<ArtistSearchField> createState() => _ArtistSearchFieldState();
}

class _ArtistSearchFieldState extends ConsumerState<ArtistSearchField> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: ref.read(artistControllerProvider).query,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(artistControllerProvider.notifier);
    final hasQuery = ref.watch(
      artistControllerProvider.select((state) => state.query.isNotEmpty),
    );
    return TextField(
      controller: _text,
      textInputAction: TextInputAction.search,
      onChanged: controller.onQueryChanged,
      onSubmitted: controller.search,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: hasQuery
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _text.clear();
                  controller.cancelSearch();
                },
              )
            : null,
      ),
    );
  }
}

/// Recommendations, paged by cursor. The list is never cleared while more is
/// loading, and the next page is requested at roughly 75% of the current one.
class RecommendedArtistsView extends ConsumerStatefulWidget {
  const RecommendedArtistsView({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 130),
    this.isSelected,
    this.onArtistTap,
  });

  final EdgeInsets padding;

  /// Supplied by the favourite-artists picker, where a card toggles a choice
  /// instead of opening the artist.
  final bool Function(MusicItem artist)? isSelected;
  final void Function(MusicItem artist)? onArtistTap;

  @override
  ConsumerState<RecommendedArtistsView> createState() =>
      _RecommendedArtistsViewState();
}

class _RecommendedArtistsViewState
    extends ConsumerState<RecommendedArtistsView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels < position.maxScrollExtent * 0.75) return;
    ref.read(artistControllerProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(artistControllerProvider);
    final palette = AppPalette.of(context);

    if (state.recommendations.isEmpty) {
      if (state.loadingRecommendations) {
        return const Center(child: CircularProgressIndicator());
      }
      return _ArtistMessage(
        icon: Icons.person_search_rounded,
        message:
            state.error ??
            'Pick a few languages and artists and your recommendations will '
                'appear here.',
        onRetry: ref
            .read(artistControllerProvider.notifier)
            .refreshRecommendations,
      );
    }

    return RefreshIndicator(
      color: palette.ink,
      onRefresh: ref
          .read(artistControllerProvider.notifier)
          .refreshRecommendations,
      child: GridView.builder(
        controller: _scroll,
        padding: widget.padding,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.74,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: state.recommendations.length + (state.loadingMore ? 3 : 0),
        itemBuilder: (context, index) {
          if (index >= state.recommendations.length) {
            return const _ArtistCardPlaceholder();
          }
          final artist = state.recommendations[index];
          return ArtistCard(
            artist: artist,
            variant: index,
            source: 'recommended_artists',
            selected: widget.isSelected?.call(artist) ?? false,
            onTap: widget.onArtistTap == null
                ? null
                : () => widget.onArtistTap!(artist),
          );
        },
      ),
    );
  }
}

/// Artist-only results for the current query.
class ArtistSearchResults extends ConsumerWidget {
  const ArtistSearchResults({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 130),
    this.isSelected,
    this.onArtistTap,
  });

  final EdgeInsets padding;
  final bool Function(MusicItem artist)? isSelected;
  final void Function(MusicItem artist)? onArtistTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(artistControllerProvider);

    if (state.searching && state.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.searchResults.isEmpty) {
      return _ArtistMessage(
        icon: Icons.search_off_rounded,
        message: state.error ?? 'No artists match "${state.query.trim()}"',
      );
    }

    return GridView.builder(
      padding: padding,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.74,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: state.searchResults.length,
      itemBuilder: (context, index) {
        final artist = state.searchResults[index];
        return ArtistCard(
          artist: artist,
          variant: index,
          source: 'artist_search',
          selected: isSelected?.call(artist) ?? false,
          onTap: onArtistTap == null ? null : () => onArtistTap!(artist),
        );
      },
    );
  }
}

/// A single artist. The name is drawn outside the artwork so it survives an
/// artwork failure, and tapping opens the artist immediately.
class ArtistCard extends ConsumerWidget {
  const ArtistCard({
    super.key,
    required this.artist,
    required this.variant,
    required this.source,
    this.selected = false,
    this.onTap,
  });

  final MusicItem artist;
  final int variant;
  final String source;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap ?? () => openArtist(context, ref, artist, source: source),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Artwork falls back to a placeholder rather than collapsing,
                // so the card keeps its shape when the image endpoint fails.
                OrganicArtwork(
                  url: artist.imageUrl,
                  size: double.infinity,
                  variant: variant,
                ),
                if (selected)
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppTheme.ink,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            artist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          if (artist.subtitle != null && artist.subtitle!.isNotEmpty)
            Text(
              artist.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _ArtistCardPlaceholder extends StatelessWidget {
  const _ArtistCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.panelHigh,
              shape: BoxShape.circle,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 11, width: 62, color: palette.panelHigh),
      ],
    );
  }
}

class _ArtistMessage extends StatelessWidget {
  const _ArtistMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: palette.muted),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
