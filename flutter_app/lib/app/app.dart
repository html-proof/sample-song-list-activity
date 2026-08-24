import 'package:flutter/material.dart';
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
    );
  }
}
