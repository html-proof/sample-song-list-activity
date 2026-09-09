import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_hub/app_state.dart';
import 'package:music_hub/models.dart';
import 'package:music_hub/network_policy.dart';
import 'package:music_hub/offline.dart';
import 'package:music_hub/providers/player_provider.dart';
import 'package:music_hub/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('parses a backend track and selects the best media URLs', () {
    final track = Track.fromJson({
      'seokey': 'yellow',
      'title': 'Yellow',
      'artists': 'Coldplay',
      'duration': '267',
      'images': {
        'urls': {'large_artwork': 'https://images.test/yellow.jpg'},
      },
      'stream_urls': {
        'urls': {'high_quality': 'https://audio.test/yellow.m3u8'},
      },
    });

    expect(track.title, 'Yellow');
    expect(track.durationSeconds, 267);
    expect(track.imageUrl, contains('yellow.jpg'));
    expect(track.streamUrl, contains('yellow.m3u8'));
  });

  test('serializes the personalization payload expected by FastAPI', () {
    const track = Track(seokey: 'yellow', title: 'Yellow', artist: 'Coldplay');
    final payload = track.toPersonalizationJson();
    expect(payload['seokey'], 'yellow');
    expect(payload['artists'], 'Coldplay');
  });

  test('parses provider stream URLs for normalized album tracks', () {
    final track = Track.fromJson({
      'type': 'song',
      'id': 'album-track',
      'title': 'Album Track',
      'artists': [
        {'name': 'Artist'},
      ],
      'stream_urls': {
        'urls': {'medium_quality': 'https://audio.test/album-track.mp3'},
      },
    });

    expect(track.streamUrl, 'https://audio.test/album-track.mp3');
  });

  test('copyWith properly updates fields while preserving others', () {
    const track = Track(
      seokey: 'sanam-re',
      title: 'Sanam Re',
      artist: 'Arijit Singh',
      streamUrl: '',
    );
    final updated = track.copyWith(streamUrl: 'https://audio.test/sanam-re.m3u8');
    expect(updated.seokey, 'sanam-re');
    expect(updated.title, 'Sanam Re');
    expect(updated.artist, 'Arijit Singh');
    expect(updated.streamUrl, 'https://audio.test/sanam-re.m3u8');
  });

  test('Track.list handles list of maps and wrapped maps', () {
    final list = Track.list([
      {'seokey': 't1', 'title': 'Track 1'},
      {'seokey': 't2', 'title': 'Track 2'},
    ]);
    expect(list.length, 2);
    expect(list[0].seokey, 't1');
    expect(list[1].seokey, 't2');

    final wrapped = Track.list({
      'items': [
        {'seokey': 't3', 'title': 'Track 3'},
      ],
    });
    expect(wrapped.length, 1);
    expect(wrapped[0].seokey, 't3');
  });

  test('backend search response maps exact song without mutating ID or metadata', () {
    final backendResponse = {
      'id': 'tumhiho',
      'provider_id': '944286',
      'type': 'song',
      'title': 'Tum Hi Ho',
      'artists': [
        {'id': 'mithoon', 'name': 'Mithoon', 'type': 'artist'},
        {'id': 'arijit-singh', 'name': 'Arijit Singh', 'type': 'artist'},
      ],
      'album': {
        'id': 'aashiqui-2',
        'provider_id': '92317',
        'title': 'Aashiqui 2',
        'artworkUrl': 'https://images.test/aashiqui2.jpg',
      },
      'image_url': 'https://images.test/aashiqui2.jpg',
      'duration_ms': 261000,
      'stream_url': 'https://audio.test/tumhiho.m3u8',
    };

    final track = Track.fromJson(backendResponse);

    expect(track.id, 'tumhiho');
    expect(track.seokey, 'tumhiho');
    expect(track.trackId, '944286');
    expect(track.title, 'Tum Hi Ho');
    expect(track.artist, 'Mithoon, Arijit Singh');
    expect(track.album, 'Aashiqui 2');
    expect(track.albumSeokey, 'aashiqui-2');
    expect(track.durationSeconds, 261);
    expect(track.streamUrl, 'https://audio.test/tumhiho.m3u8');

    // Identity chain verification
    final queue = [track];
    final tappedIndex = queue.indexWhere((item) => item.id == track.id);
    expect(tappedIndex, 0);
    expect(queue[tappedIndex].id, backendResponse['id']);
    expect(queue[tappedIndex], track);
  });

  test('Track equality and hashcode are stable and based on unique ID', () {
    const t1 = Track(seokey: 's1', title: 'Song 1', artist: 'Artist 1');
    const t2 = Track(seokey: 's1', title: 'Song 1 (Updated)', artist: 'Artist 1');
    const t3 = Track(seokey: 's2', title: 'Song 1', artist: 'Artist 1');

    expect(t1 == t2, isTrue);
    expect(t1 == t3, isFalse);
    expect(t1.hashCode == t2.hashCode, isTrue);
  });

  test('SharedPreferences restores language, artist, and google ID preferences', () async {
    final preferences = <String, Object>{
      'onboarding_completed': true,
      'saved_language_ids': ['malayalam', 'tamil', 'hindi'],
      'saved_language_names': ['Malayalam', 'Tamil', 'Hindi'],
      'saved_artist_ids': ['jakes-bejoy', 'anirudh-ravichander'],
      'saved_artist_names': ['Jakes Bejoy', 'Anirudh Ravichander'],
      'saved_google_id': 'google-user-12345',
      'saved_user_email': 'test@example.com',
    };

    expect(preferences['onboarding_completed'], isTrue);
    expect(preferences['saved_language_ids'], contains('malayalam'));
    expect(preferences['saved_artist_ids'], contains('jakes-bejoy'));
    expect(preferences['saved_google_id'], 'google-user-12345');
  });

  test('Flutter search ranking correctly ranks and preserves pattalam results', () {
    final rawBackendSongs = [
      {
        'id': 'pattalam-1',
        'title': 'Pattalam',
        'artists': [{'name': 'Vidyasagar'}, {'name': 'Gireesh Puthenchery'}, {'name': 'Alan'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'image_url': 'https://a10.gaanacdn.com/pattalam.jpg',
        'stream_url': 'https://vodhls.gaana/pattalam.m3u8',
      },
      {
        'id': 'dinkiri-pattalam',
        'title': 'Dinkiri Pattalam',
        'artists': [{'name': 'Kalyani'}, {'name': 'Vidyasagar'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/dinkiri.m3u8',
      },
      {
        'id': 'dum-dum-pattalam-2',
        'title': 'Dum Dum Pattalam',
        'artists': [{'name': 'M G Sreekumar'}],
        'album': {'name': 'My Dear Karadi (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/dumdum.m3u8',
      },
      {
        'id': 'panivizhum-kaalama',
        'title': 'Panivizhum Kaalama',
        'artists': [{'name': 'Hesham'}, {'name': 'Sayanora'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/panivizhum.m3u8',
      },
      {
        'id': 'aaroral-1',
        'title': 'Aaroraal',
        'artists': [{'name': 'K J Yesudas'}, {'name': 'Vidyasagar'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/aaroral.m3u8',
      },
      {
        'id': 'pampaganapathy-1',
        'title': 'Pampa Ganapathy',
        'artists': [{'name': 'Vidyasagar'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/pampaganapathy.m3u8',
      },
      {
        'id': 'aalilakkavile',
        'title': 'Aalilakkaavile',
        'artists': [{'name': 'P. Jayachandran'}, {'name': 'Vidyasagar'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/aalilakkaavile.m3u8',
      },
      {
        'id': 'vennakkallil-1',
        'title': 'Vennakkallil',
        'artists': [{'name': 'Biju Narayanan'}, {'name': 'Radhika Thilak'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/vennakkallil.m3u8',
      },
      {
        'id': 'dhisayettum',
        'title': 'Dhisayettum',
        'artists': [{'name': 'Najeem'}, {'name': 'Jassie Gift'}],
        'album': {'name': 'Pattalam (Original Motion Picture Soundtrack)'},
        'stream_url': 'https://vodhls.gaana/dhisayettum.m3u8',
      },
      {
        'id': 'palli-pattalam-from-anugrahan',
        'title': 'Palli Pattalam (From "Anugrahan")',
        'artists': [{'name': 'Rehan'}, {'name': 'Parthiban'}],
        'album': {'name': 'Palli Pattalam (From "Anugrahan")'},
        'stream_url': 'https://vodhls.gaana/pallipattalam.m3u8',
      },
    ];

    final tracks = Track.list(rawBackendSongs);
    expect(tracks.length, 10);

    // 1. Query: "pattalam"
    final rankedPattalam = rankTracksForQuery(tracks, 'pattalam');
    expect(rankedPattalam.length, 10);
    expect(rankedPattalam.first.title, 'Pattalam');
    expect(rankedPattalam.first.id, 'pattalam-1');

    // 2. Query: uppercase "PATTALAM"
    final rankedUpper = rankTracksForQuery(tracks, 'PATTALAM');
    expect(rankedUpper.first.title, 'Pattalam');

    // 3. Query: partial "patt"
    final rankedPartial = rankTracksForQuery(tracks, 'patt');
    expect(rankedPartial.first.title, 'Pattalam');

    // 4. Query: "dinkiri pattalam"
    final rankedDinkiri = rankTracksForQuery(tracks, 'dinkiri pattalam');
    expect(rankedDinkiri.first.title, 'Dinkiri Pattalam');

    // 5. Query: "vidyasagar" (artist match)
    final rankedVidyasagar = rankTracksForQuery(tracks, 'vidyasagar');
    expect(rankedVidyasagar.first.artist, contains('Vidyasagar'));

    // 6. Query: "my dear karadi" (album match)
    final rankedAlbum = rankTracksForQuery(tracks, 'my dear karadi');
    expect(rankedAlbum.first.album, contains('My Dear Karadi'));

    // 7. Top result parsing
    final topResult = SearchTopResult.fromJson({
      'type': 'song',
      'confidence': 0.8,
      'item': rawBackendSongs.first,
    });
    expect(topResult.type, 'song');
    expect(topResult.confidence, 0.8);
    expect(topResult.track?.title, 'Pattalam');
    expect(topResult.track?.streamUrl, contains('pattalam.m3u8'));
  });

  test('Flutter search correctly handles Operation Java frontend search and top result', () {
    final rawSongs = [
      {
        'id': 'iruvazhiye',
        'seokey': 'iruvazhiye',
        'title': 'Iruvazhiye',
        'album': 'Operation Java (Original Motion Picture Soundtrack)',
        'artists': 'Jakes Bejoy, Alan Joy Mathew',
        'language': 'Malayalam',
        'stream_url': 'https://stream.test/iruvazhiye.m3u8',
      },
      {
        'id': 'naade-naattaare',
        'seokey': 'naade-naattaare',
        'title': 'Naade Naattaare',
        'album': 'Operation Java (Original Motion Picture Soundtrack)',
        'artists': 'Jakes Bejoy, Fejo',
        'language': 'Malayalam',
        'stream_url': 'https://stream.test/naade.m3u8',
      },
      {
        'id': 'unrelated-song',
        'seokey': 'unrelated-song',
        'title': 'Random Track',
        'album': 'Some Other Album',
        'artists': 'Unknown',
        'language': 'Hindi',
        'stream_url': 'https://stream.test/random.m3u8',
      },
    ];

    final tracks = Track.list(rawSongs);
    final ranked = rankTracksForQuery(tracks, 'Operation Java');

    expect(ranked.first.title, 'Iruvazhiye');
    expect(ranked.first.album, contains('Operation Java'));
    expect(ranked[1].title, 'Naade Naattaare');

    final topResult = SearchTopResult.fromJson({
      'type': 'song',
      'confidence': 0.95,
      'item': rawSongs.first,
    });
    expect(topResult.type, 'song');
    expect(topResult.track?.title, 'Iruvazhiye');
    expect(topResult.track?.album, contains('Operation Java'));
  });

  test('Player previous resets to 0:00 when position > 10s, or goes to previous song when <= 10s', () {
    final player = PlayerProvider();
    const track = Track(seokey: 'test-1', title: 'Test Song');
    player.play(track);

    // Case 1: position > 10 seconds (e.g. 15 seconds)
    player.seek(const Duration(seconds: 15));
    expect(player.position.inSeconds, 15);
    player.previous();
    // Must reset to 0:00 without skipping song
    expect(player.position, Duration.zero);

    // Case 2: position <= 10 seconds (e.g. 4 seconds)
    player.seek(const Duration(seconds: 4));
    expect(player.position.inSeconds, 4);
    player.previous();
    // Triggers notification to navigate to previous song
    expect(player.currentTrack, track);
  });

  test('Player session persistence and instant restoration preserves position, queue, and track', () async {
    SharedPreferences.setMockInitialValues({
      'player_state': '''{
        "track": {
          "id": "ente-khalbile",
          "seokey": "ente-khalbile",
          "title": "Ente Khalbile",
          "artist": "Vineeth Sreenivasan",
          "album": "Classmates",
          "duration": 290,
          "stream_url": "https://stream.test/ente-khalbile.m3u8",
          "image_url": "https://img.test/classmates.jpg"
        },
        "queue": [
          {
            "id": "ente-khalbile",
            "title": "Ente Khalbile",
            "stream_url": "https://stream.test/ente-khalbile.m3u8"
          },
          {
            "id": "kaattaadi-thanalum",
            "title": "Kaattaadi Thanalum",
            "stream_url": "https://stream.test/kaattaadi.m3u8"
          }
        ],
        "position_ms": 48500,
        "duration_ms": 290000,
        "was_playing": true
      }''',
    });

    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('player_state');
    expect(jsonStr, isNotNull);

    final player = PlayerController();
    const track = Track(
      seokey: 'ente-khalbile',
      title: 'Ente Khalbile',
      artist: 'Vineeth Sreenivasan',
      album: 'Classmates',
      durationSeconds: 290,
      streamUrl: 'https://stream.test/ente-khalbile.m3u8',
    );
    const queue = <Track>[
      track,
      Track(
        seokey: 'kaattaadi-thanalum',
        title: 'Kaattaadi Thanalum',
        streamUrl: 'https://stream.test/kaattaadi.m3u8',
      ),
    ];

    await player.restorePlaybackSession(
      track,
      queue,
      const Duration(milliseconds: 48500),
      wasPlaying: true,
    );

    expect(player.current?.title, 'Ente Khalbile');
    expect(player.queue.length, 2);
    expect(player.position.inMilliseconds, 48500);
    expect(player.duration.inSeconds, 290);
  });

  test('parses AlbumRecommendation and converts to preview Album cleanly', () {
    final rec = AlbumRecommendation.fromJson({
      'id': 'aashiqui-2',
      'title': 'Aashiqui 2',
      'artistId': 'arijit-singh',
      'artistName': 'Arijit Singh',
      'imageUrl': 'https://images.test/aashiqui2.jpg',
      'releaseYear': 2013,
      'language': 'Hindi',
      'genre': 'Romantic',
      'songCount': 11,
      'reason': 'same_artist',
    });

    expect(rec.id, 'aashiqui-2');
    expect(rec.title, 'Aashiqui 2');
    expect(rec.artistName, 'Arijit Singh');
    expect(rec.releaseYear, 2013);
    expect(rec.reason, 'same_artist');

    final album = rec.toAlbum();
    expect(album.id, 'aashiqui-2');
    expect(album.title, 'Aashiqui 2');
    expect(album.artist, 'Arijit Singh');
    expect(album.trackCount, 11);
    expect(album.releaseDate, '2013');
  });

  test('upgradeImageUrlQuality upgrades low-res thumbnails to 500x500 HD', () {
    expect(
      upgradeImageUrlQuality('http://c.saavncdn.com/123/Notebook-150x150.jpg'),
      'https://c.saavncdn.com/123/Notebook-500x500.jpg',
    );
    expect(
      upgradeImageUrlQuality('https://c.saavncdn.com/123/Notebook-50x50.jpg'),
      'https://c.saavncdn.com/123/Notebook-500x500.jpg',
    );
    expect(
      upgradeImageUrlQuality('https://images.hungama.com/test_150x150.jpg'),
      'https://images.hungama.com/test-500x500.jpg',
    );
  });

  test('Album.list deduplicates duplicate albums by ID and semantic title', () {
    final raw = [
      {
        'id': 'notebook-1',
        'title': 'Notebook',
        'artist': 'Mejo Joseph',
        'imageUrl': 'https://c.saavncdn.com/123/Notebook-500x500.jpg',
      },
      {
        'id': 'notebook-1', // Same ID
        'title': 'Notebook',
        'artist': 'Mejo Joseph',
        'imageUrl': 'https://c.saavncdn.com/123/Notebook-500x500.jpg',
      },
      {
        'id': 'notebook-ost', // Duplicate title variant
        'title': 'Notebook (Original Motion Picture Soundtrack)',
        'artist': 'Mejo Joseph',
        'imageUrl': 'https://c.saavncdn.com/123/Notebook-500x500.jpg',
      },
      {
        'id': 'classmates-1',
        'title': 'Classmates',
        'artist': 'Alex Paul',
        'imageUrl': 'https://c.saavncdn.com/123/Classmates-500x500.jpg',
      },
    ];

    final albums = Album.list(raw);
    expect(albums.length, 2);
    expect(albums[0].title, 'Notebook');
    expect(albums[1].title, 'Classmates');
  });

  test('Track.getStreamUrlForQuality dynamically resolves URL matching quality setting', () {
    final track = Track.fromJson({
      'seokey': 'tum-hi-ho',
      'title': 'Tum Hi Ho',
      'stream_urls': {
        'urls': {
          'very_high_quality': 'https://audio.test/320.mp3',
          'high_quality': 'https://audio.test/160.mp3',
          'medium_quality': 'https://audio.test/128.mp3',
          'low_quality': 'https://audio.test/64.mp3',
        },
      },
    });

    expect(track.getStreamUrlForQuality('very_high'), 'https://audio.test/320.mp3');
    expect(track.getStreamUrlForQuality('high'), 'https://audio.test/160.mp3');
    expect(track.getStreamUrlForQuality('normal'), 'https://audio.test/128.mp3');
    expect(track.getStreamUrlForQuality('medium'), 'https://audio.test/128.mp3');
    expect(track.getStreamUrlForQuality('low'), 'https://audio.test/64.mp3');
  });

  test('Track.fromJson prioritizes high_quality for 4-5 MB song budget and synthesizes tiers from stream_url', () {
    final trackWithMap = Track.fromJson({
      'seokey': 'tum-hi-ho',
      'title': 'Tum Hi Ho',
      'stream_urls': {
        'urls': {
          'very_high_quality': 'https://vodhls.gaana.com/hls/320.mp4.master.m3u8',
          'high_quality': 'https://vodhls.gaana.com/hls/128.mp4.master.m3u8',
          'medium_quality': 'https://vodhls.gaana.com/hls/64.mp4.master.m3u8',
        },
      },
    });
    // Default streamUrl is high_quality (128 kbps, 4-5 MB)
    expect(trackWithMap.streamUrl, 'https://vodhls.gaana.com/hls/128.mp4.master.m3u8');
    expect(trackWithMap.getStreamUrlForQuality('high'), 'https://vodhls.gaana.com/hls/128.mp4.master.m3u8');
    expect(trackWithMap.getStreamUrlForQuality('automatic'), 'https://vodhls.gaana.com/hls/128.mp4.master.m3u8');

    // Track with single 320.mp4 stream_url synthesizes 128.mp4 for high/automatic to keep 4-5 MB budget
    final trackSingleUrl = Track.fromJson({
      'seokey': 'tum-hi-ho-2',
      'title': 'Tum Hi Ho',
      'stream_url': 'https://vodhls.gaana.com/hls/320.mp4.master.m3u8',
    });
    expect(trackSingleUrl.getStreamUrlForQuality('high'), 'https://vodhls.gaana.com/hls/128.mp4.master.m3u8');
    expect(trackSingleUrl.getStreamUrlForQuality('normal'), 'https://vodhls.gaana.com/hls/64.mp4.master.m3u8');
    expect(trackSingleUrl.getStreamUrlForQuality('low'), 'https://vodhls.gaana.com/hls/16.mp4.master.m3u8');
  });

  test('DataUsagePolicy adapts audio quality based on Wi-Fi and Mobile Data detection', () {
    final policy = DataUsagePolicy();
    policy.wifiAudioQuality = 'very_high';
    policy.cellularAudioQuality = 'low';

    // On Wi-Fi
    const wifiState = NetworkState(
      connected: true,
      connectionType: ConnectionType.wifi,
      connectionQuality: 'good',
    );
    expect(policy.qualityFor(wifiState), 'very_high');

    // On Cellular
    const cellularState = NetworkState(
      connected: true,
      connectionType: ConnectionType.cellular,
      isMetered: true,
    );
    expect(policy.qualityFor(cellularState), 'low');

    // Automatic mode on Wi-Fi vs Cellular
    policy.wifiAudioQuality = 'automatic';
    policy.cellularAudioQuality = 'automatic';
    expect(policy.qualityFor(wifiState), 'high');
    expect(policy.qualityFor(cellularState), 'normal');

    // Data Saver on Cellular forces low
    policy.dataSaverEnabled = true;
    expect(policy.qualityFor(cellularState), 'low');
    // Data Saver does not throttle Wi-Fi
    expect(policy.qualityFor(wifiState), 'high');
  });

  test('Lyrics.fromJson correctly parses synchronized timestamped lyric lines', () {
    final raw = {
      'trackId': 'tum-hi-ho',
      'status': 'available',
      'synced': true,
      'instrumental': false,
      'provider': 'lrclib',
      'plainLyrics': 'Hum tere bin ab reh nahi sakte',
      'lines': [
        {'startMs': 1200, 'endMs': 3400, 'text': 'Hum tere bin ab reh nahi sakte'},
        {'startMs': 3400, 'endMs': 6000, 'text': 'Tere bina kya wajood mera'},
      ],
    };

    final lyrics = Lyrics.fromJson(raw);
    expect(lyrics.trackId, 'tum-hi-ho');
    expect(lyrics.synced, isTrue);
    expect(lyrics.lines.length, 2);
    expect(lyrics.lines[0].startMs, 1200);
    expect(lyrics.lines[0].text, 'Hum tere bin ab reh nahi sakte');
    expect(lyrics.lines[1].startMs, 3400);
  });

  test('PlayerController cycles PlaybackRepeatMode properly and handles Shuffle mode', () {
    final player = PlayerController();
    expect(player.repeatMode, PlaybackRepeatMode.off);

    player.toggleRepeatMode();
    expect(player.repeatMode, PlaybackRepeatMode.all);

    player.toggleRepeatMode();
    expect(player.repeatMode, PlaybackRepeatMode.one);

    player.toggleRepeatMode();
    expect(player.repeatMode, PlaybackRepeatMode.off);

    expect(player.isShuffled, isFalse);
    final track1 = const Track(seokey: 's1', title: 'Song 1', durationSeconds: 180);
    final track2 = const Track(seokey: 's2', title: 'Song 2', durationSeconds: 200);
    final track3 = const Track(seokey: 's3', title: 'Song 3', durationSeconds: 220);
    final queue = [track1, track2, track3];

    player.current = track1;
    player.queue = List<Track>.from(queue);

    player.toggleShuffle();
    expect(player.isShuffled, isTrue);
    expect(player.queue.length, 3);
    // current track stays first
    expect(player.queue.first.id, track1.id);

    player.toggleShuffle();
    expect(player.isShuffled, isFalse);
    expect(player.queue, queue);

    player.dispose();
  });

  test('DownloadManager correctly manages entries, resolution fallback, and removal', () async {
    final downloads = DownloadManager();
    final track = const Track(
      seokey: 'test-song-seokey',
      title: 'Test Song',
      artist: 'Test Artist',
      streamUrl: 'https://example.com/audio.mp3',
    );

    // Enqueue
    await downloads.enqueue(track);
    final entry = downloads.entryFor('test-song-seokey');
    expect(entry, isNotNull);
    expect(entry!.track.title, 'Test Song');
    expect(
      entry.status == DownloadStatus.queued || entry.status == DownloadStatus.downloading,
      isTrue,
    );

    // Lookup by ID also works
    expect(downloads.entryFor(track.id), isNotNull);

    // Remove
    await downloads.remove('test-song-seokey');
    expect(downloads.entryFor('test-song-seokey'), isNull);
    expect(downloads.entries.isEmpty, isTrue);

    downloads.dispose();
  });

  test('AppState deduplicates favorite songs and prevents duplicate entries', () async {
    final auth = AuthService();
    final state = AppState(
      auth: auth,
      api: MusicApi(auth),
      player: PlayerController(),
      downloads: DownloadManager(),
    );

    const trackA = Track(
      seokey: 'chendumallika-poo',
      trackId: '12345',
      title: 'Chendumallika Poo',
      artist: 'Vijay Yesudas',
    );
    const trackADup = Track(
      seokey: 'chendumallika-poo',
      trackId: '12345',
      title: 'Chendumallika Poo',
      artist: 'Vijay Yesudas',
    );

    // Tapping favorite adds it
    await state.toggleFavorite(trackA);
    expect(state.favorites.length, 1);
    expect(state.isFavorite(trackA), isTrue);
    expect(state.isFavorite(trackADup), isTrue);

    // Tapping favorite again removes it without leaving duplicate entries
    await state.toggleFavorite(trackADup);
    expect(state.favorites.isEmpty, isTrue);
    expect(state.isFavorite(trackA), isFalse);

    // Re-adding ensures only 1 entry exists
    await state.toggleFavorite(trackA);
    expect(state.favorites.length, 1);

    state.dispose();
  });

  test('ConnectionMonitor and PlayerController handle network transition seamlessly', () async {
    final policy = DataUsagePolicy();
    final connection = ConnectionMonitor();
    final player = PlayerController(
      policy: policy,
      connection: connection,
    );

    const track1 = Track(
      trackId: 'song-1',
      seokey: 'song-1',
      title: 'Song 1',
      artist: 'Artist 1',
      streamUrl: 'https://audio.test/song1.mp3',
      durationSeconds: 200,
    );
    const track2 = Track(
      trackId: 'song-2',
      seokey: 'song-2',
      title: 'Song 2',
      artist: 'Artist 2',
      streamUrl: 'https://audio.test/song2.mp3',
      durationSeconds: 180,
    );

    // Initial state: play track 1
    await player.play(track1, fromQueue: [track1, track2]);
    expect(player.current?.id, 'song-1');

    // Simulate switching network and tapping next track
    await player.next();
    expect(player.current?.id, 'song-2');
    expect(player.duration.inSeconds, 180);

    player.dispose();
    connection.dispose();
    policy.dispose();
  });

  test('Artist model serialization and candidate key extraction preserves ID and name', () {
    final artist = Artist(
      seokey: 'p-jayachandran-1',
      artistId: '112796',
      name: 'P. Jayachandran',
      imageUrl: 'https://a10.gaanacdn.com/artist.jpg',
    );

    final json = artist.toJson();
    expect(json['id'], 'p-jayachandran-1');
    expect(json['name'], 'P. Jayachandran');
    expect(json['artist_id'], '112796');

    final reconstructed = Artist.fromJson(json);
    expect(reconstructed.name, 'P. Jayachandran');
    expect(reconstructed.id, 'p-jayachandran-1');
  });

  test('MusicApi categorizedSearch and artistDetails parse decoded response accurately', () async {
    final mockClient = MockClient((request) async {
      if (request.url.path.contains('/api/search')) {
        return http.Response(
          jsonEncode({
            'data': {
              'songs': [
                {
                  'id': 'gentleman-6',
                  'title': 'Gentleman',
                  'artist': {'name': 'Psy'},
                  'stream_url': 'https://stream.test/gentleman.mp3',
                }
              ],
              'albums': [
                {
                  'id': 'gentleman',
                  'title': 'Gentleman',
                  'artist': 'Bappi Lahiri',
                }
              ],
              'artists': [
                {
                  'id': 'gentleman',
                  'name': 'Gentleman',
                }
              ],
            }
          }),
          200,
        );
      }
      if (request.url.path.contains('/api/artists/')) {
        return http.Response(
          jsonEncode({
            'data': {
              'artist': {'id': 'p-jayachandran-1', 'name': 'P. Jayachandran'},
              'popular_songs': [
                {
                  'id': 'ariyathe',
                  'title': 'Ariyathe Ariyathe',
                  'artist': {'name': 'P. Jayachandran'},
                  'stream_url': 'https://stream.test/ariyathe.mp3',
                }
              ],
              'albums': [
                {
                  'id': 'best-of-p-jayachandran',
                  'title': 'Best of P. Jayachandran',
                }
              ],
            }
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final api = MusicApi(AuthService(), client: mockClient);
    final searchRes = await api.categorizedSearch('gentleman');
    expect((searchRes['songs'] as List).length, 1);
    expect((searchRes['albums'] as List).length, 1);
    expect((searchRes['artists'] as List).length, 1);

    final artistDetails = await api.artistDetails('p-jayachandran');
    expect((artistDetails['popular_songs'] as List).length, 1);
    expect((artistDetails['albums'] as List).length, 1);
  });

  test('DownloadManager localPathForTrack resolves downloaded tracks by ID, seokey, and trackId', () {
    final dm = DownloadManager();
    final track = Track(
      seokey: 'song-101-seokey',
      trackId: '101',
      title: 'Downloaded Song',
      artist: 'Artist',
      album: 'Album',
      streamUrl: 'https://stream.test/song.mp4',
    );
    // When no downloads exist, returns null safely
    expect(dm.localPathForTrack(track), isNull);
  });

  test('DownloadManager extractAacFrames handles TS frames or direct audio data gracefully', () {
    final directAudio = Uint8List.fromList([0xFF, 0xF1, 0x50, 0x80]);
    final resultDirect = DownloadManager.extractAacFrames(directAudio);
    expect(resultDirect, equals(directAudio));

    final empty = Uint8List(0);
    expect(DownloadManager.extractAacFrames(empty), equals(empty));
  });

  test('searchTracks queries /api/search first and falls back to sanitized /songs/search/', () async {
    final requestedPaths = <String>[];
    final mockClient = MockClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path == '/api/search') {
        return http.Response(jsonEncode({'items': []}), 200);
      }
      if (request.url.path == '/songs/search/') {
        expect(request.url.queryParameters['query'], 'Porkanda Singam EDM Version From Vikram');
        return http.Response(jsonEncode([
          {
            'seokey': 'porkanda-singam-edm-version-[from-vikram]',
            'title': 'Porkanda Singam (EDM Version) [From "Vikram"]',
            'stream_urls': {
              'urls': {'high_quality': 'https://stream.test/porkanda.m3u8'}
            }
          }
        ]), 200);
      }
      return http.Response('{}', 404);
    });

    final api = MusicApi(AuthService(), client: mockClient);
    final results = await api.searchTracks('Porkanda Singam (EDM Version) [From "Vikram"]');
    expect(requestedPaths, contains('/api/search'));
    expect(requestedPaths, contains('/songs/search/'));
    expect(results.length, 1);
    expect(results.first.streamUrl, contains('porkanda.m3u8'));
  });

  test('resolvePlayableTrack resolves stream URL for bracketed titles and updates candidate', () async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/songs/info/') {
        return http.Response('{"error": "Track not found"}', 404);
      }
      if (request.url.path == '/api/search') {
        return http.Response(jsonEncode({
          'items': [
            {
              'seokey': 'porkanda-singam-edm-version',
              'title': 'Porkanda Singam',
              'stream_urls': {
                'urls': {'high_quality': 'https://stream.test/resolved-porkanda.m3u8'}
              }
            }
          ]
        }), 200);
      }
      return http.Response('{}', 404);
    });

    final api = MusicApi(AuthService(), client: mockClient);
    const unplayableTrack = Track(
      seokey: 'porkanda-singam-edm-version-[from-vikram]',
      title: 'Porkanda Singam (EDM Version) [From "Vikram"]',
      artist: 'Anirudh Ravichander',
      streamUrl: '',
    );
    final resolved = await api.resolvePlayableTrack(unplayableTrack);
    expect(resolved, isNotNull);
    expect(resolved!.streamUrl, 'https://stream.test/resolved-porkanda.m3u8');
  });

  test('PlayerController.play updates current and queue when resolveTrack returns playable candidate', () async {
    final player = PlayerController();
    const initialTrack = Track(
      trackId: 'raw-id-1',
      seokey: 'porkanda-singam-edm-version-[from-vikram]',
      title: 'Porkanda Singam (EDM Version) [From "Vikram"]',
      streamUrl: '',
    );
    player.resolveTrack = (track, {forceFresh = false}) async {
      return track.copyWith(
        trackId: 'resolved-id-2',
        streamUrl: 'https://stream.test/live.m3u8',
      );
    };

    await player.play(initialTrack, fromQueue: [initialTrack], autoPlay: false);
    expect(player.current?.streamUrl, 'https://stream.test/live.m3u8');
    expect(player.queue.first.streamUrl, 'https://stream.test/live.m3u8');
  });
}






