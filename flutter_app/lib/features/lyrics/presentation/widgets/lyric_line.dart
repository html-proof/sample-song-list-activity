import 'package:flutter/material.dart';

class LyricLineTile extends StatelessWidget {
  const LyricLineTile({
    super.key,
    required this.text,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String text;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    label: active ? 'Current lyric: $text' : text,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.13) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.43),
            fontSize: active ? 25 : 20,
            height: 1.18,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: active ? -0.5 : -0.2,
          ),
          child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ),
    ),
  );
}
