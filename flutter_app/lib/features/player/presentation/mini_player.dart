import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/player/presentation/player_providers.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();
    final state = ref.watch(playbackStateProvider).value;
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final playing = state?.playing == true;
    final duration = item.duration ?? Duration.zero;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: () => context.push('/player'),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 66,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Artwork(url: item.artUri?.toString(), size: 48, radius: 13),
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
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: playing ? 'Pause' : 'Play',
                      color: Colors.black,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                      ),
                      onPressed: () => playing
                          ? ref.read(audioHandlerProvider).pause()
                          : ref.read(audioHandlerProvider).play(),
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close player',
                      color: Colors.white54,
                      onPressed: () =>
                          ref.read(audioHandlerProvider).clearQueue(),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  color: Colors.white,
                  backgroundColor: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
