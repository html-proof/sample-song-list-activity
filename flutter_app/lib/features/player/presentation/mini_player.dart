import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/downloads/data/download_repository.dart';
import 'package:music_hub_app/features/downloads/presentation/downloads_screen.dart';
import 'package:music_hub_app/features/home/presentation/home_controller.dart';
import 'package:music_hub_app/features/library/presentation/library_controller.dart';
import 'package:music_hub_app/features/player/presentation/player_palette.dart';
import 'package:music_hub_app/features/player/presentation/player_providers.dart';
import 'package:music_hub_app/features/player/presentation/player_screen.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();
    final state = ref.watch(playbackStateProvider).value;
    final progressState =
        ref.watch(playerProgressProvider).valueOrNull ??
        ref.read(audioHandlerProvider).currentProgress;
    final position = progressState.position;
    final playing = state?.playing == true;
    final duration = progressState.duration ?? item.duration;
    final progress = duration == null || duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final buffering =
        state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;
    final palette =
        ref.watch(playerPaletteProvider(item.artUri?.toString())).valueOrNull ??
        PlayerPalette.fallback;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 260) return;
        HapticFeedback.selectionClick();
        velocity < 0
            ? ref.read(audioHandlerProvider).skipToNext()
            : ref.read(audioHandlerProvider).skipToPrevious();
      },
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -260) context.push('/player');
      },
      onLongPress: () => _showQuickActions(context, ref, item),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(23),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/player'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 68,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Hero(
                      tag: 'now-playing-${item.id}',
                      child: Artwork(
                        url: item.artUri?.toString(),
                        size: 50,
                        radius: 13,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            item.artist ?? 'Music Hub',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: playing ? 'Pause' : 'Play',
                      color: palette.background,
                      style: IconButton.styleFrom(
                        backgroundColor: palette.primary,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        playing
                            ? ref.read(audioHandlerProvider).pause()
                            : ref.read(audioHandlerProvider).play();
                      },
                      icon: SizedBox.square(
                        dimension: 24,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (buffering)
                              const CircularProgressIndicator(strokeWidth: 2),
                            Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      color: Colors.white70,
                      onPressed: ref.read(audioHandlerProvider).skipToNext,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                color: palette.primary,
                backgroundColor: Colors.white12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickActions(
    BuildContext context,
    WidgetRef ref,
    MediaItem media,
  ) async {
    final music = _musicFrom(media);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.favorite_border_rounded),
              title: const Text('Like'),
              enabled: music != null,
              onTap: music == null
                  ? null
                  : () async {
                      Navigator.pop(sheetContext);
                      await ref.read(libraryRepositoryProvider).like(music);
                      ref.invalidate(libraryControllerProvider);
                      await ref
                          .read(homeControllerProvider.notifier)
                          .load(refresh: true);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Open queue'),
              onTap: () {
                Navigator.pop(sheetContext);
                showPlayerQueue(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Download'),
              enabled: music != null,
              onTap: music == null
                  ? null
                  : () async {
                      Navigator.pop(sheetContext);
                      await _download(context, ref, music);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

MusicItem? _musicFrom(MediaItem media) {
  final raw = media.extras?['raw'];
  return raw is Map ? MusicItem.fromJson(raw.cast<String, dynamic>()) : null;
}

Future<void> _download(
  BuildContext context,
  WidgetRef ref,
  MusicItem item,
) async {
  try {
    await ref.read(downloadRepositoryProvider).download(item, (_) {});
    ref.read(downloadsRevisionProvider.notifier).state++;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved for offline listening')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }
}
