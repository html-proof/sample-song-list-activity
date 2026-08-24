import 'dart:async';

import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/audio/playback_analytics.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:uuid/uuid.dart';

class EventTracker implements PlaybackAnalytics {
  EventTracker(this._api) : sessionId = const Uuid().v4();

  final ApiClient _api;
  final String sessionId;

  @override
  void track(
    String event,
    MusicItem item, {
    required String source,
    int? positionMs,
    Map<String, dynamic>? metadata,
  }) {
    unawaited(
      _api
          .post(
            ApiEndpoints.historyEvents,
            data: {
              'event_type': event,
              'provider': 'gaana',
              'song_id': item.id,
              'artist_id': item.raw['artist_ids']
                  ?.toString()
                  .split(',')
                  .first
                  .trim(),
              'album_id': item.raw['album_id']?.toString(),
              'language': item.raw['language']?.toString(),
              'source': source,
              'position_ms': positionMs,
              'session_id': sessionId,
              'metadata': metadata ?? const <String, dynamic>{},
            },
            headers: {'Idempotency-Key': const Uuid().v4()},
          )
          .catchError((_) => null),
    );
  }

  @override
  void recordListen(
    MusicItem item, {
    required String source,
    int playedMs = 0,
    bool completed = false,
  }) {
    unawaited(
      _api
          .post(
            ApiEndpoints.historyListens,
            data: {
              'provider': 'gaana',
              'song_id': item.id,
              'seokey': item.seokey,
              'song_name': item.title,
              'artist_id': item.raw['artist_ids']
                  ?.toString()
                  .split(',')
                  .first
                  .trim(),
              'artist_name': item.subtitle,
              'album_id': item.raw['album_id']?.toString(),
              'album_name': item.raw['album']?.toString(),
              'language': item.raw['language']?.toString(),
              'artwork_url': item.imageUrl,
              'duration_ms': item.duration?.inMilliseconds,
              'played_ms': playedMs,
              'source': source,
              'started_at': DateTime.now().toUtc().toIso8601String(),
              'completed_at': completed
                  ? DateTime.now().toUtc().toIso8601String()
                  : null,
              'session_id': sessionId,
            },
          )
          .catchError((_) => null),
    );
  }
}
