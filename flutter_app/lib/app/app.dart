import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/router.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/startup/startup_controller.dart';
import 'package:music_hub_app/features/settings/presentation/settings_controller.dart';

class MusicHubApp extends ConsumerWidget {
  const MusicHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    ref.listen(authStateProvider, (_, next) {
      if (!next.hasValue) return;
      if (next.value != null) {
        router.go('/');
        return;
      }
      final firstLaunch = ref.read(firstLaunchServiceProvider);
      router.go(firstLaunch.shouldShowSplash ? '/' : '/login');
    });
    return MaterialApp.router(
      title: 'Music Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // Status- and navigation-bar icons follow the theme that is actually
      // resolved, so they stay visible on screens that have no AppBar to
      // carry an overlay style of their own.
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
              ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
