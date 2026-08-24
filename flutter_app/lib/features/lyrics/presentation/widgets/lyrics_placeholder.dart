import 'package:flutter/material.dart';

class LyricsPlaceholder extends StatelessWidget {
  const LyricsPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 44),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}

class LyricsSkeleton extends StatelessWidget {
  const LyricsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 70, 26, 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        6,
        (index) => Container(
          width: index.isEven ? double.infinity : 240,
          height: index == 2 ? 30 : 22,
          margin: const EdgeInsets.only(bottom: 25),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: index == 2 ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    ),
  );
}
