import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_state.dart';
import 'models.dart';
import 'offline.dart';
import 'screens/player_screen.dart';
import 'theme.dart';

class ArtistPhotoResolver {
  static final Map<String, String> _cache = {};
  static final Map<String, Future<String?>> _inFlight = {};

  static String? getCached(String name) {
    final key = name.toLowerCase().trim();
    return _cache[key];
  }

  static Future<String?> resolve(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    final key = clean.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];

    if (_inFlight.containsKey(key)) {
      return _inFlight[key];
    }

    final future = _fetchPhoto(clean);
    _inFlight[key] = future;
    try {
      final result = await future;
      if (result != null && result.isNotEmpty) {
        _cache[key] = result;
      }
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<String?> _fetchPhoto(String name) async {
    // 1. Try Deezer Artist API for high-resolution original artist picture
    try {
      final uri = Uri.parse(
        'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(name)}&limit=1',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['data'] is List && (data['data'] as List).isNotEmpty) {
          final first = (data['data'] as List).first;
          if (first is Map) {
            final pic = first['picture_xl'] ?? first['picture_big'] ?? first['picture_medium'];
            if (pic is String && pic.isNotEmpty && !pic.contains('artist-default')) {
              return pic;
            }
          }
        }
      }
    } catch (_) {}

    // 2. Try iTunes Artist API
    try {
      final uri = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(name)}&entity=musicArtist&limit=1',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['results'] is List && (data['results'] as List).isNotEmpty) {
          final first = (data['results'] as List).first;
          if (first is Map) {
            final pic = first['artworkUrl100'] ?? first['artworkUrl60'];
            if (pic is String && pic.isNotEmpty) {
              return pic.replaceAll('100x100bb', '600x600bb');
            }
          }
        }
      }
    } catch (_) {}

    // 3. Try Wikipedia OpenSearch / Page Image
    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=${Uri.encodeComponent("$name singer musician")}&gsrlimit=1&prop=pageimages&piprop=thumbnail|original&pithumbsize=500&format=json',
      );
      final resp = await http.get(uri, headers: {'User-Agent': 'MusicHub/1.0'}).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['query'] is Map && data['query']['pages'] is Map) {
          final pages = data['query']['pages'] as Map;
          for (final p in pages.values) {
            if (p is Map) {
              final orig = (p['original'] is Map) ? p['original']['source'] : null;
              final thumb = (p['thumbnail'] is Map) ? p['thumbnail']['source'] : null;
              final source = orig ?? thumb;
              if (source is String && source.isNotEmpty) {
                return source;
              }
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }
}

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    required this.label,
    this.radius = 22,
    this.fit = BoxFit.cover,
    this.cacheKey,
    this.debugKind = 'artwork',
    this.autoFetchArtistPhoto = true,
  });
  final String url, label;
  final String? cacheKey;
  final String debugKind;
  final double radius;
  final BoxFit fit;
  final bool autoFetchArtistPhoto;

  @override
  Widget build(BuildContext context) {
    final cachedPhoto = ArtistPhotoResolver.getCached(label);
    final effectiveUrl = url.isNotEmpty ? url : (cachedPhoto ?? '');

    if (effectiveUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: _tone(label),
          child: CachedNetworkImage(
            imageUrl: upgradeImageUrlQuality(effectiveUrl),
            cacheKey: cacheKey,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            fadeInDuration: const Duration(milliseconds: 220),
            progressIndicatorBuilder: (_, _, progress) => Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.progress,
              ),
            ),
            errorWidget: (_, _, error) => _buildFallback(label),
          ),
        ),
      );
    }

    if (autoFetchArtistPhoto && label.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: _tone(label),
          child: FutureBuilder<String?>(
            future: ArtistPhotoResolver.resolve(label),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                return CachedNetworkImage(
                  imageUrl: upgradeImageUrlQuality(snapshot.data!),
                  cacheKey: cacheKey,
                  fit: fit,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: const Duration(milliseconds: 220),
                  errorWidget: (_, _, _) => _buildFallback(label),
                );
              }
              return _buildFallback(label);
            },
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: _tone(label),
        child: _buildFallback(label),
      ),
    );
  }

  Widget _buildFallback(String seed) => Center(
    child: Text(
      seed.isEmpty ? '♪' : seed.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: readableTextColor(_tone(seed)),
      ),
    ),
  );
}

