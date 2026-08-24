import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/features/auth/data/session_repository.dart';
import 'package:music_hub_app/shared/models/app_user.dart';

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(apiClientProvider));
});

final sessionProvider = FutureProvider<AppUser?>((ref) async {
  ref.watch(authStateProvider);
  if (ref.watch(firebaseAuthProvider).currentUser == null) return null;
  final user = await ref.watch(sessionRepositoryProvider).synchronize();
  unawaited(ref.read(deviceRegistrarProvider).register().catchError((_) {}));
  return user;
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
      return AuthController(ref);
    });

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> signIn() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref.read(firebaseAuthServiceProvider).signInWithGoogle();
      _ref.read(sessionRepositoryProvider).clear();
      _ref.invalidate(sessionProvider);
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await _ref.read(deviceRegistrarProvider).unregister();
      } catch (_) {
        // Sign-out must still succeed while offline.
      }
      await _ref.read(localStoreProvider).clearPrivateSession();
      await _ref.read(firebaseAuthServiceProvider).signOut();
      _ref.read(sessionRepositoryProvider).clear();
      _ref.invalidate(sessionProvider);
    });
  }

  Future<bool> deleteAccount() async {
    state = const AsyncLoading();
    try {
      await _ref.read(firebaseAuthServiceProvider).reauthenticateWithGoogle();
      await _ref.read(apiClientProvider).delete(ApiEndpoints.account);
      await _ref.read(firebaseAuthServiceProvider).deleteCurrentUser();
      await _ref.read(localStoreProvider).clearPrivateSession();
      _ref.read(sessionRepositoryProvider).clear();
      _ref.invalidate(sessionProvider);
      state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}
