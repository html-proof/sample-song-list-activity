import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../offline.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'album_details_screen.dart';
import 'artist_profile_screen.dart';
import 'lyrics_screen.dart';

// Navigation lock to prevent duplicate pushes from rapid taps
bool _playerOpenInProgress = false;

Future<void> openFullPlayer(BuildContext context, AppState state) async {
  if (state.player.current == null) return;
  if (_playerOpenInProgress) return;
  _playerOpenInProgress = true;
  try {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(state: state),
        settings: const RouteSettings(name: '/player'),
      ),
    );
  } finally {
    _playerOpenInProgress = false;
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.state});
  final AppState state;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return PopScope(
      canPop: true,
      child: ListenableBuilder(
        listenable: state.player,
        builder: (context, _) {
          final track = state.player.current;
          if (track == null) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                  tooltip: 'Close player',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('Current track'),
                centerTitle: true,
              ),
              body: const Center(child: Text('No track playing')),
            );
          }
          final max = state.player.duration.inMilliseconds
              .toDouble()
              .clamp(1.0, double.infinity);
          final currentPos = _dragValue ?? state.player.position.inMilliseconds.toDouble();
          final value = currentPos.clamp(0.0, max);
          final displayPos = Duration(milliseconds: value.round());
          final displayDur = state.player.duration;
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                tooltip: 'Close player',
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: const Text('Current track'),
              centerTitle: true,
        actions: [
          ListenableBuilder(
            listenable: state.downloads,
            builder: (context, _) {
              final isDownloaded = state.downloads.isDownloaded(track.seokey) ||
                  (track.id.isNotEmpty && state.downloads.isDownloaded(track.id));
              final entry = state.downloads.entryFor(track.seokey) ??
                  (track.id.isNotEmpty ? state.downloads.entryFor(track.id) : null);
              final isDownloading = entry?.status == DownloadStatus.downloading ||
                  entry?.status == DownloadStatus.queued;

              if (isDownloading) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        value: entry?.progress,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                );
              }

              if (isDownloaded) {
                return IconButton(
                  tooltip: 'Downloaded (Tap to delete)',
                  onPressed: () => _confirmDeleteDownload(context, state, track),
                  icon: Icon(
                    Icons.download_done_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              }

              return IconButton(
                tooltip: 'Download offline',
                onPressed: () async {
                  await state.downloads.enqueue(track, resolveTrack: state.api.resolvePlayableTrack);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Downloading "${track.title}" offline...'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.download_for_offline_outlined),
              );
            },
          ),
          IconButton(
            onPressed: () => state.toggleFavorite(track),
            icon: Icon(
              state.isFavorite(track) ? Icons.favorite : Icons.favorite_border,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
          child: Column(
            children: [
              Text(
                '${formatDuration(displayPos)}  |  ${formatDuration(displayDur)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  final albumId = track.albumSeokey.isNotEmpty
                      ? track.albumSeokey
                      : (track.albumId.isNotEmpty ? track.albumId : track.album);
                  if (albumId.isEmpty) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailsScreen(
                        state: state,
                        albumId: albumId,
                        heroTag: 'album-art-${track.seokey}',
                        preview: Album(
                          id: albumId,
                          seokey: albumId,
                          title: track.album,
                          artist: track.artist,
                          artistIds: track.artistIds
                              .split(',')
                              .map((value) => value.trim())
                              .where((value) => value.isNotEmpty)
                              .toList(),
                          imageUrl: track.imageUrl,
                          trackCount: 1,
                          tracks: [track],
                        ),
                      ),
                    ),
                  );
                },
                child: Hero(
                  tag: 'album-art-${track.seokey}',
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(120),
                      ),
                      child: Artwork(
                        url: track.imageUrl,
                        label: track.title,
                        radius: 95,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                track.title.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _onArtistTapped(context, track),
                child: Text(
                  track.artist,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Slider(
                value: value,
                max: max,
                onChanged: (position) {
                  setState(() => _dragValue = position);
                },
                onChangeEnd: (position) async {
                  final target = Duration(milliseconds: position.round());
                  setState(() => _dragValue = null);
                  await state.player.seek(target);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: state.player.toggleRepeatMode,
                    tooltip: switch (state.player.repeatMode) {
                      PlaybackRepeatMode.off => 'Repeat: Off',
                      PlaybackRepeatMode.all => 'Repeat: All',
                      PlaybackRepeatMode.one => 'Repeat: One',
                    },
                    icon: Icon(
                      state.player.repeatMode == PlaybackRepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      size: 26,
                      color: state.player.repeatMode != PlaybackRepeatMode.off
                          ? Theme.of(context).colorScheme.primary
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white54
                              : Colors.black45),
                    ),
                  ),
                  IconButton(
                    onPressed: state.player.previous,
                    icon: const Icon(Icons.skip_previous_rounded, size: 36),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(24),
                    ),
                    onPressed: state.player.toggle,
                    child: Icon(
                      state.player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 36,
                    ),
                  ),
                  IconButton(
                    onPressed: state.player.next,
                    icon: const Icon(Icons.skip_next_rounded, size: 36),
                  ),
                  IconButton(
                    onPressed: state.player.toggleShuffle,
                    tooltip: state.player.isShuffled ? 'Shuffle: On' : 'Shuffle: Off',
                    icon: Icon(
                      Icons.shuffle_rounded,
                      size: 26,
                      color: state.player.isShuffled
                          ? Theme.of(context).colorScheme.primary
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white54
                              : Colors.black45),
                    ),
                  ),
                ],
              ),
              if (state.player.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    state.player.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Spacer(),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LyricsScreen(state: state, track: track),
                  ),
                ),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lyrics_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lyrics',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to view synchronized lyrics',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
        },
      ),
    );
  }

  List<Artist> _getTrackArtists(Track track) {
    final names = track.artist
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final ids = track.artistIds
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final result = <Artist>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final seokey = i < ids.length && ids[i].isNotEmpty
          ? ids[i]
          : name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      result.add(Artist(seokey: seokey, name: name));
    }
    return result;
  }

  void _onArtistTapped(BuildContext context, Track track) {
    final artists = _getTrackArtists(track);
    if (artists.isEmpty) return;
    if (artists.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistProfileScreen(
            artist: artists.first,
            state: widget.state,
          ),
        ),
      );
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
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArtistProfileScreen(
                              artist: artist,
                              state: widget.state,
                            ),
                          ),
                        );
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

  Future<void> _confirmDeleteDownload(
    BuildContext context,
    AppState state,
    Track track,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download?'),
        content: Text('Remove "${track.title}" from your offline downloads?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (remove == true) {
      await state.downloads.remove(track.seokey);
      if (track.id.isNotEmpty) await state.downloads.remove(track.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${track.title}" from offline downloads'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
