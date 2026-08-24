import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/lyrics/domain/entities/lyrics.dart';
import 'package:music_hub_app/features/lyrics/presentation/controllers/lyrics_controller.dart';
import 'package:music_hub_app/features/lyrics/presentation/widgets/lyrics_placeholder.dart';
import 'package:music_hub_app/features/lyrics/presentation/widgets/plain_lyrics.dart';
import 'package:music_hub_app/features/lyrics/presentation/widgets/synced_lyrics.dart';
import 'package:music_hub_app/features/player/presentation/player_palette.dart';
import 'package:music_hub_app/features/player/presentation/player_providers.dart';

Future<void> showLyricsView(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      const FractionallySizedBox(heightFactor: 0.96, child: LyricsView()),
);

class LyricsView extends ConsumerWidget {
  const LyricsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(currentMediaItemProvider).valueOrNull;
    final request = media == null ? null : lyricsRequestForMedia(media);
    final palette =
        ref
            .watch(playerPaletteProvider(media?.artUri?.toString()))
            .valueOrNull ??
        PlayerPalette.fallback;
    final state = request == null
        ? null
        : ref.watch(lyricsControllerProvider(request));

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: Material(
        color: palette.background,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.primary.withValues(alpha: 0.18),
                palette.background,
                Colors.black.withValues(alpha: 0.35),
              ],
            ),
          ),
          child: Column(
            children: [
              _LyricsHeader(media: media, palette: palette),
              Expanded(
                child: request == null || state == null
                    ? const LyricsPlaceholder(
                        icon: Icons.music_note_rounded,
                        title: 'Nothing playing',
                        message: 'Play a song to open its lyrics.',
                      )
                    : state.when(
                        loading: () => const LyricsSkeleton(),
                        error: (_, _) => LyricsPlaceholder(
                          icon: Icons.cloud_off_rounded,
                          title: 'Lyrics unavailable',
                          message:
                              'The song will keep playing. Try again shortly.',
                          onRetry: () => ref
                              .read(lyricsControllerProvider(request).notifier)
                              .load(force: true),
                        ),
                        data: (lyrics) => _LyricsContent(
                          key: ValueKey(
                            lyrics.songIdentityHash ?? request.identityKey,
                          ),
                          lyrics: lyrics,
                          palette: palette,
                          onRetry: () => ref
                              .read(lyricsControllerProvider(request).notifier)
                              .load(force: true),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsHeader extends StatelessWidget {
  const _LyricsHeader({required this.media, required this.palette});

  final MediaItem? media;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
    child: Column(
      children: [
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Icon(Icons.lyrics_rounded, color: palette.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LYRICS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    media?.title ?? 'Now playing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close lyrics',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LyricsContent extends StatelessWidget {
  const _LyricsContent({
    super.key,
    required this.lyrics,
    required this.palette,
    required this.onRetry,
  });

  final Lyrics lyrics;
  final PlayerPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final content = switch (lyrics.status) {
      LyricsStatus.available when lyrics.lines.isNotEmpty => SyncedLyrics(
        lyrics: lyrics,
        accent: palette.primary,
      ),
      LyricsStatus.plainOnly => PlainLyrics(text: lyrics.plainText ?? ''),
      LyricsStatus.instrumental => const LyricsPlaceholder(
        icon: Icons.music_note_rounded,
        title: '♪ Instrumental',
        message: 'Enjoy the music.',
      ),
      LyricsStatus.temporaryError => LyricsPlaceholder(
        icon: Icons.sync_problem_rounded,
        title: 'Lyrics are taking a break',
        message: 'Playback is unaffected. You can try again now.',
        onRetry: onRetry,
      ),
      LyricsStatus.offline => LyricsPlaceholder(
        icon: Icons.cloud_off_rounded,
        title: 'Lyrics unavailable offline',
        message: 'The song will keep playing. Reconnect and try again.',
        onRetry: onRetry,
      ),
      LyricsStatus.notFound => const LyricsPlaceholder(
        icon: Icons.lyrics_outlined,
        title: 'Lyrics unavailable',
        message: "Lyrics aren't available for this version.",
      ),
      LyricsStatus.unsupported => const LyricsPlaceholder(
        icon: Icons.lyrics_outlined,
        title: 'Lyrics coming soon',
        message: 'A licensed lyrics source has not been connected yet.',
      ),
      _ => const LyricsPlaceholder(
        icon: Icons.lyrics_outlined,
        title: 'Lyrics unavailable',
        message: "Lyrics aren't available for this song.",
      ),
    };
    if (!lyrics.synchronized) return content;
    return Stack(
      children: [
        Positioned.fill(child: content),
        const Positioned(left: 20, bottom: 18, child: _LyricsClock()),
      ],
    );
  }
}

class _LyricsClock extends ConsumerWidget {
  const _LyricsClock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        ref.watch(playerProgressProvider).valueOrNull ??
        ref.read(audioHandlerProvider).currentProgress;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            '${_time(progress.position)} / ${_time(progress.duration ?? Duration.zero)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

String _time(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
