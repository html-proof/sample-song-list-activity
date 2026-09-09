import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme/app_theme.dart';

class NowPlayingScreen extends StatefulWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToggleRepeat;
  final VoidCallback? onToggleShuffle;
  final ValueChanged<Duration>? onSeek;
  final PlaybackRepeatMode repeatMode;
  final bool isShuffled;

  const NowPlayingScreen({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.onTogglePlay,
    this.onPrevious,
    this.onNext,
    this.onToggleRepeat,
    this.onToggleShuffle,
    this.onSeek,
    this.repeatMode = PlaybackRepeatMode.off,
    this.isShuffled = false,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isPlaying = false;
  double _sliderValue = 0.0;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.isPlaying;
    _repeatMode = widget.repeatMode;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant NowPlayingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.seokey != widget.track.seokey ||
        oldWidget.track.title != widget.track.title) {
      setState(() {
        _sliderValue = 0.0;
        _isPlaying = widget.isPlaying;
        _repeatMode = widget.repeatMode;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final totalSeconds = track.durationSeconds > 0 ? track.durationSeconds.toDouble() : 180.0;
    final currentSeconds = _sliderValue * totalSeconds;
    final currentDuration = Duration(seconds: currentSeconds.toInt());

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            const SizedBox(height: 24),
            _buildAlbumArt(track),
            const SizedBox(height: 28),
            _buildTrackInfo(track),
            const SizedBox(height: 24),
            _buildProgressBar(currentDuration, Duration(seconds: totalSeconds.toInt()), totalSeconds),
            const SizedBox(height: 24),
            _buildControls(),
            const SizedBox(height: 24),
            _buildLyricsPreview(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          ),
          const Spacer(),
          Column(
            children: [
              const Text(
                'Now Playing',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                widget.track.album.isNotEmpty ? widget.track.album : 'Music Hub',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.more_horiz_rounded, size: 24),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(Track track) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = _isPlaying
            ? 1.0 + (_pulseController.value * 0.04)
            : 1.0;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(140),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipOval(
          child: track.imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: track.imageUrl,
                  width: 280,
                  height: 280,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    width: 280,
                    height: 280,
                    color: AppColors.surfaceCard,
                    child: const Icon(Icons.music_note, color: AppColors.muted, size: 60),
                  ),
                )
              : Container(
                  width: 280,
                  height: 280,
                  color: AppColors.surfaceCard,
                  child: const Icon(Icons.music_note, color: AppColors.muted, size: 60),
                ),
        ),
      ),
    );
  }

  Widget _buildTrackInfo(Track track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border_rounded, size: 26),
            onPressed: () {},
            color: AppColors.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    Duration current,
    Duration total,
    double totalSeconds,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.divider,
              thumbColor: AppColors.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 3,
            ),
            child: Slider(
              value: _sliderValue.clamp(0.0, 1.0),
              onChanged: (v) => setState(() => _sliderValue = v),
              onChangeEnd: (v) {
                final targetMs = (v * (total.inMilliseconds > 0 ? total.inMilliseconds : totalSeconds * 1000)).round();
                widget.onSeek?.call(Duration(milliseconds: targetMs));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(current),
                  style: const TextStyle(fontSize: 12, color: AppColors.secondary),
                ),
                Text(
                  _formatDuration(total),
                  style: const TextStyle(fontSize: 12, color: AppColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              _repeatMode == PlaybackRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              size: 24,
              color: _repeatMode != PlaybackRepeatMode.off ? AppColors.primary : AppColors.muted,
            ),
            onPressed: () {
              setState(() {
                _repeatMode = switch (_repeatMode) {
                  PlaybackRepeatMode.off => PlaybackRepeatMode.all,
                  PlaybackRepeatMode.all => PlaybackRepeatMode.one,
                  PlaybackRepeatMode.one => PlaybackRepeatMode.off,
                };
              });
              widget.onToggleRepeat?.call();
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded, size: 38),
            onPressed: widget.onPrevious,
            color: AppColors.primary,
          ),
          GestureDetector(
            onTap: () {
              setState(() => _isPlaying = !_isPlaying);
              widget.onTogglePlay();
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded, size: 38),
            onPressed: widget.onNext,
            color: AppColors.primary,
          ),
          IconButton(
            icon: Icon(
              Icons.shuffle_rounded,
              size: 24,
              color: widget.isShuffled ? AppColors.primary : AppColors.muted,
            ),
            onPressed: () {
              widget.onToggleShuffle?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Lyrics',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const Icon(Icons.open_in_full_rounded, size: 18, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 10),
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 13, color: AppColors.secondary, height: 1.6),
              children: [
                TextSpan(text: 'Midnight roads and neon skies, '),
                TextSpan(
                  text: 'City glowing in your eyes, ',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
                TextSpan(text: 'Every step, a silent fight, '),
                TextSpan(text: 'Ancing shadows in the light...'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

