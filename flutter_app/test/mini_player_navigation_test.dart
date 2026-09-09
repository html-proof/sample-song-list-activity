import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_hub/app_state.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/screens/album_details_screen.dart';
import 'package:music_hub/screens/player_screen.dart';
import 'package:music_hub/offline.dart';
import 'package:music_hub/services.dart';
import 'package:music_hub/widgets.dart';

class TestMusicApi extends MusicApi {
  TestMusicApi(super.auth);

  @override
  Future<Album> albumDetails(String albumId) async {
    return Album(
      id: albumId,
      seokey: albumId,
      title: 'Test Album Title',
      artist: 'Test Artist',
      artistIds: const [],
      imageUrl: '',
      trackCount: 1,
      tracks: [],
    );
  }

  @override
  Future<Map<String, dynamic>> albumRecommendations(String albumId) async {
    return {'items': <dynamic>[]};
  }
}

AppState createTestAppState() {
  final auth = AuthService();
  final api = TestMusicApi(auth);
  final player = PlayerController();
  final downloads = DownloadManager();
  return AppState(
    auth: auth,
    api: api,
    player: player,
    downloads: downloads,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => methodCall.method == 'init'
          ? {'id': '1'}
          : <String, dynamic>{},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  void setMobileScreenSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Track sampleTrack() {
    return Track.fromJson({
      'id': 'test-song-1',
      'seokey': 'test-song-1',
      'title': 'Test Song Title',
      'artists': 'Test Artist Name',
      'album': 'Test Album',
      'duration': '180',
      'stream_urls': {
        'urls': {'high_quality': 'https://stream.test/test.m3u8'}
      },
    });
  }

  testWidgets('MiniPlayer tap opens PlayerScreen without popping underlying screen', (tester) async {
    setMobileScreenSize(tester);
    final state = createTestAppState();
    final track = sampleTrack();
    state.player.current = track;
    state.player.duration = const Duration(seconds: 180);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Center(child: Text('Underlying Screen Content')),
          bottomNavigationBar: MiniPlayer(state: state),
        ),
      ),
    );

    expect(find.text('Underlying Screen Content'), findsOneWidget);
    expect(find.text('Test Song Title'), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);

    // Tap MiniPlayer body
    await tester.tap(find.text('Test Song Title'));
    await tester.pumpAndSettle();

    // PlayerScreen is now open
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.text('Current track'), findsOneWidget);

    // Tap collapse down-arrow button
    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();

    // PlayerScreen is closed, underlying screen is intact
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Underlying Screen Content'), findsOneWidget);
    expect(find.text('Test Song Title'), findsOneWidget);
  });

  testWidgets('AlbumDetailsScreen MiniPlayer tap pushes PlayerScreen instead of popping album screen', (tester) async {
    setMobileScreenSize(tester);
    final state = createTestAppState();
    final track = sampleTrack();
    state.player.current = track;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AlbumDetailsScreen(
                      state: state,
                      albumId: 'test-album',
                      preview: Album(
                        id: 'test-album',
                        seokey: 'test-album',
                        title: 'Test Album Title',
                        artist: 'Test Artist',
                        artistIds: const [],
                        imageUrl: '',
                        trackCount: 1,
                        tracks: [track],
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open Album'),
            ),
          ),
        ),
      ),
    );

    // Navigate to AlbumDetailsScreen
    await tester.tap(find.text('Open Album'));
    await tester.pumpAndSettle();

    expect(find.byType(AlbumDetailsScreen), findsOneWidget);
    expect(find.textContaining(RegExp(r'Test Album Title', caseSensitive: false)), findsOneWidget);

    // MiniPlayer is visible on AlbumDetailsScreen
    expect(find.byType(MiniPlayer), findsOneWidget);

    // Tap MiniPlayer on AlbumDetailsScreen
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    // PlayerScreen opens above AlbumDetailsScreen
    expect(find.byType(PlayerScreen), findsOneWidget);

    // Tap collapse down arrow
    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();

    // PlayerScreen closed, user is STILL on AlbumDetailsScreen!
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(AlbumDetailsScreen), findsOneWidget);
    expect(find.textContaining(RegExp(r'Test Album Title', caseSensitive: false)), findsOneWidget);
  });

  testWidgets('Rapidly tapping MiniPlayer pushes only ONE PlayerScreen route', (tester) async {
    setMobileScreenSize(tester);
    final state = createTestAppState();
    final track = sampleTrack();
    state.player.current = track;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Text('Home Screen'),
          bottomNavigationBar: MiniPlayer(state: state),
        ),
      ),
    );

    // Rapidly tap MiniPlayer 5 times
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Test Song Title'), warnIfMissed: false);
    }
    await tester.pumpAndSettle();

    // Only one PlayerScreen should exist
    expect(find.byType(PlayerScreen), findsOneWidget);

    // Close it once
    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();

    // Should return directly to Home Screen
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Home Screen'), findsOneWidget);
  });

  testWidgets('MiniPlayer playback buttons do NOT open PlayerScreen', (tester) async {
    setMobileScreenSize(tester);
    final state = createTestAppState();
    final track = sampleTrack();
    state.player.current = track;
    state.player.queue = [track];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Text('Home Screen'),
          bottomNavigationBar: MiniPlayer(state: state),
        ),
      ),
    );

    // Tap Play/Pause button
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.byType(PlayerScreen), findsNothing);

    // Tap Next button
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(find.byType(PlayerScreen), findsNothing);

    // Tap Previous button
    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pump();
    expect(find.byType(PlayerScreen), findsNothing);
  });
}
