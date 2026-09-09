import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemePreference { system, light, dark }

extension ThemePreferenceX on ThemePreference {
  String get storageValue => name;
  ThemeMode get themeMode => switch (this) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };

  static ThemePreference fromStorage(String? value) => switch (value) {
    'light' => ThemePreference.light,
    'dark' => ThemePreference.dark,
    _ => ThemePreference.system,
  };
}

class ThemePreferenceController extends ChangeNotifier {
  static late ThemePreferenceController instance;
  ThemePreferenceController(this.preference);
  ThemePreference preference;

  Future<void> setPreference(ThemePreference value) async {
    if (preference == value) return;
    preference = value;
    notifyListeners();
    final local = await SharedPreferences.getInstance();
    await local.setString('theme_preference', value.storageValue);
  }

  static Future<ThemePreferenceController> load() async {
    final local = await SharedPreferences.getInstance();
    return ThemePreferenceController(
      ThemePreferenceX.fromStorage(local.getString('theme_preference')),
    );
  }
}

bool isColorDark(Color color) => color.computeLuminance() < 0.42;

Color readableTextColor(Color background) =>
    isColorDark(background) ? Colors.white : const Color(0xFF121212);

Color readableSecondaryTextColor(Color background) =>
    isColorDark(background) ? const Color(0xFFB8B8B8) : const Color(0xFF5F6368);

Color readableIconColor(Color background) => readableTextColor(background);

abstract final class AppColors {
  static const ink = Color(0xFF090909);
  static const paper = Color(0xFFF8F7F3);
  static const warm = Color(0xFFECE8E1);
  static const blush = Color(0xFFF1E4DA);
  static const lavender = Color(0xFFE8E8F2);
  static const muted = Color(0xFF77746E);
  static const orange = Color(0xFFFF4B1F);
}

@immutable
class MusicHubColors extends ThemeExtension<MusicHubColors> {
  const MusicHubColors({
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surfaceColor,
    required this.accentColor,
    required this.errorColor,
    required this.dividerColor,
  });

  final Color textPrimary, textSecondary, textMuted;
  final Color backgroundPrimary, backgroundSecondary, surfaceColor;
  final Color accentColor, errorColor, dividerColor;

  @override
  MusicHubColors copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surfaceColor,
    Color? accentColor,
    Color? errorColor,
    Color? dividerColor,
  }) => MusicHubColors(
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
    backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
    surfaceColor: surfaceColor ?? this.surfaceColor,
    accentColor: accentColor ?? this.accentColor,
    errorColor: errorColor ?? this.errorColor,
    dividerColor: dividerColor ?? this.dividerColor,
  );

  @override
  MusicHubColors lerp(covariant MusicHubColors? other, double t) {
    if (other == null) return this;
    return MusicHubColors(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      backgroundPrimary: Color.lerp(
        backgroundPrimary,
        other.backgroundPrimary,
        t,
      )!,
      backgroundSecondary: Color.lerp(
        backgroundSecondary,
        other.backgroundSecondary,
        t,
      )!,
      surfaceColor: Color.lerp(surfaceColor, other.surfaceColor, t)!,
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      errorColor: Color.lerp(errorColor, other.errorColor, t)!,
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t)!,
    );
  }
}

extension MusicHubTheme on BuildContext {
  MusicHubColors get hubColors =>
      Theme.of(this).extension<MusicHubColors>() ??
      const MusicHubColors(
        textPrimary: Colors.white,
        textSecondary: Color(0xFFB8B8B8),
        textMuted: Color(0xFF727272),
        backgroundPrimary: Color(0xFF000000),
        backgroundSecondary: Color(0xFF242424),
        surfaceColor: Color(0xFF181818),
        accentColor: AppColors.orange,
        errorColor: Colors.red,
        dividerColor: Color(0xFF2A2A2A),
      );
}

ThemeData soundwavesTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF000000) : AppColors.paper;
  final surface = dark ? const Color(0xFF181818) : Colors.white;
  final surfaceVariant = dark ? const Color(0xFF242424) : AppColors.warm;
  final text = readableTextColor(background);
  final secondary = readableSecondaryTextColor(background);
  final divider = dark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5);
  final muted = dark ? const Color(0xFF727272) : const Color(0xFF9E9E9E);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.orange,
        brightness: brightness,
        surface: surface,
      ).copyWith(
        primary: AppColors.orange,
        onPrimary: readableTextColor(AppColors.orange),
        surface: surface,
        onSurface: text,
        surfaceContainerHighest: surfaceVariant,
        outline: divider,
        onSurfaceVariant: secondary,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: scheme,
    extensions: [
      MusicHubColors(
        textPrimary: text,
        textSecondary: secondary,
        textMuted: muted,
        backgroundPrimary: background,
        backgroundSecondary: surfaceVariant,
        surfaceColor: surface,
        accentColor: AppColors.orange,
        errorColor: scheme.error,
        dividerColor: divider,
      ),
    ],
    fontFamily: 'Arial',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 48,
        height: .96,
        fontWeight: FontWeight.w800,
        letterSpacing: -2.3,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -.4,
      ),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: text,
      iconTheme: IconThemeData(color: text),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: background,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: dark ? const Color(0xFF5A2417) : const Color(0xFFFFE4DC),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(color: secondary)),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: secondary)),
      height: 72,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: readableTextColor(AppColors.orange),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? const Color(0xFF242424)
          : Colors.black.withValues(alpha: .05),
      hintStyle: TextStyle(color: secondary),
      labelStyle: TextStyle(color: secondary),
      prefixIconColor: secondary,
      suffixIconColor: secondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: scheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    ),
    dividerTheme: DividerThemeData(color: divider),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceVariant,
      contentTextStyle: TextStyle(color: text),
    ),
  );
}
