import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/player/presentation/player_palette.dart';

/// WCAG relative luminance.
double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// Contrast ratio between a foreground and the background it sits on.
/// Translucent foregrounds are composited first, the way the screen shows them.
double _contrast(Color foreground, Color background) {
  final resolved = Color.alphaBlend(foreground, background);
  final a = _luminance(resolved);
  final b = _luminance(background);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final name = entry.key;
    final theme = entry.value;
    final colors = theme.colorScheme;
    final accents = theme.extension<AppAccents>()!;

    void expectReadable(
      String label,
      Color foreground,
      Color background, {
      double minimum = 4.5,
    }) {
      final ratio = _contrast(foreground, background);
      expect(
        ratio,
        greaterThanOrEqualTo(minimum),
        reason:
            '$name: $label has contrast ${ratio.toStringAsFixed(2)}, '
            'below the $minimum minimum',
      );
    }

    group('$name theme', () {
      test('every text style is readable on both page and card surfaces', () {
        final styles = <String, TextStyle?>{
          'displayLarge': theme.textTheme.displayLarge,
          'displayMedium': theme.textTheme.displayMedium,
          'displaySmall': theme.textTheme.displaySmall,
          'headlineLarge': theme.textTheme.headlineLarge,
          'headlineMedium': theme.textTheme.headlineMedium,
          'headlineSmall': theme.textTheme.headlineSmall,
          'titleLarge': theme.textTheme.titleLarge,
          'titleMedium': theme.textTheme.titleMedium,
          'titleSmall': theme.textTheme.titleSmall,
          'bodyLarge': theme.textTheme.bodyLarge,
          'bodyMedium': theme.textTheme.bodyMedium,
          'bodySmall': theme.textTheme.bodySmall,
          'labelLarge': theme.textTheme.labelLarge,
          'labelMedium': theme.textTheme.labelMedium,
          'labelSmall': theme.textTheme.labelSmall,
        };
        for (final style in styles.entries) {
          final color = style.value?.color;
          expect(color, isNotNull, reason: '$name: ${style.key} has no color');
          expectReadable(
            '${style.key} on the page background',
            color!,
            theme.scaffoldBackgroundColor,
          );
          expectReadable('${style.key} on a card', color, colors.surface);
        }
      });

      test('foregrounds contrast with the surface they name', () {
        expectReadable('onPrimary', colors.onPrimary, colors.primary);
        expectReadable('onSecondary', colors.onSecondary, colors.secondary);
        expectReadable('onTertiary', colors.onTertiary, colors.tertiary);
        expectReadable('onError', colors.onError, colors.error);
        expectReadable('onSurface', colors.onSurface, colors.surface);
        expectReadable(
          'onSurfaceVariant',
          colors.onSurfaceVariant,
          colors.surface,
        );
        expectReadable(
          'onSurfaceVariant on the raised surface',
          colors.onSurfaceVariant,
          colors.surfaceContainerHighest,
        );
        expectReadable(
          'onInverseSurface',
          colors.onInverseSurface,
          colors.inverseSurface,
        );
      });

      test('text stays readable on every branded accent surface', () {
        final surfaces = {
          'peach': accents.peach,
          'blue': accents.blue,
          'lilac': accents.lilac,
          'mint': accents.mint,
        };
        for (final surface in surfaces.entries) {
          expectReadable(
            'onAccent on ${surface.key}',
            accents.onAccent,
            surface.value,
          );
          // Accent cards also host plain inherited body text and the muted
          // captions that sit above a title.
          expectReadable(
            'onSurface on ${surface.key}',
            colors.onSurface,
            surface.value,
          );
          expectReadable(
            'onSurfaceVariant on ${surface.key}',
            colors.onSurfaceVariant,
            surface.value,
          );
        }
        expectReadable('onHighlight', accents.onHighlight, accents.highlight);
        expectReadable('onWarning', accents.onWarning, accents.warning);
      });

      test('navigation bar labels stay readable, selected or not', () {
        final navTheme = theme.navigationBarTheme;
        final background = navTheme.backgroundColor!;
        for (final states in [
          <WidgetState>{WidgetState.selected},
          <WidgetState>{},
        ]) {
          final label = navTheme.labelTextStyle!.resolve(states)!;
          expectReadable('nav label $states', label.color!, background);
          final icon = navTheme.iconTheme!.resolve(states)!;
          expectReadable(
            'nav icon $states',
            icon.color!,
            states.contains(WidgetState.selected)
                ? navTheme.indicatorColor!
                : background,
            minimum: 3,
          );
        }
      });

      test('input, dialog, sheet and menu text is readable', () {
        expectReadable(
          'hint text',
          theme.inputDecorationTheme.hintStyle!.color!,
          theme.inputDecorationTheme.fillColor!,
        );
        expectReadable(
          'dialog body',
          theme.dialogTheme.contentTextStyle!.color!,
          theme.dialogTheme.backgroundColor!,
        );
        expectReadable(
          'dialog title',
          theme.dialogTheme.titleTextStyle!.color!,
          theme.dialogTheme.backgroundColor!,
        );
        expectReadable(
          'popup menu item',
          theme.popupMenuTheme.textStyle!.color!,
          theme.popupMenuTheme.color!,
        );
        expectReadable(
          'snack bar',
          theme.snackBarTheme.contentTextStyle!.color!,
          theme.snackBarTheme.backgroundColor!,
        );
        expectReadable(
          'chip label',
          theme.chipTheme.labelStyle!.color!,
          theme.chipTheme.backgroundColor!,
        );
        expectReadable(
          'selected chip label',
          theme.chipTheme.secondaryLabelStyle!.color!,
          theme.chipTheme.selectedColor!,
        );
      });

      test('no bundled font is forced, so non-Latin song titles keep glyphs', () {
        // The app ships no font assets, so text falls back to the platform
        // family, which covers Malayalam, Tamil, Hindi and Latin metadata.
        // Anything else here would mean a Latin-only face was pinned globally.
        const platformFamilies = {'Roboto', '.SF UI Text', '.SF UI Display'};
        for (final style in [
          theme.textTheme.bodyMedium,
          theme.textTheme.titleMedium,
          theme.textTheme.headlineLarge,
        ]) {
          final family = style?.fontFamily;
          expect(
            family == null || platformFamilies.contains(family),
            isTrue,
            reason: '$name: a custom font family ($family) is pinned globally',
          );
        }
      });
    });
  }

  test('the player stage carries its own readable foregrounds', () {
    const palette = PlayerPalette.fallback;
    for (final background in [palette.background, palette.surface]) {
      expect(
        _contrast(PlayerPalette.onSurface, background),
        greaterThanOrEqualTo(4.5),
        reason: 'player title text is unreadable on the stage',
      );
      expect(
        _contrast(PlayerPalette.onSurfaceVariant, background),
        greaterThanOrEqualTo(4.5),
        reason: 'player metadata text is unreadable on the stage',
      );
      // Faint is for disabled controls only, so it holds the 3:1 UI minimum.
      expect(
        _contrast(PlayerPalette.onSurfaceFaint, background),
        greaterThanOrEqualTo(3),
        reason: 'disabled player controls are invisible on the stage',
      );
    }
  });

  test('both brightnesses expose the accent extension', () {
    expect(AppTheme.light.extension<AppAccents>(), isNotNull);
    expect(AppTheme.dark.extension<AppAccents>(), isNotNull);
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });
}
