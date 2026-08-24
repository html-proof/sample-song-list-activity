class PlaybackProgress {
  const PlaybackProgress({
    required this.position,
    required this.buffered,
    required this.duration,
  });

  const PlaybackProgress.zero()
    : position = Duration.zero,
      buffered = Duration.zero,
      duration = null;

  final Duration position;
  final Duration buffered;
  final Duration? duration;
}
