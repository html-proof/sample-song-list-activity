import 'package:audio_service/audio_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/app.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/event_tracker.dart';
import 'package:music_hub_app/core/audio/music_audio_handler.dart';
import 'package:music_hub_app/core/audio/playback_source_resolver.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Firebase, Hive and SharedPreferences do not depend on each other, so the
    // three cold-start costs overlap instead of stacking. Future.wait attaches
    // its listeners synchronously, which keeps a fast failure in one of them
    // from being reported as an unhandled async error while the others run.
    final started = await Future.wait<Object?>([
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
      LocalStore.open(),
      SharedPreferences.getInstance(),
    ]).timeout(const Duration(seconds: 15));
    final store = started[1]! as LocalStore;
    final preferences = started[2]! as SharedPreferences;
    final auth = FirebaseAuth.instance;
    final api = ApiClient(auth);
    final tracker = EventTracker(api);
    final handler = await AudioService.init<MusicAudioHandler>(
      builder: () => MusicAudioHandler(
        store,
        sourceResolver: PlaybackSourceResolver(store, api: api),
        analytics: tracker,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.musichub.app.playback',
        androidNotificationChannelName: 'Music playback',
        androidNotificationOngoing: true,
      ),
    ).timeout(const Duration(seconds: 15));
    await handler.initialize().timeout(const Duration(seconds: 15));
    runApp(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(handler),
          firebaseAuthProvider.overrideWithValue(auth),
          apiClientProvider.overrideWithValue(api),
          eventTrackerProvider.overrideWithValue(tracker),
        ],
        child: const MusicHubApp(),
      ),
    );
  } catch (error) {
    runApp(_BootstrapFailure(error: error));
  }
}

class _BootstrapFailure extends StatelessWidget {
  const _BootstrapFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.build_circle_outlined, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Music Hub needs platform configuration',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
