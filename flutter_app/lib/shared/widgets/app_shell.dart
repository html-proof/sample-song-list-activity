import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/features/player/presentation/mini_player.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(connectivityProvider).value;
    final offline =
        results?.isNotEmpty == true &&
        results!.every((value) => value == ConnectivityResult.none);
    return Scaffold(
      body: Column(
        children: [
          if (offline)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: Colors.orange.shade900,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                child: const Text(
                  'Offline — showing saved content where available',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: NavigationBar(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: (index) => navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  ),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.graphic_eq_rounded),
                      selectedIcon: Icon(Icons.graphic_eq_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      label: 'Search',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music_rounded),
                      label: 'Library',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'You',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
