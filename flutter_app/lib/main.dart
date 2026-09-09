import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'config.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: AppConfig.firebaseOptions);
  final theme = await ThemePreferenceController.load();
  ThemePreferenceController.instance = theme;
  runApp(SoundwavesApp(themeController: theme));
}
