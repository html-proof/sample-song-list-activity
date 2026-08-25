import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/downloads/data/download_repository.dart';
import 'package:music_hub_app/features/downloads/presentation/downloads_screen.dart';
import 'package:music_hub_app/features/home/presentation/home_controller.dart';
import 'package:music_hub_app/features/library/presentation/library_controller.dart';
import 'package:music_hub_app/features/player/presentation/player_palette.dart';
import 'package:music_hub_app/features/player/presentation/player_providers.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(currentMediaItemProvider).value;
    final playback = ref.watch(playbackStateProvider).value;
    final progress =
        ref.watch(playerProgressProvider).valueOrNull ??
        ref.read(audioHandlerProvider).currentProgress;
    final position = progress.position;
    if (media == null) {
      return Scaffold(
        backgroundColor: PlayerPalette.fallback.background,
        body: const Center(
          child: Text(
            'Choose a song to start listening',
            style: TextStyle(color: PlayerPalette.onSurfaceVariant),
          ),
        ),
      );
    }

    final palette =
        ref
            .watch(playerPaletteProvider(media.artUri?.toString()))
            .valueOrNull ??
        PlayerPalette.fallback;
    final duration = progress.duration ?? media.duration;
    final playing = playback?.playing == true;
    final music = _toMusicItem(media);
    final error = playback?.processingState == AudioProcessingState.error
        ? playback?.errorMessage
        : null;

    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.primary,
          brightness: Brightness.dark,
          surface: palette.surface,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: palette.primary,
          inactiveTrackColor: PlayerPalette.onSurfaceFaint,
          thumbColor: palette.primary,
          overlayColor: palette.primary.withValues(alpha: 0.16),
          trackHeight: 3,
        ),
      ),
      child: Scaffold(
        backgroundColor: palette.background,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 420) return;
            velocity < 0 ? _next() : _previous();
          },
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -420) showPlayerQueue(context);
            if (velocity > 420) Navigator.maybePop(context);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PlayerBackdrop(palette: palette, animation: _motion),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 34),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 40),
                      ),
                      child: Column(
                        children: [
                          _PlayerHeader(
                            onQueue: () => showPlayerQueue(context),
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 10),
                            _PlaybackError(message: error),
                          ],
                          const SizedBox(height: 18),
                          _ArtworkStage(
                            media: media,
                            playing: playing,
                            palette: palette,
                            maxWidth: constraints.maxWidth,
                          ),
                          const SizedBox(height: 25),
                          Text(
                            media.title,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PlayerPalette.onSurface,
                              fontSize: 27,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            [media.artist, media.album]
                                .whereType<String>()
                                .where((value) => value.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PlayerPalette.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _SeekBar(
                            position: position,
                            buffered: progress.buffered,
                            duration: duration,
                            onSeek: ref.read(audioHandlerProvider).seek,
                          ),
                          const SizedBox(height: 12),
                          _TransportControls(
                            playing: playing,
                            playback: playback,
                            palette: palette,
                            onPrevious: _previous,
                            onToggle: () => _toggle(playing),
                            onNext: _next,
                          ),
                          const SizedBox(height: 26),
                          _SecondaryActions(
                            music: music,
                            palette: palette,
                            onQueue: () => showPlayerQueue(context),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Swipe sideways to skip · swipe up for queue',
                            style: TextStyle(
                              color: PlayerPalette.onSurfaceVariant.withValues(
                                alpha: 0.62,
                              ),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  MusicItem? _toMusicItem(MediaItem media) {
    final raw = media.extras?['raw'];
    return raw is Map ? MusicItem.fromJson(raw.cast<String, dynamic>()) : null;
  }

  void _toggle(bool playing) {
    HapticFeedback.mediumImpact();
    playing
        ? ref.read(audioHandlerProvider).pause()
        : ref.read(audioHandlerProvider).play();
  }

  void _next() {
    HapticFeedback.selectionClick();
    ref.read(audioHandlerProvider).skipToNext();
  }

  void _previous() {
    HapticFeedback.selectionClick();
    ref.read(audioHandlerProvider).skipToPrevious();
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration buffered;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  Duration? _preview;

  @override
  void didUpdateWidget(covariant _SeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _preview = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration;
    final durationMs = duration?.inMilliseconds ?? 0;
    final shownPosition = _preview ?? widget.position;
    final positionMs = durationMs == 0
        ? 0
        : shownPosition.inMilliseconds.clamp(0, durationMs);
    final bufferedFraction = durationMs == 0
        ? 0.0
        : (widget.buffered.inMilliseconds / durationMs).clamp(0.0, 1.0);
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LinearProgressIndicator(
                value: bufferedFraction,
                minHeight: 3,
                color: PlayerPalette.onSurfaceFaint,
                backgroundColor: PlayerPalette.onSurfaceFaint.withValues(
                  alpha: 0.28,
                ),
              ),
            ),
            Slider(
              value: positionMs.toDouble(),
              max: durationMs == 0 ? 1 : durationMs.toDouble(),
              onChanged: durationMs == 0
                  ? null
                  : (value) => setState(
                      () => _preview = Duration(milliseconds: value.round()),
                    ),
              onChangeEnd: durationMs == 0
                  ? null
                  : (value) {
                      final target = Duration(milliseconds: value.round());
                      setState(() => _preview = null);
                      widget.onSeek(target);
                    },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(durationMs == 0 ? '--:--' : _time(shownPosition)),
              Text(
                durationMs == 0
                    ? '--:--'
                    : '-${_remaining(shownPosition, duration!)}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.onQueue});

  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filledTonal(
        tooltip: 'Close player',
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
      ),
      const Expanded(
        child: Column(
          children: [
            Text(
              'NOW PLAYING',
              style: TextStyle(
                color: PlayerPalette.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: 2.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Resonance',
              style: TextStyle(
                color: PlayerPalette.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: 'Queue',
        onPressed: onQueue,
        icon: const Icon(Icons.queue_music_rounded),
      ),
    ],
  );
}

class _ArtworkStage extends StatelessWidget {
  const _ArtworkStage({
    required this.media,
    required this.playing,
    required this.palette,
    required this.maxWidth,
  });

  final MediaItem media;
  final bool playing;
  final PlayerPalette palette;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final size = (maxWidth - 58).clamp(230.0, 430.0);
    return AnimatedScale(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      scale: playing ? 1 : 0.94,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: palette.primary.withValues(alpha: playing ? 0.30 : 0.16),
              blurRadius: playing ? 58 : 32,
              spreadRadius: playing ? 4 : 0,
            ),
          ],
        ),
        child: Hero(
          tag: 'now-playing-${media.id}',
          child: Artwork(url: media.artUri?.toString(), size: size, radius: 32),
        ),
      ),
    );
  }
}

class _TransportControls extends ConsumerWidget {
  const _TransportControls({
    required this.playing,
    required this.playback,
    required this.palette,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final bool playing;
  final PlaybackState? playback;
  final PlayerPalette palette;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buffering =
        playback?.processingState == AudioProcessingState.loading ||
        playback?.processingState == AudioProcessingState.buffering;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Shuffle',
          color: playback?.shuffleMode == AudioServiceShuffleMode.all
              ? palette.primary
              : PlayerPalette.onSurfaceVariant,
          onPressed: () => ref
              .read(audioHandlerProvider)
              .setShuffle(playback?.shuffleMode != AudioServiceShuffleMode.all),
          icon: const Icon(Icons.shuffle_rounded),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 42,
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        FilledButton(
          onPressed: onToggle,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: palette.primary,
            foregroundColor: palette.background,
            padding: const EdgeInsets.all(19),
            elevation: 8,
            shadowColor: palette.primary.withValues(alpha: 0.35),
          ),
          child: SizedBox.square(
            dimension: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (buffering)
                  const SizedBox.square(
                    dimension: 42,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 34,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          iconSize: 42,
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: 'Repeat',
          color: playback?.repeatMode != AudioServiceRepeatMode.none
              ? palette.primary
              : PlayerPalette.onSurfaceVariant,
          onPressed: ref.read(audioHandlerProvider).cycleRepeat,
          icon: Icon(
            playback?.repeatMode == AudioServiceRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
        ),
      ],
    );
  }
}

class _SecondaryActions extends ConsumerWidget {
  const _SecondaryActions({
    required this.music,
    required this.palette,
    required this.onQueue,
  });

  final MusicItem? music;
  final PlayerPalette palette;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF000000).withValues(alpha: 0.17),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: PlayerPalette.onSurfaceFaint.withValues(alpha: 0.24),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SmallAction(
          icon: Icons.favorite_border_rounded,
          label: 'Like',
          onTap: music == null
              ? null
              : () async {
                  HapticFeedback.selectionClick();
                  await ref.read(libraryRepositoryProvider).like(music!);
                  ref.invalidate(libraryControllerProvider);
                  await ref
                      .read(homeControllerProvider.notifier)
                      .load(refresh: true);
                  if (context.mounted) {
                    _message(context, 'Added to Liked songs');
                  }
                },
        ),
        _SmallAction(
          icon: Icons.lyrics_outlined,
          label: 'Lyrics',
          onTap: () =>
              _message(context, 'Lyrics are not available for this track'),
        ),
        _SmallAction(
          icon: Icons.queue_music_rounded,
          label: 'Queue',
          onTap: onQueue,
        ),
        _SmallAction(
          icon: Icons.speaker_group_outlined,
          label: 'Device',
          onTap: () => _message(context, 'Playing on this device'),
        ),
        _SmallAction(
          icon: Icons.download_rounded,
          label: 'Save',
          onTap: music == null ? null : () => _save(context, ref, music!),
        ),
      ],
    ),
  );

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    MusicItem item,
  ) async {
    try {
      await ref.read(downloadRepositoryProvider).download(item, (_) {});
      ref.read(downloadsRevisionProvider.notifier).state++;
      if (context.mounted) _message(context, 'Saved for offline listening');
    } catch (error) {
      if (context.mounted) {
        _message(context, error.toString().replaceFirst('Bad state: ', ''));
      }
    }
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 28,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Column(
        children: [
          Icon(
            icon,
            size: 21,
            color: onTap == null ? PlayerPalette.onSurfaceFaint : null,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? PlayerPalette.onSurfaceFaint
                  : PlayerPalette.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlayerBackdrop extends StatelessWidget {
  const _PlayerBackdrop({required this.palette, required this.animation});

  final PlayerPalette palette;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final value = Curves.easeInOut.transform(animation.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.65 + value * 1.2, -0.85 + value * 0.25),
            radius: 1.25,
            colors: [
              palette.primary.withValues(alpha: 0.24),
              palette.secondary.withValues(alpha: 0.09),
              palette.background,
            ],
            stops: const [0, 0.46, 1],
          ),
        ),
      );
    },
  );
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 19),
        const SizedBox(width: 9),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

Future<void> showPlayerQueue(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12141A),
      showDragHandle: true,
      builder: (_) =>
          const FractionallySizedBox(heightFactor: 0.78, child: _PlayerQueue()),
    );

