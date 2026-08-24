import 'package:flutter/material.dart';

class PlainLyrics extends StatelessWidget {
  const PlainLyrics({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 160),
    child: SelectableText(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.84),
        fontSize: 21,
        height: 1.65,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
