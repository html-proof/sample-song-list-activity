import 'dart:async';

import 'package:dio/dio.dart';
import 'package:music_hub_app/core/api/api_client.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/audio/playback_file_probe.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

enum PlaybackSourceKind { localDownload, localCache, network, refreshedNetwork }

class ResolvedPlaybackSource {
  const ResolvedPlaybackSource({
    required this.item,
    required this.uri,
    required this.kind,
  });

  final MusicItem item;
  final Uri uri;
  final PlaybackSourceKind kind;
}

class PlaybackSourceResolver {
  PlaybackSourceResolver(
    this._store, {
    this.api,
    this.providerTimeout = const Duration(seconds: 8),
  });

  final LocalStore _store;
  final ApiClient? api;
  final Duration providerTimeout;

  bool hasPotentialSource(MusicItem item) =>
      item.type == MusicItemType.song &&
      (item.playable ||
          item.seokey?.isNotEmpty == true ||
          _store.readDownload(item.id) != null);

  Future<ResolvedPlaybackSource?> resolve(
    MusicItem item,
    String quality, {
    bool refreshNetwork = false,
    Uri? failedUri,
  }) async {
    final storedDownload = _store.readDownload(item.id);
    final downloadUri = _localUri(storedDownload);
    if (downloadUri != null &&
        downloadUri != failedUri &&
        await isUsablePlaybackFile(downloadUri)) {
      return ResolvedPlaybackSource(
        item: item,
        uri: downloadUri,
        kind: PlaybackSourceKind.localDownload,
      );
    }

    final cachedUri = _localUri(item.raw);
    if (cachedUri != null &&
        cachedUri != failedUri &&
        await isUsablePlaybackFile(cachedUri)) {
      return ResolvedPlaybackSource(
        item: item,
        uri: cachedUri,
        kind: PlaybackSourceKind.localCache,
      );
    }

    var effectiveItem = item;
    var refreshed = false;
    if (refreshNetwork) {
      final fresh = await _refresh(item);
      if (fresh != null) {
        effectiveItem = fresh;
        refreshed = true;
      }
    }

    final uri = selectNetworkUri(effectiveItem, quality);
    if (uri == null || uri == failedUri) return null;
    return ResolvedPlaybackSource(
      item: effectiveItem,
      uri: uri,
      kind: refreshed
          ? PlaybackSourceKind.refreshedNetwork
          : PlaybackSourceKind.network,
    );
  }

  Future<MusicItem?> _refresh(MusicItem item) async {
    final api = this.api;
    final key = item.seokey;
    if (api == null || key == null || key.isEmpty) return null;
    final cancelToken = CancelToken();
    try {
      final response = await api
          .getMap(
            '${ApiEndpoints.songs}/${Uri.encodeComponent(key)}',
            cancelToken: cancelToken,
          )
          .timeout(
            providerTimeout,
            onTimeout: () {
              cancelToken.cancel('Playback source resolution timed out');
              throw TimeoutException('Playback source resolution timed out');
            },
          );
      final refreshed = MusicItem.fromJson(response);
      return refreshed.type == MusicItemType.song ? refreshed : null;
    } catch (_) {
      return null;
    }
  }

  static Uri? selectNetworkUri(MusicItem item, String quality) {
    final streams = item.raw['stream_urls'];
    final urls = streams is Map ? streams['urls'] : null;
    if (urls is Map) {
      final keys = switch (quality) {
        'low' => const [
          'low_quality',
          'medium_quality',
          'high_quality',
          'very_high_quality',
        ],
        'medium' => const [
          'medium_quality',
          'high_quality',
          'low_quality',
          'very_high_quality',
        ],
        _ => const [
          'very_high_quality',
          'high_quality',
          'medium_quality',
          'low_quality',
        ],
      };
      for (final key in keys) {
        final uri = _networkUri(urls[key]?.toString());
        if (uri != null) return uri;
      }
    }
    return _networkUri(item.streamUrl);
  }

  static Uri? _networkUri(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri
        : null;
  }

  static Uri? _localUri(Map<dynamic, dynamic>? value) {
    final raw = value?['local_uri']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    return uri?.scheme == 'file' ? uri : null;
  }
}
