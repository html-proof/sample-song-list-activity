import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand accent surfaces that Material's [ColorScheme] has no slot for.
///
/// Every accent carries the foreground that belongs on it, so a widget never
/// has to decide whether text should be dark or light: it asks the theme for
/// the pair. Light and dark each supply their own values and Flutter lerps
/// between them when the platform brightness changes.
@immutable
class AppAccents extends ThemeExtension<AppAccents> {
  const AppAccents({
    required this.peach,
    required this.blue,
    required this.lilac,
    required this.mint,
    required this.onAccent,
    required this.highlight,
    required this.onHighlight,
    required this.warning,
    required this.onWarning,
    required this.raised,
  });

  /// Tinted card surfaces used across Home, Library, Settings and Details.
  final Color peach;
  final Color blue;
  final Color lilac;
  final Color mint;

  /// The only foreground allowed on [peach], [blue], [lilac] and [mint].
  final Color onAccent;

  /// The lime call-to-action colour. It stays bright in both modes, so it
  /// keeps its own dark foreground.
  final Color highlight;
  final Color onHighlight;

  /// The offline / degraded-state banner. Warning keeps one meaning in both
  /// modes, so the pair is identical either way.
  final Color warning;
  final Color onWarning;

  /// A slightly raised neutral: dividers, placeholders, inactive tracks.
  final Color raised;

  static const light = AppAccents(
    peach: Color(0xFFF2E3D6),
    blue: Color(0xFFDDE7F8),
    lilac: Color(0xFFE7E0F1),
    mint: Color(0xFFDDEBDD),
    onAccent: Color(0xFF090909),
    highlight: Color(0xFFD8FF45),
    onHighlight: Color(0xFF090909),
    warning: Color(0xFF9A3A00),
    onWarning: Color(0xFFFFFFFF),
    raised: Color(0xFFE9E6DF),
  );

  /// Dark counterparts keep each accent's hue but move it below the text, so
  /// the same layouts stay readable without any per-screen colour logic.
  static const dark = AppAccents(
    peach: Color(0xFF3B2E25),
    blue: Color(0xFF1E2835),
    lilac: Color(0xFF2A2436),
    mint: Color(0xFF212E23),
    onAccent: Color(0xFFF3F0EA),
    highlight: Color(0xFFD8FF45),
    onHighlight: Color(0xFF090909),
    warning: Color(0xFF9A3A00),
    onWarning: Color(0xFFFFFFFF),
    raised: Color(0xFF262626),
  );

  @override
  AppAccents copyWith({
    Color? peach,
    Color? blue,
    Color? lilac,
    Color? mint,
    Color? onAccent,
    Color? highlight,
    Color? onHighlight,
    Color? warning,
    Color? onWarning,
    Color? raised,
  }) {
    return AppAccents(
      peach: peach ?? this.peach,
      blue: blue ?? this.blue,
      lilac: lilac ?? this.lilac,
      mint: mint ?? this.mint,
      onAccent: onAccent ?? this.onAccent,
      highlight: highlight ?? this.highlight,
      onHighlight: onHighlight ?? this.onHighlight,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      raised: raised ?? this.raised,
    );
  }

