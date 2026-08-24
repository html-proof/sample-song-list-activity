import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/startup/startup_controller.dart';
import 'package:music_hub_app/features/auth/presentation/auth_controller.dart';
import 'package:music_hub_app/features/auth/presentation/login_screen.dart';
import 'package:music_hub_app/features/auth/presentation/session_gate.dart';
import 'package:music_hub_app/features/details/presentation/details_screen.dart';
import 'package:music_hub_app/features/home/presentation/home_screen.dart';
import 'package:music_hub_app/features/library/presentation/library_screen.dart';
import 'package:music_hub_app/features/onboarding/presentation/onboarding_screen.dart';
import 'package:music_hub_app/features/player/presentation/player_screen.dart';
import 'package:music_hub_app/features/profile/presentation/profile_screen.dart';
import 'package:music_hub_app/features/search/presentation/search_screen.dart';
import 'package:music_hub_app/features/settings/presentation/settings_detail_screen.dart';
import 'package:music_hub_app/features/settings/presentation/settings_hub_screen.dart';
import 'package:music_hub_app/features/settings/presentation/music_preferences_screen.dart';
import 'package:music_hub_app/features/splash/presentation/splash_screen.dart';
import 'package:music_hub_app/shared/widgets/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final firebaseAuth = ref.watch(firebaseAuthProvider);
  final firstLaunch = ref.watch(firstLaunchServiceProvider);
  final sessions = ref.watch(sessionRepositoryProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isRoot = location == '/';
      final isSplash = location == '/splash';
      final isLogin = location == '/login';
      final isOnboarding = location.startsWith('/onboarding');

      if (isSplash && !firstLaunch.shouldShowSplash) return '/';

      final firebaseUser = firebaseAuth.currentUser;
      if (firebaseUser == null) {
        return isRoot || isSplash || isLogin ? null : '/login';
      }

      if (isLogin) return '/';
      if (isRoot || isSplash) return null;

      final profile = sessions.currentUser;
      if (profile == null) return '/';
      if (!profile.onboardingCompleted && !isOnboarding) {
        return '/onboarding/languages';
      }
      if (profile.onboardingCompleted && isOnboarding) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SessionGate()),
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/onboarding/languages',
        builder: (_, _) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, _) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/player',
        builder: (_, _) => const PlayerScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/artist/:seokey',
        builder: (_, state) =>
            ArtistScreen(seokey: state.pathParameters['seokey']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/album/:seokey',
        builder: (_, state) =>
            AlbumScreen(seokey: state.pathParameters['seokey']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings',
        builder: (_, _) => const SettingsHubScreen(),
        routes: [
          GoRoute(
            path: 'appearance',
            builder: (_, _) =>
                const SettingsDetailScreen(page: SettingsPage.appearance),
          ),
          GoRoute(
            path: 'playback',
            builder: (_, _) =>
                const SettingsDetailScreen(page: SettingsPage.playback),
          ),
          GoRoute(
            path: 'downloads',
            builder: (_, _) =>
                const SettingsDetailScreen(page: SettingsPage.downloads),
          ),
          GoRoute(
            path: 'recommendations',
            builder: (_, _) =>
                const SettingsDetailScreen(page: SettingsPage.recommendations),
          ),
          GoRoute(
            path: 'notifications',
            builder: (_, _) =>
                const SettingsDetailScreen(page: SettingsPage.notifications),
          ),
          GoRoute(
            path: 'privacy',
            builder: (_, _) =>
                const SettingsDetailScreen(page: SettingsPage.privacy),
          ),
          GoRoute(
            path: 'storage',
            builder: (_, _) =>
                const SettingsDetailScreen(page: SettingsPage.storage),
          ),
          GoRoute(
            path: 'music-languages',
            builder: (_, _) => const MusicPreferencesScreen(
              page: MusicPreferencesPage.languages,
            ),
          ),
          GoRoute(
            path: 'favorite-artists',
            builder: (_, _) => const MusicPreferencesScreen(
              page: MusicPreferencesPage.artists,
            ),
          ),
        ],
      ),
    ],
  );
});