Color _tone(String seed) {
  const tones = [
    AppColors.blush,
    AppColors.lavender,
    Color(0xFFDCE9E2),
    Color(0xFFECE7D2),
    Color(0xFFE1E6ED),
  ];
  return tones[seed.codeUnits.fold(0, (a, b) => a + b) % tones.length];
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.state,
    required this.queue,
    this.dark = false,
    this.showFavorite = true,
    this.showDelete = false,
  });
  final Track track;
  final AppState state;
  final List<Track> queue;
  final bool dark, showFavorite, showDelete;

  @override
  Widget build(BuildContext context) {
    final favored = state.isFavorite(track);
    return ListTile(
      key: ValueKey(track.seokey.isNotEmpty ? track.seokey : track.trackId),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
      leading: SizedBox.square(
        dimension: 54,
        child: Artwork(url: track.imageUrl, label: track.title, radius: 14),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: dark ? Theme.of(context).colorScheme.onInverseSurface : null,
        ),
      ),
      subtitle: Text(
        track.artist.isEmpty ? track.album : track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: dark
              ? Theme.of(context).colorScheme.onInverseSurface
                    .withValues(alpha: .65)
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDelete)
            IconButton(
              iconSize: 22,
              tooltip: 'Delete downloaded song',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
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
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await state.deleteDownloadedTrack(track);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed "${track.title}" from offline downloads'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
            )
          else
            DownloadIndicator(track: track, state: state),
          if (showFavorite)
            IconButton(
              onPressed: () => state.toggleFavorite(track),
              icon: Icon(
                favored ? Icons.favorite : Icons.favorite_border,
                color: favored
                    ? Theme.of(context).colorScheme.primary
                    : (dark ? Theme.of(context).colorScheme.onInverseSurface : null),
              ),
            )
          else
            const Icon(Icons.play_arrow_rounded),
        ],
      ),
      onTap: () => state.play(track, queue),
    );
  }
}

class DownloadIndicator extends StatelessWidget {
  const DownloadIndicator({
    super.key,
    required this.track,
    required this.state,
    this.interactive = true,
  });
  final Track track;
  final AppState state;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.downloads,
      builder: (context, _) {
        final id = track.seokey.isNotEmpty ? track.seokey : track.id;
        final isDownloaded = state.downloads.isDownloaded(track.seokey) ||
            (track.id.isNotEmpty && state.downloads.isDownloaded(track.id)) ||
            (track.trackId.isNotEmpty && state.downloads.isDownloaded(track.trackId));
        final entry = state.downloads.entryFor(track.seokey) ??
            (track.id.isNotEmpty ? state.downloads.entryFor(track.id) : null) ??
            (track.trackId.isNotEmpty ? state.downloads.entryFor(track.trackId) : null);
        final isDownloading = entry?.status == DownloadStatus.downloading ||
            entry?.status == DownloadStatus.queued;
        final isFailed = entry?.status == DownloadStatus.failed;

        if (isDownloading) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: entry?.progress,
                strokeWidth: 2,
                color: AppColors.orange,
              ),
            ),
          );
        }

        if (isDownloaded) {
          if (!interactive) {
            return const Icon(
              Icons.download_done_rounded,
              size: 18,
              color: AppColors.orange,
            );
          }
          return IconButton(
            iconSize: 20,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Downloaded (Tap to delete)',
            icon: const Icon(
              Icons.download_done_rounded,
              color: AppColors.orange,
            ),
            onPressed: () async {
              final ok = await showDialog<bool>(
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
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await state.deleteDownloadedTrack(track);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed "${track.title}" from downloads'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          );
        }

        if (isFailed) {
          return IconButton(
            iconSize: 20,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Download failed (Tap to retry)',
            icon: const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
            ),
            onPressed: () => state.downloads.retry(id),
          );
        }

        if (!interactive) return const SizedBox(width: 8);

        return IconButton(
          iconSize: 20,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(),
          tooltip: 'Download offline',
          icon: Icon(
            Icons.download_for_offline_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          onPressed: () async {
            await state.downloadTrack(track);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Downloading "${track.title}" offline...'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        );
      },
    );
  }
}

class CollectionCard extends StatelessWidget {
  const CollectionCard({super.key, required this.item, required this.onTap});
  final CollectionItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(26),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Artwork(url: item.imageUrl, label: item.title, radius: 18),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            item.language.isEmpty ? 'Curated playlist' : item.language,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.state, this.onOpen});
  final AppState state;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.player,
      builder: (context, _) {
        final track = state.player.current;
        if (track == null) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen ?? () => unawaited(openFullPlayer(context, state)),
          child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 46,
              child: Artwork(
                url: track.imageUrl,
                label: track.title,
                radius: 14,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface
                          .withValues(alpha: .65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: state.player.previous,
              color: Theme.of(context).colorScheme.onInverseSurface,
              icon: const Icon(Icons.skip_previous_rounded, size: 24),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: state.player.toggle,
              color: Theme.of(context).colorScheme.onInverseSurface,
              icon: Icon(
                state.player.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 28,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: state.player.next,
              color: Theme.of(context).colorScheme.onInverseSurface,
              icon: const Icon(Icons.skip_next_rounded, size: 24),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.inverted = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool inverted, busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 58,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: inverted
            ? Theme.of(context).colorScheme.surface
            : AppColors.orange,
        foregroundColor: inverted
            ? Theme.of(context).colorScheme.onSurface
            : readableTextColor(AppColors.orange),
        shape: const StadiumBorder(),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
}
