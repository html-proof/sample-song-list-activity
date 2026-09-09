import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'artist_profile_screen.dart';
import 'player_screen.dart';

class AlbumDetailsScreen extends StatefulWidget {
  const AlbumDetailsScreen({
    super.key,
    required this.state,
    required this.albumId,
    this.heroTag,
    this.preview,
  });
  final AppState state;
  final String albumId;
  final String? heroTag;
  final Album? preview;
  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> {
  late final Future<Album> _album = _loadAlbum();
  bool saved = false;
  Future<Album> _loadAlbum() async {
    // 1. Direct API lookup with safety timeout to load all full album tracks
    try {
      if (widget.albumId.isNotEmpty) {
        final result = await widget.state.api
            .albumDetails(widget.albumId)
            .timeout(const Duration(seconds: 10));
        if (result.tracks.isNotEmpty) {
          return result.copyWith(
            title: result.title.isNotEmpty ? result.title : (widget.preview?.title ?? ''),
            artist: result.artist.isNotEmpty ? result.artist : (widget.preview?.artist ?? ''),
            imageUrl: result.imageUrl.isNotEmpty ? result.imageUrl : (widget.preview?.imageUrl ?? ''),
            trackCount: result.tracks.length,
          );
        }
      }
    } catch (_) {}

    // 2. Check if preview already has tracks
    if (widget.preview != null && widget.preview!.tracks.isNotEmpty) {
      return widget.preview!;
    }

    // 3. Check offline downloads
    final downloadedTracks = widget.state.downloads.entries
        .where(
          (entry) =>
              entry.track.albumId == widget.albumId ||
              entry.track.albumSeokey == widget.albumId ||
              (widget.preview != null &&
                  entry.track.album.toLowerCase().trim() ==
                      widget.preview!.title.toLowerCase().trim()),
        )
        .map((entry) => entry.track)
        .toList();
    if (downloadedTracks.isNotEmpty) {
      return Album(
        id: widget.preview?.id ?? widget.albumId,
        seokey: widget.preview?.seokey ?? widget.albumId,
        title: widget.preview?.title ?? downloadedTracks.first.album,
        artist: widget.preview?.artist ?? downloadedTracks.first.artist,
        imageUrl: widget.preview?.imageUrl ?? downloadedTracks.first.imageUrl,
        trackCount: downloadedTracks.length,
        tracks: downloadedTracks,
      );
    }

    // 4. Multi-tier track search fallback
    final rawTitle = widget.preview?.title ?? widget.albumId.replaceAll('-', ' ').replaceAll('_', ' ');
    final artistName = widget.preview?.artist ?? '';
    final queries = <String>[
      rawTitle,
      rawTitle.replaceAll(RegExp(r'[^a-zA-Z0-9\s]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
      if (rawTitle.contains('-')) rawTitle.split('-').first.trim(),
      if (rawTitle.contains('–')) rawTitle.split('–').first.trim(),
      if (artistName.isNotEmpty) '$artistName $rawTitle',
      if (artistName.isNotEmpty) artistName,
    ].where((q) => q.isNotEmpty).toSet().toList();

    for (final q in queries) {
      try {
        final cleanQ = q.toLowerCase().trim();
        final tracks = await widget.state.api
            .searchTracks(q, limit: 30)
            .timeout(const Duration(seconds: 8));
        if (tracks.isNotEmpty) {
          final matchingTracks = tracks.where((t) {
            if (widget.albumId.isNotEmpty &&
                (t.albumId == widget.albumId || t.albumSeokey == widget.albumId)) {
              return true;
            }
            if (widget.preview != null &&
                t.album.toLowerCase().trim() == widget.preview!.title.toLowerCase().trim()) {
              return true;
            }
            if (cleanQ.isNotEmpty && (t.album.toLowerCase().contains(cleanQ) || cleanQ.contains(t.album.toLowerCase().trim()))) {
              return true;
            }
            return false;
          }).toList();

          final resolvedTracks = matchingTracks.isNotEmpty ? matchingTracks : tracks;
          if (resolvedTracks.isNotEmpty) {
            return Album(
              id: widget.preview?.id ?? widget.albumId,
              seokey: widget.preview?.seokey ?? widget.albumId,
              title: widget.preview?.title.isNotEmpty == true ? widget.preview!.title : resolvedTracks.first.album,
              artist: widget.preview?.artist.isNotEmpty == true ? widget.preview!.artist : resolvedTracks.first.artist,
              imageUrl: widget.preview?.imageUrl.isNotEmpty == true ? widget.preview!.imageUrl : resolvedTracks.first.imageUrl,
              trackCount: resolvedTracks.length,
              tracks: resolvedTracks,
            );
          }
        }
      } catch (_) {}
    }

    // 5. Guaranteed fallback with active track if matching
    final currentPlaying = widget.state.player.current;
    final fallbackTracks = (currentPlaying != null &&
            (currentPlaying.albumId == widget.albumId ||
                currentPlaying.albumSeokey == widget.albumId ||
                (widget.preview != null &&
                    currentPlaying.album.toLowerCase().trim() ==
                        widget.preview!.title.toLowerCase().trim())))
        ? [currentPlaying]
        : (widget.preview?.tracks ?? <Track>[]);

    if (widget.preview != null && widget.preview!.tracks.isNotEmpty) {
      return widget.preview!;
    }

    return Album(
      id: widget.preview?.id ?? widget.albumId,
      seokey: widget.preview?.seokey ?? widget.albumId,
      title: (widget.preview?.title.isNotEmpty == true) ? widget.preview!.title : (rawTitle.isNotEmpty ? rawTitle : 'Album'),
      artist: widget.preview?.artist ?? currentPlaying?.artist ?? '',
      imageUrl: widget.preview?.imageUrl ?? currentPlaying?.imageUrl ?? '',
      trackCount: fallbackTracks.length,
      tracks: fallbackTracks,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text('Album'),
      centerTitle: true,
      actions: [
        IconButton(
          onPressed: () => setState(() => saved = !saved),
          icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
        ),
      ],
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
    body: FutureBuilder<Album>(
      future: _album,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final preview = widget.preview;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: preview == null
                    ? ColoredBox(color: context.hubColors.backgroundSecondary)
                    : Artwork(
                        url: preview.imageUrl,
                        label: preview.title,
                        radius: 24,
                      ),
              ),
              const SizedBox(height: 18),
              if (preview != null)
                Text(
                  preview.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              const SizedBox(height: 24),
              ...List.generate(
                4,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: context.hubColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          final fallback = widget.preview ??
              Album(
                id: widget.albumId,
                seokey: widget.albumId,
                title: widget.albumId.replaceAll('-', ' ').replaceAll('_', ' '),
                artist: widget.state.player.current?.artist ?? '',
                imageUrl: widget.state.player.current?.imageUrl ?? '',
                trackCount: widget.state.player.current != null ? 1 : 0,
                tracks: widget.state.player.current != null
                    ? [widget.state.player.current!]
                    : [],
              );
          return _AlbumContent(
            state: widget.state,
            album: fallback,
            heroTag: widget.heroTag,
          );
        }
        return _AlbumContent(
          state: widget.state,
          album: snapshot.data!,
          heroTag: widget.heroTag,
        );
      },
    ),
  );
}

class _AlbumContent extends StatefulWidget {
  const _AlbumContent({
    required this.state,
    required this.album,
    this.heroTag,
  });

  final AppState state;
  final Album album;
  final String? heroTag;

  @override
  State<_AlbumContent> createState() => _AlbumContentState();
}

class _AlbumContentState extends State<_AlbumContent> {
  late Future<Map<String, dynamic>> _recsFuture;

  @override
  void initState() {
    super.initState();
    _recsFuture = widget.state.api.albumRecommendations(widget.album.id);
  }

  @override
  void didUpdateWidget(covariant _AlbumContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id) {
      _recsFuture = widget.state.api.albumRecommendations(widget.album.id);
    }
  }

  List<Artist> _getAlbumArtists(Album album) {
    final rawNames = album.artist
        .split(RegExp(r'[,/;&]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final rawIds = album.artistIds
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final list = <Artist>[];
    for (var i = 0; i < rawNames.length; i++) {
      final name = rawNames[i];
      final seokey = i < rawIds.length && rawIds[i].isNotEmpty
          ? rawIds[i]
          : name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      list.add(Artist(seokey: seokey, name: name));
    }
    return list;
  }

  List<Artist> _getTrackArtists(Track track) {
    final rawNames = track.artist
        .split(RegExp(r'[,/;&]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final rawIds = track.artistIds
        .split(RegExp(r'[,/;&]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final list = <Artist>[];
    for (var i = 0; i < rawNames.length; i++) {
      final name = rawNames[i];
      final seokey = i < rawIds.length && rawIds[i].isNotEmpty
          ? rawIds[i]
          : name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      list.add(Artist(seokey: seokey, name: name));
    }
    return list;
  }

  void _openArtistScreen(BuildContext context, Artist artist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArtistProfileScreen(
          artist: artist,
          state: widget.state,
        ),
      ),
    );
  }

  void _showArtistSelectionSheet(BuildContext context, List<Artist> artists) {
    if (artists.isEmpty) return;
    if (artists.length == 1) {
      _openArtistScreen(context, artists.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hubColors.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Artists',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: artists.length,
                  itemBuilder: (_, index) {
                    final artist = artists[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      leading: SizedBox.square(
                        dimension: 44,
                        child: ClipOval(
                          child: Artwork(
                            url: artist.imageUrl,
                            label: artist.name,
                            radius: 999,
                          ),
                        ),
                      ),
                      title: Text(
                        artist.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: const Text(
                        'Artist',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openArtistScreen(context, artist);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClickableArtists(BuildContext context, Album album) {
    final artists = _getAlbumArtists(album);
    if (artists.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 2,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (int i = 0; i < artists.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _openArtistScreen(context, artists[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Text(
                  artists[i].name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (i < artists.length - 1)
              Text(
                ',',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _retryRecs() {
    setState(() {
      _recsFuture = widget.state.api.albumRecommendations(widget.album.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final state = widget.state;
    final tracks = album.tracks;
    final fullArtist = album.artist.isNotEmpty
        ? album.artist
        : (tracks.isNotEmpty ? tracks.first.artist : '');
    final primaryArtist = fullArtist.isNotEmpty
        ? fullArtist.split(',').first.trim()
        : '';
    final year = album.releaseDate.length >= 4
        ? album.releaseDate.substring(0, 4)
        : '';
    final art = Artwork(url: album.imageUrl, label: album.title, radius: 24);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: AspectRatio(
              aspectRatio: 1,
              child: widget.heroTag == null
                  ? art
                  : Hero(tag: widget.heroTag!, child: art),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.title.toUpperCase(),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 7),
                _buildClickableArtists(context, album),
                const SizedBox(height: 10),
                Text(
                  [
                    'Album',
                    if (album.language.isNotEmpty) album.language,
                    if (year.isNotEmpty) year,
                    '${album.trackCount == 0 ? tracks.length : album.trackCount} songs',
                  ].join('  •  '),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () {
                              state.player.isShuffled = false;
                              state.play(tracks.first, tracks);
                            },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      onPressed: tracks.isEmpty
                          ? null
                          : () => state.playWithShuffle(tracks),
                      icon: const Icon(Icons.shuffle_rounded),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () async {
                        for (final track in tracks) {
                          await state.downloadTrack(track);
                        }
                      },
                      icon: const Icon(Icons.download_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final track = tracks[index];
            return ListenableBuilder(
              listenable: state.player,
              builder: (context, _) {
                final active = state.player.isCurrentTrack(track);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: SizedBox(
                    width: 28,
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: active
                              ? AppColors.orange
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.orange : null,
                    ),
                  ),
                  subtitle: InkWell(
                    onTap: () {
                      final trackArtists = _getTrackArtists(track);
                      if (trackArtists.length == 1) {
                        _openArtistScreen(context, trackArtists.first);
                      } else if (trackArtists.length > 1) {
                        _showArtistSelectionSheet(context, trackArtists);
                      }
                    },
                    child: Text(
                      '${track.artist}${track.isExplicit ? '  •  E' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DownloadIndicator(track: track, state: state),
                      Text(
                        formatDuration(Duration(seconds: track.durationSeconds)),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        onPressed: () => state.downloadTrack(track),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ],
                  ),
                  onTap: () => state.play(track, tracks),
                );
              },
            );
          }, childCount: tracks.length),
        ),
        SliverToBoxAdapter(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _recsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildRecsSkeleton(context, primaryArtist);
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _retryRecs,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry recommendations'),
                      ),
                      _buildCopyright(context, year, album.label),
                    ],
                  ),
                );
              }

              final data = snapshot.data ?? const {};
              final rawMoreBy = (data['moreByArtist'] as List<AlbumRecommendation>?) ?? const [];
              final rawYouMightLike = (data['youMightAlsoLike'] as List<AlbumRecommendation>?) ?? const [];
              final headerArtist = (data['primaryArtist'] as String?)?.isNotEmpty == true
                  ? data['primaryArtist'] as String
                  : primaryArtist;

              final moreBy = _dedupeRecs(rawMoreBy, album.id, album.title);
              final usedIds = moreBy.map((e) => e.id.toLowerCase()).toSet();
              final youMightLike = _dedupeRecs(rawYouMightLike, album.id, album.title)
                  .where((e) => !usedIds.contains(e.id.toLowerCase()))
                  .toList();

              return Padding(
                padding: const EdgeInsets.only(bottom: 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (moreBy.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          headerArtist.isNotEmpty
                              ? 'More by $headerArtist'
                              : 'More by this artist',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildAlbumCarousel(context, state, moreBy),
                    ],
                    if (youMightLike.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const Text(
                          'You might also like',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildAlbumCarousel(context, state, youMightLike),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                      child: _buildCopyright(context, year, album.label),
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

  String _cleanTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '')
        .replaceAll(
          RegExp(
            r'\b(?:original motion picture soundtrack|soundtrack|ost|vol(?:ume)?\.?\s*\d+|ep|single)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .trim();
  }

  List<AlbumRecommendation> _dedupeRecs(
    List<AlbumRecommendation> items,
    String currentAlbumId,
    String currentTitle,
  ) {
    final cleanCurrent = _cleanTitle(currentTitle);
    final seenIds = <String>{currentAlbumId.toLowerCase().trim()};
    final seenKeys = <String>{};
    final result = <AlbumRecommendation>[];

    for (final item in items) {
      if (item.id.isEmpty) continue;
      final cleanItemTitle = _cleanTitle(item.title);
      final artistKey = item.artistName
          .toLowerCase()
          .split(',')
          .first
          .replaceAll(RegExp(r'[^a-z0-9]+'), '')
          .trim();
      final semKey = '$cleanItemTitle-$artistKey';

      if (seenIds.contains(item.id.toLowerCase().trim())) continue;
      if (cleanItemTitle.isNotEmpty && cleanItemTitle == cleanCurrent) continue;
      if (cleanItemTitle.isNotEmpty && seenKeys.contains(semKey)) continue;

      seenIds.add(item.id.toLowerCase().trim());
      if (cleanItemTitle.isNotEmpty) seenKeys.add(semKey);
      result.add(item);
    }
    return result;
  }

  Widget _buildAlbumCarousel(
    BuildContext context,
    AppState state,
    List<AlbumRecommendation> recs,
  ) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: recs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = recs[index];
          return _RecommendedAlbumCard(
            item: item,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlbumDetailsScreen(
                    state: state,
                    albumId: item.id,
                    preview: item.toAlbum(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRecsSkeleton(BuildContext context, String primaryArtist) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primaryArtist.isNotEmpty
                ? 'More by $primaryArtist'
                : 'Recommended albums',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, _) => Container(
                width: 135,
                decoration: BoxDecoration(
                  color: context.hubColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyright(BuildContext context, String year, String label) {
    if (label.isEmpty && year.isEmpty) return const SizedBox.shrink();
    return Text(
      '© ${[year, label].where((v) => v.isNotEmpty).join(' ')}',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _RecommendedAlbumCard extends StatelessWidget {
  const _RecommendedAlbumCard({required this.item, required this.onTap});

  final AlbumRecommendation item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final yearText = item.releaseYear != null ? '${item.releaseYear}' : '';
    final subText = [
      if (item.artistName.isNotEmpty) item.artistName,
      if (yearText.isNotEmpty) yearText,
    ].join(' • ');

    return SizedBox(
      width: 135,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Artwork(
                url: item.imageUrl,
                label: item.title,
                radius: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subText.isNotEmpty ? subText : (item.language.isNotEmpty ? item.language : 'Album'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
