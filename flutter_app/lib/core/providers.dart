import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/event_tracker.dart';
import 'package:music_hub_app/core/audio/music_audio_handler.dart';
import 'package:music_hub_app/core/auth/firebase_auth_service.dart';
import 'package:music_hub_app/core/devices/device_registrar.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localStoreProvider = Provider<LocalStore>(
  (_) => throw StateError('LocalStore must be overridden during bootstrap'),
);

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) =>
      throw StateError('SharedPreferences must be overridden during bootstrap'),
);

final audioHandlerProvider = Provider<MusicAudioHandler>(
  (_) =>
      throw StateError('MusicAudioHandler must be overridden during bootstrap'),
);

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>((ref) {
  return FirebaseAuthService(ref.watch(firebaseAuthProvider));
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthServiceProvider).authStateChanges;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(firebaseAuthProvider));
});

final eventTrackerProvider = Provider<EventTracker>((ref) {
  return EventTracker(ref.watch(apiClientProvider));
});

final deviceRegistrarProvider = Provider<DeviceRegistrar>((ref) {
  return DeviceRegistrar(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
  );
});
