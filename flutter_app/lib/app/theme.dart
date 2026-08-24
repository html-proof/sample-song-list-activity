import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFFF3F1EC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHigh = Color(0xFFE9E6DF);
  static const ink = Color(0xFF090909);
  static const muted = Color(0xFF73716C);
  static const accent = Color(0xFFD8FF45);
  static const peach = Color(0xFFF2E3D6);
  static const blue = Color(0xFFDDE7F8);
  static const lilac = Color(0xFFE7E0F1);
  static const mint = Color(0xFFDDEBDD);

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: ink,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: ink,
      surface: surface,
      onSurface: ink,
      error: Color(0xFFB3261E),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: ink.withValues(alpha: 0.08),
      splashColor: ink.withValues(alpha: 0.05),
      highlightColor: ink.withValues(alpha: 0.03),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: ink,
        indicatorColor: Colors.white,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? ink : Colors.white60,
            size: 21,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : Colors.white54,
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: ink.withValues(alpha: 0.06)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide(color: ink, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: ink),
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: ink,
        disabledColor: surfaceHigh,
        labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: ink,
        inactiveTrackColor: surfaceHigh,
        thumbColor: ink,
        overlayColor: Color(0x14000000),
        trackHeight: 2,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: ink,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.8,
          height: 0.98,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
          height: 1.02,
        ),
        headlineSmall: TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: ink),
        bodyMedium: TextStyle(color: ink),
      ),
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: Colors.white,
      onPrimary: ink,
      secondary: accent,
      onSecondary: ink,
      surface: Color(0xFF171717),
      onSurface: Colors.white,
      error: Color(0xFFFFB4AB),
    );
    return light.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      canvasColor: const Color(0xFF0D0D0D),
      dividerColor: Colors.white12,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
    );
  }
}
