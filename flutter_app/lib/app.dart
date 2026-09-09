import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'screens/language_selection_screen.dart';
import 'screens/main_shell.dart';
import 'screens/welcome_screen.dart';
import 'services.dart';
import 'offline.dart';
import 'network_policy.dart';
import 'theme.dart';
import 'cache/audio_cache.dart';
import 'cache/cache_cleanup.dart';
import 'cache/prefetch_manager.dart';
import 'cache/segment_downloader.dart';

class SoundwavesApp extends StatefulWidget {
  const SoundwavesApp({super.key, required this.themeController});
  final ThemePreferenceController themeController;

  @override
  State<SoundwavesApp> createState() => _SoundwavesAppState();
}

class _SoundwavesAppState extends State<SoundwavesApp> with WidgetsBindingObserver {
  late final AuthService _auth;
  late final MusicApi _api;
  late final PlayerController _player;
  late final DownloadManager _downloads;
  late final AudioCache _audioCache;
  late final QueuePrefetchManager _prefetchManager;
  late final CacheCleanupWorker _cleanupWorker;
  late final AppState _state;
  late final DataUsagePolicy _policy;
  late final ConnectionMonitor _connection;
  final _notifications = NotificationService();
  int _stage = 0;
  bool _navigationInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.themeController.addListener(_refresh);
    _auth = AuthService();
    _policy = DataUsagePolicy();
    _connection = ConnectionMonitor();
    _downloads = DownloadManager(connection: _connection, policy: _policy);
    _audioCache = AudioCache();
    final downloader = SegmentDownloader();
    _prefetchManager = QueuePrefetchManager(
      audioCache: _audioCache,
      downloader: downloader,
      policy: _policy,
      connection: _connection,
    );
    _cleanupWorker = CacheCleanupWorker(_audioCache);
    _api = MusicApi(_auth, policy: _policy, connection: _connection);
    _player = PlayerController(
      policy: _policy,
      connection: _connection,
      downloads: _downloads,
      audioCache: _audioCache,
      prefetchManager: _prefetchManager,
    )..resolveTrack = _api.resolvePlayableTrack;
    _state = AppState(
      auth: _auth,
      api: _api,
      player: _player,
      downloads: _downloads,
      audioCache: _audioCache,
    )..addListener(_refresh);
    _initialize();
  }

  Future<void> _initialize() async {
    // Wait for the native media session before exposing the player. Starting
    // it in the background creates a race where the first song uses the
    // foreground-only player and never appears on the lock screen.
    await _player.initializeBackgroundAudio();
    await _auth.initialize();
    await _policy.load();
    await _audioCache.initialize();
    _cleanupWorker.startPeriodicCleanup();
    await _state.restoreLocal();
    if (_state.onboardingCompleted) {
      _go(4);
    } else if (_auth.isSignedIn) {
      _go(2);
    } else {
      _go(1);
    }
    unawaited(_backgroundInitialize());
  }

  Future<void> _backgroundInitialize() async {
    await _connection.start();
    if (!kIsWeb) {
      try {
        await _notifications.initialize();
      } catch (_) {}
    }
    if (_auth.isSignedIn) {
      try {
        await _api.ensureAccount();
        await _notifications.registerWithBackend(_api);
        final me = await _api.me();
        _state.applyProfile(me);
        await _state.persistLocal();
        if (_state.onboardingCompleted) unawaited(_state.bootstrap());
      } catch (_) {
        // Cached Home remains usable while the backend is unavailable.
      }
    }
  }

  void _refresh() {
    if (!mounted) return;
    if (!_auth.isSignedIn && _stage == 4 && !_state.onboardingCompleted) {
      setState(() => _stage = 1);
    } else {
      setState(() {});
    }
  }

  void _go(int stage) {
    if (!mounted) return;
    setState(() => _stage = stage);
  }

  Future<void> _finishOnboarding() async {
    if (_navigationInProgress) return;
    _navigationInProgress = true;
    _go(4);
    try {
      await _state.saveArtistPreferences();
      await _state.bootstrap();
    } catch (_) {
    } finally {
      _navigationInProgress = false;
    }
  }

  Future<void> _openArtists() async {
    if (_navigationInProgress) return;
    _navigationInProgress = true;
    try {
      _go(3);
      if (_state.onboardingArtists.isEmpty) {
        unawaited(_state.loadOnboardingArtists());
      }
    } catch (exception) {
      _state.error = '$exception';
    } finally {
      _navigationInProgress = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_player.persistStateNow());
      unawaited(_state.persistLocal());
    } else if (state == AppLifecycleState.resumed) {
      _state.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_player.persistStateNow());
    unawaited(_state.persistLocal());
    widget.themeController.removeListener(_refresh);
    _state.removeListener(_refresh);
    _state.dispose();
    _cleanupWorker.dispose();
    _player.dispose();
    _auth.dispose();
    _policy.dispose();
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Hub',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: NotificationService.messengerKey,
      theme: soundwavesTheme(),
      darkTheme: soundwavesTheme(brightness: Brightness.dark),
      themeMode: widget.themeController.preference.themeMode,
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: SizedBox(
              width: constraints.maxWidth.clamp(0.0, 520.0),
              height: constraints.maxHeight,
              child: ClipRect(child: child ?? const SizedBox.shrink()),
            ),
          ),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: switch (_stage) {
          0 => const _MusicHubSplash(key: ValueKey('splash')),
          1 => WelcomeScreen(
            key: const ValueKey('welcome'),
            state: _state,
            onContinue: () => _go(2),
          ),
          2 => LanguageSelectionScreen(
            key: const ValueKey('language'),
            state: _state,
            onBack: () => _go(1),
            onContinue: _openArtists,
          ),
          3 => ArtistPickerScreen(
            key: const ValueKey('artists'),
            state: _state,
            onBack: () => _go(2),
            onDone: _finishOnboarding,
          ),
          _ => MainShell(key: const ValueKey('main'), state: _state),
        },
      ),
    );
  }
}

class _MusicHubSplash extends StatelessWidget {
  const _MusicHubSplash({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _WavePainter())),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _HubMark(size: 58),
                const SizedBox(height: 18),
                Text(
                  'Music Hub',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Feel the Rhythm.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HubMark extends StatelessWidget {
  const _HubMark({this.size = 42});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(7, (index) {
        const heights = [.28, .58, .84, 1.0, .76, .52, .25];
        return Container(
          width: size * .075,
          height: size * heights[index],
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }),
    ),
  );
}

class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.orange.withValues(alpha: .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(
        Offset(size.width * .82, size.height * .1),
        36.0 + i * 17,
        paint,
      );
      canvas.drawCircle(
        Offset(size.width * .18, size.height * .88),
        30.0 + i * 15,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
