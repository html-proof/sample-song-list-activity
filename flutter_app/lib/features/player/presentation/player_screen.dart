import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/library/presentation/library_controller.dart';
import 'package:music_hub_app/features/player/presentation/player_providers.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(currentMediaItemProvider).value;
    final playback = ref.watch(playbackStateProvider).value;
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    if (media == null) {
      return const Scaffold(
        body: Center(child: Text('Choose a song to start listening')),
      );
    }
    final duration = media.duration ?? Duration.zero;
    final playing = playback?.playing == true;
    final music = _toMusicItem(media);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton.filledTonal(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        title: const Text('Current track', style: TextStyle(fontSize: 15)),
        centerTitle: true,
        actions: [
          IconButton.filledTonal(
            tooltip: 'Like song',
            onPressed: music == null
                ? null
                : () async {
                    await ref.read(libraryRepositoryProvider).like(music);
                    ref.invalidate(libraryControllerProvider);
                  },
            icon: const Icon(Icons.favorite_border_rounded),
          ),
          IconButton(
            tooltip: 'Queue',
            onPressed: () => _showQueue(context),
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artSize = (constraints.maxWidth - 56).clamp(220.0, 440.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 36),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${_time(position)}  |  ${_time(duration)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: artSize,
                    height: artSize,
                    padding: EdgeInsets.all(artSize * 0.045),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(artSize * 0.28),
                        topRight: Radius.circular(artSize * 0.16),
                        bottomLeft: Radius.circular(artSize * 0.18),
                        bottomRight: Radius.circular(artSize * 0.30),
                      ),
                      border: Border.all(
                        color: AppTheme.ink.withValues(alpha: 0.20),
                      ),
                    ),
                    child: OrganicArtwork(
                      url: media.artUri?.toString(),
                      size: artSize * 0.91,
                      variant: 2,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    media.title.toUpperCase(),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    media.artist ?? 'Music Hub',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 18),
                  Slider(
                    value: duration.inMilliseconds == 0
                        ? 0
                        : position.inMilliseconds
                              .clamp(0, duration.inMilliseconds)
                              .toDouble(),
                    max: duration.inMilliseconds == 0
                        ? 1
                        : duration.inMilliseconds.toDouble(),
                    onChanged: duration.inMilliseconds == 0
                        ? null
                        : (value) => ref
                              .read(audioHandlerProvider)
                              .seek(Duration(milliseconds: value.round())),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _time(position),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _time(duration),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        onPressed: () => ref
                            .read(audioHandlerProvider)
                            .setShuffle(
                              playback?.shuffleMode !=
                                  AudioServiceShuffleMode.all,
                            ),
                        color:
                            playback?.shuffleMode == AudioServiceShuffleMode.all
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        icon: const Icon(Icons.shuffle_rounded),
                      ),
                      IconButton.filledTonal(
                        iconSize: 38,
                        tooltip: 'Previous',
                        onPressed: () {
                          if (music != null) {
                            ref
                                .read(eventTrackerProvider)
                                .track(
                                  'skip',
                                  music,
                                  source: 'player',
                                  positionMs: position.inMilliseconds,
                                );
                            ref
                                .read(eventTrackerProvider)
                                .recordListen(
                                  music,
                                  source: 'player',
                                  playedMs: position.inMilliseconds,
                                );
                          }
                          ref.read(audioHandlerProvider).skipToPrevious();
                        },
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      FilledButton(
                        onPressed: () {
                          if (playing && music != null) {
                            ref
                                .read(eventTrackerProvider)
                                .track(
                                  'pause',
                                  music,
                                  source: 'player',
                                  positionMs: position.inMilliseconds,
                                );
                            ref
                                .read(eventTrackerProvider)
                                .recordListen(
                                  music,
                                  source: 'player',
                                  playedMs: position.inMilliseconds,
                                );
                          }
                          playing
                              ? ref.read(audioHandlerProvider).pause()
                              : ref.read(audioHandlerProvider).play();
                        },
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(20),
                        ),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 40,
                        ),
                      ),
                      IconButton.filledTonal(
                        iconSize: 38,
                        tooltip: 'Next',
                        onPressed: () {
                          if (music != null) {
                            ref
                                .read(eventTrackerProvider)
                                .track(
                                  'skip',
                                  music,
                                  source: 'player',
                                  positionMs: position.inMilliseconds,
                                );
                            ref
                                .read(eventTrackerProvider)
                                .recordListen(
                                  music,
                                  source: 'player',
                                  playedMs: position.inMilliseconds,
                                );
                          }
                          ref.read(audioHandlerProvider).skipToNext();
                        },
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                      IconButton(
                        tooltip: 'Repeat',
                        onPressed: () =>
                            ref.read(audioHandlerProvider).cycleRepeat(),
                        color:
                            playback?.repeatMode != AudioServiceRepeatMode.none
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        icon: Icon(
                          playback?.repeatMode == AudioServiceRepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Track notes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Icon(Icons.open_in_full_rounded, size: 18),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${media.title} · ${media.artist ?? 'Music Hub'}\nA selection shaped by your listening profile.',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  MusicItem? _toMusicItem(MediaItem media) {
    final raw = media.extras?['raw'];
    return raw is Map ? MusicItem.fromJson(raw.cast<String, dynamic>()) : null;
  }

  String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          const FractionallySizedBox(heightFactor: 0.72, child: _PlayerQueue()),
    );
  }
}

class _PlayerQueue extends ConsumerWidget {
  const _PlayerQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(playerQueueProvider).value ?? const <MediaItem>[];
    final handler = ref.watch(audioHandlerProvider);
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Text(
                'Up next',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: items.length,
            onReorderItem: handler.reorder,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                key: ValueKey('${item.id}-$index'),
                selected: index == handler.currentIndex,
                leading: Artwork(url: item.artUri?.toString(), size: 48),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(item.artist ?? '', maxLines: 1),
                onTap: () => handler.skipToQueueItem(index),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => handler.removeQueueItemAt(index),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
