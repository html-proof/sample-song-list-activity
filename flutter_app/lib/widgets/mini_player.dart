import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme/app_theme.dart';

class MiniPlayer extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final VoidCallback onTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const MiniPlayer({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onTap,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.playerBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: track.imageUrl,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppColors.secondary),
                errorWidget: (_, _, _) => Container(
                  color: AppColors.secondary,
                  child: const Icon(Icons.music_note, color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    track.artist,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onPrevious != null)
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 24),
                onPressed: onPrevious,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
              onPressed: onTogglePlay,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            if (onNext != null)
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
                onPressed: onNext,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
          ],
        ),
      ),
    );
  }
}

