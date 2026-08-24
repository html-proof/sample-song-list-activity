import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/app.dart';
import 'package:music_hub_app/core/audio/music_audio_handler.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
    final store = await LocalStore.open().timeout(const Duration(seconds: 15));
    final preferences = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 15),
    );
    final handler = await AudioService.init<MusicAudioHandler>(
      builder: () => MusicAudioHandler(store),
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
