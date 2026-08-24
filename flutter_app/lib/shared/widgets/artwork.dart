import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:music_hub_app/app/theme.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    this.url,
    this.size = 56,
    this.radius = 12,
    this.round = false,
  });

  final String? url;
  final double size;
  final double radius;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(round ? size / 2 : radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: size,
        height: size,
        color: AppTheme.surfaceHigh,
        child: url?.isNotEmpty == true
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                errorWidget: (_, _, _) => const Icon(Icons.music_note_rounded),
              )
            : const Icon(Icons.music_note_rounded, color: AppTheme.muted),
      ),
    );
  }
}

class OrganicArtwork extends StatelessWidget {
  const OrganicArtwork({
    super.key,
    this.url,
    this.size = 180,
    this.variant = 0,
  });

  final String? url;
  final double size;
  final int variant;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _OrganicClipper(variant),
      child: Artwork(url: url, size: size, radius: 0),
    );
  }
}

class _OrganicClipper extends CustomClipper<Path> {
  const _OrganicClipper(this.variant);

  final int variant;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final shift = (variant % 3) * 0.035;
    return Path()
      ..moveTo(w * (0.18 + shift), h * 0.04)
      ..cubicTo(w * 0.42, -h * 0.02, w * 0.72, h * 0.02, w * 0.88, h * 0.18)
      ..cubicTo(w * 1.04, h * 0.35, w * 0.96, h * 0.60, w * 0.88, h * 0.82)
      ..cubicTo(w * 0.72, h * 1.02, w * 0.42, h * 0.98, w * 0.18, h * 0.91)
      ..cubicTo(-w * 0.02, h * 0.80, w * 0.02, h * 0.56, w * 0.04, h * 0.35)
      ..cubicTo(
        w * 0.04,
        h * 0.18,
        w * 0.08,
        h * 0.09,
        w * (0.18 + shift),
        h * 0.04,
      )
      ..close();
  }

  @override
  bool shouldReclip(covariant _OrganicClipper oldClipper) =>
      oldClipper.variant != variant;
}
