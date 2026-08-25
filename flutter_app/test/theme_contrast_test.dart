import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/app/theme.dart';

/// WCAG relative luminance, used to check that foreground and background are
/// actually far enough apart rather than merely different values.
double _luminance(Color color) {
  double channel(double component) {
    return component <= 0.03928
        ? component / 12.92
        : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color foreground, Color background) {
  final a = _luminance(foreground);
  final b = _luminance(background);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final light = AppTheme.light;
  final dark = AppTheme.dark;

  test('the dark theme carries its own palette rather than the light one', () {
    expect(light.extension<AppPalette>(), isNotNull);
    expect(dark.extension<AppPalette>(), isNotNull);
    expect(
      dark.extension<AppPalette>()!.ink,
      isNot(light.extension<AppPalette>()!.ink),
    );
  });

  test('body text reads against the scaffold in both themes', () {
    for (final theme in [light, dark]) {
      final background = theme.scaffoldBackgroundColor;
      for (final style in [
        theme.textTheme.bodyMedium,
        theme.textTheme.bodyLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.headlineLarge,
      ]) {
        expect(style?.color, isNotNull);
        expect(
          _contrast(style!.color!, background),
          greaterThan(4.5),
          reason: '${theme.brightness} text on the scaffold background',
        );
      }
    }
  });

  test('secondary text stays legible on the scaffold in both themes', () {
    for (final theme in [light, dark]) {
      final palette = theme.extension<AppPalette>()!;
      expect(
        _contrast(palette.muted, theme.scaffoldBackgroundColor),
        greaterThan(3.0),
        reason: '${theme.brightness} muted text',
      );
    }
  });

  test('navigation bar labels read against the bar itself', () {
    for (final theme in [light, dark]) {
      final palette = theme.extension<AppPalette>()!;
      expect(
        _contrast(palette.onNavBar, palette.navBar),
        greaterThan(4.5),
        reason: '${theme.brightness} navigation bar',
      );
    }
  });

  test('tile foreground reads on every decorative panel', () {
    for (final theme in [light, dark]) {
      final palette = theme.extension<AppPalette>()!;
      for (final tile in [
        palette.peach,
        palette.blue,
        palette.lilac,
        palette.mint,
      ]) {
        expect(
          _contrast(palette.onTile, tile),
          greaterThan(4.5),
          reason: '${theme.brightness} text on a decorative panel',
        );
      }
    }
  });

  test('filled buttons keep their label readable', () {
    for (final theme in [light, dark]) {
      expect(
        _contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
        greaterThan(4.5),
        reason: '${theme.brightness} filled button',
      );
    }
  });
}