  @override
  AppAccents lerp(ThemeExtension<AppAccents>? other, double t) {
    if (other is! AppAccents) return this;
    return AppAccents(
      peach: Color.lerp(peach, other.peach, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      lilac: Color.lerp(lilac, other.lilac, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      onHighlight: Color.lerp(onHighlight, other.onHighlight, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
    );
  }
}

/// Semantic shortcuts so widgets read the theme instead of naming colours.
extension AppColors on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  AppAccents get accents =>
      Theme.of(this).extension<AppAccents>() ?? AppAccents.light;

  /// Titles, body copy, anything the user must read.
  Color get primaryText => colors.onSurface;

  /// Supporting metadata: artists, counts, captions.
  Color get secondaryText => colors.onSurfaceVariant;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _base(_lightScheme, AppAccents.light);
  static ThemeData get dark => _base(_darkScheme, AppAccents.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF090909),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFFD8FF45),
    onSecondary: Color(0xFF090909),
    tertiary: Color(0xFF4C5C8A),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF090909),
    surfaceContainerHighest: Color(0xFFE9E6DF),
    onSurfaceVariant: Color(0xFF5F5D58),
    outline: Color(0xFF8B8983),
    outlineVariant: Color(0xFFDCD8D0),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF090909),
    onInverseSurface: Color(0xFFFFFFFF),
    inversePrimary: Color(0xFFE9E6DF),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3F0EA),
    onPrimary: Color(0xFF090909),
    secondary: Color(0xFFD8FF45),
    onSecondary: Color(0xFF090909),
    tertiary: Color(0xFFB3C4F2),
    onTertiary: Color(0xFF16203D),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF601410),
    surface: Color(0xFF1A1A1A),
    onSurface: Color(0xFFF3F0EA),
    surfaceContainerHighest: Color(0xFF262626),
    onSurfaceVariant: Color(0xFFB6B2AB),
    outline: Color(0xFF7C7972),
    outlineVariant: Color(0xFF3A3A3A),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF262626),
    onInverseSurface: Color(0xFFF3F0EA),
    inversePrimary: Color(0xFF090909),
  );

  static const _lightBackground = Color(0xFFF3F1EC);
  static const _darkBackground = Color(0xFF0D0D0D);

  static ThemeData _base(ColorScheme colors, AppAccents accents) {
    final dark = colors.brightness == Brightness.dark;
    final background = dark ? _darkBackground : _lightBackground;
    final onSurface = colors.onSurface;
    final overlayStyle = dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      colorScheme: colors,
      // No global fontFamily: song and artist names arrive in Malayalam,
      // Tamil, Hindi and Latin scripts, and the platform picks a font that
      // actually has the glyphs when we do not force one.
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: colors.outlineVariant,
      splashColor: onSurface.withValues(alpha: 0.05),
      highlightColor: onSurface.withValues(alpha: 0.03),
      extensions: [accents],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        centerTitle: false,
        systemOverlayStyle: overlayStyle,
        iconTheme: IconThemeData(color: onSurface),
        actionsIconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
      iconTheme: IconThemeData(color: onSurface),
      listTileTheme: ListTileThemeData(
        textColor: onSurface,
        iconColor: onSurface,
        subtitleTextStyle: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        contentTextStyle: TextStyle(color: onSurface, fontSize: 15),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        modalBackgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colors.onSurfaceVariant,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: onSurface),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: TextStyle(color: colors.onInverseSurface),
        actionTextColor: colors.secondary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: colors.inverseSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.onInverseSurface,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.inverseSurface
                : colors.onInverseSurface.withValues(alpha: 0.78),
            size: 21,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? colors.onInverseSurface
                : colors.onInverseSurface.withValues(alpha: 0.78),
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
        prefixIconColor: colors.onSurfaceVariant,
        suffixIconColor: colors.onSurfaceVariant,
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
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: 0.24),
        selectionHandleColor: colors.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: onSurface.withValues(alpha: 0.38),
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: BorderSide(color: colors.outline),
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: onSurface),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: colors.primary,
        disabledColor: colors.surfaceContainerHighest,
        checkmarkColor: colors.onPrimary,
        labelStyle: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(
          color: colors.onPrimary,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.surfaceContainerHighest,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.surfaceContainerHighest,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.12),
        trackHeight: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
      disabledColor: onSurface.withValues(alpha: 0.38),
      textTheme: _textTheme(colors),
    );
  }

  /// Every style names its own colour, so text can never inherit a foreground
  /// that belongs to the other brightness.
  static TextTheme _textTheme(ColorScheme colors) {
    final onSurface = colors.onSurface;
    final variant = colors.onSurfaceVariant;
    return TextTheme(
      displayLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w900),
      displayMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w900),
      displaySmall: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
      headlineLarge: TextStyle(
        color: onSurface,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.8,
        height: 0.98,
      ),
      headlineMedium: TextStyle(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        height: 1.02,
      ),
      headlineSmall: TextStyle(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      titleLarge: TextStyle(
        color: onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: onSurface),
      bodyMedium: TextStyle(color: onSurface),
      bodySmall: TextStyle(color: variant),
      labelLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: variant),
      labelSmall: TextStyle(color: variant),
    );
  }
}
