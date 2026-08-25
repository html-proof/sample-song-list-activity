import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/music_tile.dart';

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

double contrast(Color foreground, Color background) {
  final a = _luminance(foreground);
  final b = _luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// The colour a [Text] actually paints with, after the ambient DefaultTextStyle
/// and the theme have been merged in. A widget that simply omits a colour still
/// has to end up readable, so resolving it this way is the point of the test.
Color resolvedColor(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  final defaultStyle = DefaultTextStyle.of(tester.element(finder)).style;
  final merged = text.style == null
      ? defaultStyle
      : defaultStyle.merge(text.style);
  expect(
    merged.color,
    isNotNull,
    reason: 'no colour resolved for ${text.data}',
  );
  return merged.color!;
}

Widget host(ThemeData theme, Widget child) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: child),
  );
}

void main() {
  final song = MusicItem.fromJson({
    'track_id': '1',
    'title': 'A song title',
    'artists': 'An artist name',
  });

  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final name = entry.key;
    final theme = entry.value;

    testWidgets('$name: a song row stays readable on the scaffold', (
      tester,
    ) async {
      await tester.pumpWidget(host(theme, MusicTile(item: song, onTap: () {})));

      final background = theme.scaffoldBackgroundColor;
      expect(
        contrast(resolvedColor(tester, find.text('A song title')), background),
        greaterThan(4.5),
        reason: '$name song title',
      );
      expect(
        contrast(
          resolvedColor(tester, find.text('An artist name')),
          background,
        ),
        greaterThan(3.0),
        reason: '$name song subtitle',
      );
    });

    testWidgets('$name: an unstyled Text inherits a readable colour', (
      tester,
    ) async {
      await tester.pumpWidget(host(theme, const Text('Plain body text')));

      expect(
        contrast(
          resolvedColor(tester, find.text('Plain body text')),
          theme.scaffoldBackgroundColor,
        ),
        greaterThan(4.5),
        reason: '$name unstyled text',
      );
    });
  }

  testWidgets('the palette follows a foreign dark theme, not the light default', (
    tester,
  ) async {
    // The player installs a plain ThemeData.dark() that carries no AppPalette.
    // Falling back to the light palette there painted dark text on dark chrome.
    late AppPalette resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (context) {
            resolved = AppPalette.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved.ink, AppTheme.darkPalette.ink);
    expect(contrast(resolved.ink, const Color(0xFF08090C)), greaterThan(4.5));
  });

  testWidgets('the palette still resolves light under a light theme', (
    tester,
  ) async {
    late AppPalette resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        home: Builder(
          builder: (context) {
            resolved = AppPalette.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved.ink, AppTheme.lightPalette.ink);
  });
}
