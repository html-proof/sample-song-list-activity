import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Firebase client configuration for the registered applications.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _android,
      TargetPlatform.iOS || TargetPlatform.macOS => _ios,
      _ => throw UnsupportedError(
        'Firebase is configured for web, Android, and iOS only.',
      ),
    };
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyDKRNnrhEjbqKn5HUfg47Q5yuxYroiTbFM',
    authDomain: 'personal-songs.firebaseapp.com',
    projectId: 'personal-songs',
    storageBucket: 'personal-songs.firebasestorage.app',
    messagingSenderId: '404503869615',
    appId: '1:404503869615:web:9ffbcef5d5c638c8dc7c5a',
    measurementId: 'G-1FLJRF9P38',
  );

  static const _android = FirebaseOptions(
    apiKey: 'AIzaSyBKWWqGjEr4KZUIqgCW-uXnBdx-Z7wo-Qk',
    projectId: 'personal-songs',
    storageBucket: 'personal-songs.firebasestorage.app',
    messagingSenderId: '404503869615',
    appId: '1:404503869615:android:ae7494d0fe31e807dc7c5a',
  );

  static FirebaseOptions get _ios {
    const appId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
    const bundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
    if (appId.isEmpty || bundleId.isEmpty) {
      throw UnsupportedError(
        'Missing iOS Firebase configuration. Run flutterfire configure.',
      );
    }
    return const FirebaseOptions(
      apiKey: 'AIzaSyDKRNnrhEjbqKn5HUfg47Q5yuxYroiTbFM',
      projectId: 'personal-songs',
      storageBucket: 'personal-songs.firebasestorage.app',
      messagingSenderId: '404503869615',
      appId: appId,
      iosBundleId: bundleId,
    );
  }
}
