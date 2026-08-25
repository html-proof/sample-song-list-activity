import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class PlayerPalette {
  const PlayerPalette({
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
  });

  /// The player is always a dark stage, whatever the system theme is doing,
  /// so it carries its own foreground pair instead of borrowing the app's
  /// `onSurface` — which would be near-black in light mode and vanish here.
  static const onSurface = Color(0xFFF6F5F3);
  static const onSurfaceVariant = Color(0xFFBFBDBA);

  /// Foreground for elements that are present but not the point: disabled
  /// transport controls, inactive track, hairline borders.
  static const onSurfaceFaint = Color(0xFF8A8886);

  static const fallback = PlayerPalette(
    background: Color(0xFF08090C),
    surface: Color(0xFF171A22),
    primary: Color(0xFF9CAEFF),
    secondary: Color(0xFFD7A6FF),
  );

  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
}

final playerPaletteProvider = FutureProvider.autoDispose
    .family<PlayerPalette, String?>((ref, artworkUrl) async {
      if (artworkUrl == null ||
          artworkUrl.isEmpty ||
          !artworkUrl.startsWith('http')) {
        return PlayerPalette.fallback;
      }
      try {
        final scheme = await ColorScheme.fromImageProvider(
          provider: NetworkImage(artworkUrl),
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          contrastLevel: 0.2,
        );
        final primary = _vivid(scheme.primary);
        final secondary = _vivid(scheme.tertiary);
        const black = Color(0xFF08090C);
        return PlayerPalette(
          background: Color.alphaBlend(primary.withValues(alpha: 0.18), black),
          surface: Color.alphaBlend(
            primary.withValues(alpha: 0.16),
            const Color(0xFF171A22),
          ),
          primary: primary,
          secondary: secondary,
        );
      } catch (_) {
        return PlayerPalette.fallback;
      }
    });

Color _vivid(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.42, 0.82))
      .withLightness(hsl.lightness.clamp(0.48, 0.72))
      .toColor();
}