class _PlayerQueue extends ConsumerWidget {
  const _PlayerQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(playerQueueProvider).value ?? const <MediaItem>[];
    final handler = ref.watch(audioHandlerProvider);
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Playing next',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Hold and drag to reorder',
                        style: TextStyle(
                          color: PlayerPalette.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text('${items.length} tracks'),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Your queue is empty'))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: items.length,
                    onReorderItem: handler.reorder,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final current = index == handler.currentIndex;
                      return ListTile(
                        key: ValueKey('${item.id}-$index'),
                        selected: current,
                        selectedTileColor: PlayerPalette.onSurface.withValues(
                          alpha: 0.07,
                        ),
                        leading: Stack(
                          children: [
                            Artwork(url: item.artUri?.toString(), size: 48),
                            if (current)
                              const Positioned.fill(
                                child: ColoredBox(
                                  color: Color(0x66000000),
                                  child: Icon(Icons.graphic_eq_rounded),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          current ? 'PLAYING' : item.artist ?? '',
                          maxLines: 1,
                          style: TextStyle(
                            color: current
                                ? null
                                : PlayerPalette.onSurfaceVariant,
                            fontSize: current ? 10 : 12,
                            letterSpacing: current ? 1.4 : 0,
                          ),
                        ),
                        onTap: () => handler.skipToQueueItem(index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => handler.removeQueueItemAt(index),
                            ),
                            const Icon(Icons.drag_handle_rounded),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _time(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _remaining(Duration position, Duration duration) {
  final remaining = duration - position;
  return _time(remaining.isNegative ? Duration.zero : remaining);
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
