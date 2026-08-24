import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/startup/first_launch_service.dart';
import 'package:music_hub_app/core/startup/startup_state.dart';
import 'package:music_hub_app/features/auth/data/session_repository.dart';
import 'package:music_hub_app/features/auth/presentation/auth_controller.dart';

final firstLaunchServiceProvider = Provider<FirstLaunchService>((ref) {
  return FirstLaunchService(ref.watch(sharedPreferencesProvider));
});

final startupControllerProvider = Provider<StartupController>((ref) {
  return StartupController(
    firebaseAuth: ref.watch(firebaseAuthProvider),
    firstLaunchService: ref.watch(firstLaunchServiceProvider),
    authRepository: ref.watch(sessionRepositoryProvider),
  );
});

final startupDestinationProvider = FutureProvider<StartupDestination>((ref) {
  // Re-resolve when Firebase restores, signs in, signs out, or deletes a user.
  ref.watch(authStateProvider);
  return ref.watch(startupControllerProvider).resolve();
});

class StartupController {
  StartupController({
    required this.firebaseAuth,
    required this.firstLaunchService,
    required this.authRepository,
  });

  final FirebaseAuth firebaseAuth;
  final FirstLaunchService firstLaunchService;
  final SessionRepository authRepository;

  Future<StartupDestination> resolve({bool allowSplash = true}) async {
    if (allowSplash && await firstLaunchService.isFirstLaunch()) {
      return StartupDestination.splash;
    }

    final firebaseUser = await firebaseAuth.authStateChanges().first;
    if (firebaseUser == null) {
      authRepository.clear();
      return StartupDestination.login;
    }

    final profile = await authRepository.synchronize();
    return profile.onboardingCompleted
        ? StartupDestination.home
        : StartupDestination.onboarding;
  }

  Future<StartupDestination> completeSplash() async {
    await firstLaunchService.markSplashSeen();
    return resolve(allowSplash: false);
  }
}
