import 'package:flutter/material.dart';

/// The colours that are not expressible through [ColorScheme]: the paper-like
/// background, the muted secondary text, and the pastel panels that artwork
/// sits on. They are resolved per brightness so a widget can read the correct
/// value through [AppPalette.of] instead of hardcoding the light one.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.panel,
    required this.panelHigh,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.peach,
    required this.blue,
    required this.lilac,
    required this.mint,
    required this.onTile,
    required this.navBar,
    required this.onNavBar,
  });

  /// Page background.
  final Color background;

  /// Raised card and sheet fill.
  final Color panel;

  /// Second level fill, used for inactive tracks and disabled chips.
  final Color panelHigh;

  /// Primary foreground. Near black on light, near white on dark.
  final Color ink;

  /// Secondary foreground for captions and supporting labels.
  final Color muted;

  final Color accent;

  /// Decorative panels that sit behind artwork.
  final Color peach;
  final Color blue;
  final Color lilac;
  final Color mint;

  /// Foreground guaranteed to read on [peach], [blue], [lilac] and [mint].
  final Color onTile;

  /// The bottom navigation bar, which is a high contrast block rather than a
  /// tint of the background.
  final Color navBar;
  final Color onNavBar;

  /// Falls back on the ambient brightness rather than on the light palette.
  /// Screens such as the player install their own [ThemeData.dark] without
  /// this extension, and a light fallback there paints dark text on a dark
  /// background.
  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<AppPalette>();
    if (extension != null) return extension;
    return theme.brightness == Brightness.dark
        ? AppTheme.darkPalette
        : AppTheme.lightPalette;
  }

  @override
  AppPalette copyWith({
    Color? background,
    Color? panel,
    Color? panelHigh,
    Color? ink,
    Color? muted,
    Color? accent,
    Color? peach,
    Color? blue,
    Color? lilac,
    Color? mint,
    Color? onTile,
    Color? navBar,
    Color? onNavBar,
  }) {
    return AppPalette(
      background: background ?? this.background,
      panel: panel ?? this.panel,
      panelHigh: panelHigh ?? this.panelHigh,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      peach: peach ?? this.peach,
      blue: blue ?? this.blue,
      lilac: lilac ?? this.lilac,
      mint: mint ?? this.mint,
      onTile: onTile ?? this.onTile,
      navBar: navBar ?? this.navBar,
      onNavBar: onNavBar ?? this.onNavBar,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelHigh: Color.lerp(panelHigh, other.panelHigh, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      peach: Color.lerp(peach, other.peach, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      lilac: Color.lerp(lilac, other.lilac, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      onTile: Color.lerp(onTile, other.onTile, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      onNavBar: Color.lerp(onNavBar, other.onNavBar, t)!,
    );
  }
}

class AppTheme {
  // Retained so existing const call sites keep compiling. These hold the light
  // values; anything that must follow the system theme reads AppPalette.of.
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

  static const lightPalette = AppPalette(
    background: background,
    panel: surface,
    panelHigh: surfaceHigh,
    ink: ink,
    muted: muted,
    accent: accent,
    peach: peach,
    blue: blue,
    lilac: lilac,
    mint: mint,
    onTile: ink,
    navBar: ink,
    onNavBar: Colors.white,
  );

  static const darkPalette = AppPalette(
    background: Color(0xFF0D0D0D),
    panel: Color(0xFF171717),
    panelHigh: Color(0xFF262626),
    ink: Color(0xFFF4F3F0),
    muted: Color(0xFFA8A59E),
    accent: accent,
    peach: Color(0xFF34291F),
    blue: Color(0xFF1B2432),
    lilac: Color(0xFF262036),
    mint: Color(0xFF1D2A1D),
    onTile: Color(0xFFF4F3F0),
    navBar: Color(0xFF1F1F1F),
    onNavBar: Color(0xFFF4F3F0),
  );

  static ThemeData get light {
    return _build(
      brightness: Brightness.light,
      palette: lightPalette,
      scheme: const ColorScheme.light(
        primary: ink,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: ink,
        surface: surface,
        onSurface: ink,
        error: Color(0xFFB3261E),
      ),
    );
  }

  static ThemeData get dark {
    return _build(
      brightness: Brightness.dark,
      palette: darkPalette,
      scheme: const ColorScheme.dark(
        primary: Color(0xFFF0EEE8),
        onPrimary: Color(0xFF0D0D0D),
        secondary: accent,
        onSecondary: ink,
        surface: Color(0xFF171717),
        onSurface: Color(0xFFF4F3F0),
        error: Color(0xFFFFB4AB),
      ),
    );
  }

  /// Both themes are produced here so a component styled for one can never be
  /// left behind in the other, which is what the previous copyWith-based dark
  /// theme did: it inherited the light text colours onto a dark background.
  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
    required ColorScheme scheme,
  }) {
    final ink = palette.ink;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: ink.withValues(alpha: 0.08),
      splashColor: ink.withValues(alpha: 0.05),
      highlightColor: ink.withValues(alpha: 0.03),
      appBarTheme: AppBarTheme(
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
      cardTheme: CardThemeData(
        color: palette.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: palette.navBar,
        indicatorColor: palette.onNavBar,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.navBar
                : palette.onNavBar.withValues(alpha: 0.60),
            size: 21,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? palette.onNavBar
                : palette.onNavBar.withValues(alpha: 0.54),
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.panel,
        hintStyle: TextStyle(color: palette.muted),
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
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide(color: ink, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink),
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      iconTheme: IconThemeData(color: ink),
      chipTheme: ChipThemeData(
        backgroundColor: palette.panel,
        selectedColor: scheme.primary,
        disabledColor: palette.panelHigh,
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: ink,
        inactiveTrackColor: palette.panelHigh,
        thumbColor: ink,
        overlayColor: ink.withValues(alpha: 0.08),
        trackHeight: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: ink),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.navBar,
        contentTextStyle: TextStyle(color: palette.onNavBar),
      ),
      dialogTheme: DialogThemeData(backgroundColor: palette.panel),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: palette.panel),
      listTileTheme: ListTileThemeData(
        textColor: ink,
        iconColor: ink,
        subtitleTextStyle: TextStyle(color: palette.muted),
      ),
      textTheme: TextTheme(
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
}
