import 'package:music_hub_app/core/downloads/download_writer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/core/storage/local_store.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  return DownloadRepository(ref.watch(localStoreProvider));
});

class DownloadRepository {
  DownloadRepository(this._store);

  final LocalStore _store;
  final DownloadWriter _writer = DownloadWriter();

  List<MusicItem> items() =>
      _store.downloads().map(MusicItem.fromJson).toList();

  Future<void> download(MusicItem item, void Function(double) progress) async {
    if (_store.readSetting('downloads_wifi_only', true)) {
      final connections = await Connectivity().checkConnectivity();
      if (!connections.contains(ConnectivityResult.wifi)) {
        throw StateError('Connect to Wi-Fi or disable Wi-Fi-only downloads');
      }
    }
    final url = _downloadUrl(item);
    if (url == null || url.contains('.m3u8')) {
      throw UnsupportedError(
        'This provider supplies an HLS stream. Offline packaging requires provider support.',
      );
    }
    final path = await _writer.save(item.id, url, progress);
    await _store.saveDownload({
      ...item.raw,
      'id': item.id,
      'local_path': path,
      'local_uri': Uri.file(path).toString(),
    });
  }

  Future<void> remove(MusicItem item) async {
    final path = item.raw['local_path']?.toString();
    if (path != null) await _writer.remove(path);
    await _store.removeDownload(item.id);
  }

  String? _downloadUrl(MusicItem item) {
    final streams = item.raw['stream_urls'];
    if (streams is! Map || streams['urls'] is! Map) return item.streamUrl;
    final urls = streams['urls'] as Map;
    final quality = _store.readSetting('downloads_quality', 'high');
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
      final value = urls[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return item.streamUrl;
  }
}
