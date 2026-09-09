import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'network_policy.dart';

enum DownloadStatus { queued, downloading, paused, downloaded, failed }

class DownloadEntry {
  DownloadEntry({
    required this.track,
    required this.path,
    this.status = DownloadStatus.queued,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  Track track;
  String path;
  DownloadStatus status;
  int downloadedBytes;
  int totalBytes;
  String? error;

  bool get complete => status == DownloadStatus.downloaded;
  double? get progress => totalBytes > 0 ? downloadedBytes / totalBytes : null;

  Map<String, dynamic> toJson() => {
    'track': {
      ...track.toPersonalizationJson(),
      'stream_url': track.streamUrl,
      'duration': track.durationSeconds,
    },
    'path': path,
    'status': status.name,
    'downloaded_bytes': downloadedBytes,
    'total_bytes': totalBytes,
    'error': error,
  };

  factory DownloadEntry.fromJson(Map<String, dynamic> json) => DownloadEntry(
    track: Track.fromJson(Map<String, dynamic>.from(json['track'] as Map? ?? {})),
    path: '${json['path'] ?? ''}',
    status: DownloadStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => DownloadStatus.queued,
    ),
    downloadedBytes: (json['downloaded_bytes'] as num?)?.toInt() ?? 0,
    totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
    error: json['error'] as String?,
  );
}

/// Persistent, account-scoped download database and queue.
/// Files live in the app support directory and are never exposed as public URLs.
class DownloadManager extends ChangeNotifier {
  DownloadManager({this.connection, this.policy});

  final ConnectionMonitor? connection;
  final DataUsagePolicy? policy;
  Future<Track?> Function(Track track, {bool forceFresh})? resolveTrack;
  final Map<String, DownloadEntry> _entries = {};
  final List<String> _queue = [];
  SharedPreferences? _local;
  Directory? _directory;
  String? _uid;
  bool _running = false;
  bool _disposed = false;

  static String extensionForUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return '.aac';
    if (lower.contains('.aac')) return '.aac';
    if (lower.contains('.mp3')) return '.mp3';
    if (lower.contains('.m4a')) return '.m4a';
    if (lower.contains('.mp4')) return '.mp4';
    if (lower.contains('.ogg')) return '.ogg';
    if (lower.contains('.opus')) return '.opus';
    return '.aac';
  }

  static Uint8List extractAacFrames(Uint8List rawBytes) {
    if (rawBytes.isEmpty) return rawBytes;
    if (rawBytes[0] != 0x47) return rawBytes;

    final builder = BytesBuilder(copy: false);
    var i = 0;
    var foundAudio = false;

    while (i + 188 <= rawBytes.length) {
      if (rawBytes[i] != 0x47) {
        i++;
        continue;
      }
      final pusi = (rawBytes[i + 1] & 0x40) != 0;
      final pid = ((rawBytes[i + 1] & 0x1F) << 8) | rawBytes[i + 2];
      final afc = (rawBytes[i + 3] & 0x30) >> 4;

      var payloadStart = 4;
      if (afc == 2) {
        i += 188;
        continue;
      } else if (afc == 3) {
        final adaptationFieldLength = rawBytes[i + 4];
        payloadStart = 5 + adaptationFieldLength;
      }

      if (payloadStart < 188 && pid >= 0x100 && pid < 0x1FFF) {
        final payloadOffset = i + payloadStart;
        final payloadLength = 188 - payloadStart;

        if (pusi && payloadLength > 9 &&
            rawBytes[payloadOffset] == 0x00 &&
            rawBytes[payloadOffset + 1] == 0x00 &&
            rawBytes[payloadOffset + 2] == 0x01) {
          final streamId = rawBytes[payloadOffset + 3];
          if (streamId >= 0xC0 && streamId <= 0xDF) {
            foundAudio = true;
            final pesHeaderDataLen = rawBytes[payloadOffset + 8];
            final audioStart = payloadOffset + 9 + pesHeaderDataLen;
            if (audioStart < i + 188) {
              builder.add(rawBytes.sublist(audioStart, i + 188));
            }
          }
        } else if (foundAudio) {
          builder.add(rawBytes.sublist(payloadOffset, i + 188));
        }
      }
      i += 188;
    }

    final result = builder.takeBytes();
    return result.isNotEmpty ? result : rawBytes;
  }

  void onNetworkChanged() {
    if (connection?.state.connected == true) {
      for (final entry in _entries.values) {
        if (entry.status == DownloadStatus.paused && !_queue.contains(entry.track.seokey)) {
          entry.status = DownloadStatus.queued;
          _queue.add(entry.track.seokey);
        }
      }
      unawaited(_drain());
    }
  }

  List<DownloadEntry> get entries => List.unmodifiable(_entries.values);
  List<DownloadEntry> get downloaded => entries.where((e) => e.complete).toList();
  bool get hasDownloads => downloaded.isNotEmpty;
  int get downloadedBytes => downloaded.fold(0, (sum, e) => sum + e.downloadedBytes);

  DownloadEntry? entryFor(String id) {
    if (id.isEmpty) return null;
    if (_entries.containsKey(id)) return _entries[id];
    for (final entry in _entries.values) {
      if (entry.track.id == id ||
          entry.track.seokey == id ||
          (entry.track.trackId.isNotEmpty && entry.track.trackId == id)) {
        return entry;
      }
    }
    return null;
  }

  bool isDownloaded(String id) => _validEntry(entryFor(id));

  Future<void> initialize(String? uid) async {
    connection?.removeListener(onNetworkChanged);
    connection?.addListener(onNetworkChanged);
    _uid = uid;
    _local ??= await SharedPreferences.getInstance();
    if (!kIsWeb) {
      final root = await getApplicationSupportDirectory();
      _directory = Directory('${root.path}${Platform.pathSeparator}downloads${Platform.pathSeparator}${_safe(uid ?? 'guest')}');
      await _directory!.create(recursive: true);
    }
    await _load();
  }

  Future<void> setUser(String? uid) async {
    if (_uid == uid) return;
    _queue.clear();
    _uid = uid;
    await initialize(uid);
    notifyListeners();
  }

  Future<void> _load() async {
    _entries.clear();
    final raw = _local?.getString(_key);
    if (raw != null) {
      try {
        for (final item in (jsonDecode(raw) as List).whereType<Map>()) {
          final entry = DownloadEntry.fromJson(Map<String, dynamic>.from(item));
          if (entry.path.isNotEmpty && _validEntry(entry)) {
            entry.status = DownloadStatus.downloaded;
          } else if (entry.status == DownloadStatus.downloading) {
            entry.status = DownloadStatus.queued;
          }
          final key = entry.track.seokey.isNotEmpty ? entry.track.seokey : entry.track.id;
          if (key.isNotEmpty) {
            _entries[key] = entry;
          }
        }
      } catch (_) {
        _entries.clear();
      }
    }
    notifyListeners();
  }

  String get _key => 'offline_downloads_${_uid ?? 'guest'}';

  Future<void> _save() async {
    await _local?.setString(_key, jsonEncode(_entries.values.map((e) => e.toJson()).toList()));
  }

  bool _validEntry(DownloadEntry? entry) {
    if (entry == null || !entry.complete || kIsWeb) return false;
    if (entry.path.isNotEmpty) {
      final file = File(entry.path);
      if (file.existsSync() && file.lengthSync() > 0) return true;
    }
    if (_directory != null) {
      final id = entry.track.seokey.isNotEmpty ? entry.track.seokey : entry.track.id;
      final safeKey = _safe(id);
      for (final ext in ['.aac', '.mp4', '.m4a', '.mp3', '.audio', '.ts']) {
        final f = File('${_directory!.path}${Platform.pathSeparator}$safeKey$ext');
        if (f.existsSync() && f.lengthSync() > 0) {
          entry.path = f.path;
          return true;
        }
      }
    }
    return false;
  }

  String? localPath(String id) {
    if (kIsWeb || id.isEmpty) return null;
    final entry = entryFor(id);
    if (entry != null && _validEntry(entry)) return entry.path;
    if (_directory != null) {
      final safeKey = _safe(id);
      for (final ext in ['.aac', '.mp4', '.m4a', '.mp3', '.audio', '.ts']) {
        final f = File('${_directory!.path}${Platform.pathSeparator}$safeKey$ext');
        if (f.existsSync() && f.lengthSync() > 0) return f.path;
      }
    }
    return null;
  }

  String? localPathForTrack(Track track) {
    if (kIsWeb) return null;
    return localPath(track.id) ??
        localPath(track.seokey) ??
        (track.trackId.isNotEmpty ? localPath(track.trackId) : null);
  }

  Future<void> enqueue(
    Track track, {
    Future<Track?> Function(Track track, {bool forceFresh})? resolveTrack,
  }) async {
    final key = track.seokey.isNotEmpty ? track.seokey : track.id;
    if (kIsWeb || key.isEmpty || isDownloaded(key)) return;
    if (_directory == null) await initialize(_uid);
    final ext = track.streamUrl.isNotEmpty ? extensionForUrl(track.streamUrl) : '.mp4';
    final path = '${_directory!.path}${Platform.pathSeparator}${_safe(key)}$ext';
    final existing = entryFor(key);
    _entries[key] = existing ?? DownloadEntry(track: track, path: path);
    if (!_queue.contains(key)) _queue.add(key);
    await _save();
    notifyListeners();
    unawaited(_drain(customResolve: resolveTrack));
  }

  Future<void> enqueueAll(Iterable<Track> tracks) async {
    for (final track in tracks) {
      await enqueue(track);
    }
  }

  Future<void> retry(String id) async {
    final entry = entryFor(id);
    if (entry == null) return;
    final key = entry.track.seokey.isNotEmpty ? entry.track.seokey : entry.track.id;
    entry.status = DownloadStatus.queued;
    entry.error = null;
    if (!_queue.contains(key)) _queue.add(key);
    await _save();
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> resumeAll() async {
    for (final entry in _entries.values) {
      if (entry.status == DownloadStatus.paused || entry.status == DownloadStatus.failed) {
        entry.status = DownloadStatus.queued;
        entry.error = null;
        final key = entry.track.seokey.isNotEmpty ? entry.track.seokey : entry.track.id;
        if (!_queue.contains(key)) _queue.add(key);
      }
    }
    await _save();
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> pause(String id) async {
    final entry = entryFor(id);
    if (entry == null || entry.complete) return;
    entry.status = DownloadStatus.paused;
    final key = entry.track.seokey.isNotEmpty ? entry.track.seokey : entry.track.id;
    _queue.remove(key);
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    if (id.isEmpty) return;
    final entry = entryFor(id);
    if (entry != null) {
      _entries.remove(entry.track.seokey);
      if (entry.track.id.isNotEmpty) _entries.remove(entry.track.id);
      _queue.remove(entry.track.seokey);
      if (entry.track.id.isNotEmpty) _queue.remove(entry.track.id);
      if (!kIsWeb) {
        final file = File(entry.path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> removeAll() async {
    final list = _entries.values.toList();
    _entries.clear();
    _queue.clear();
    for (final entry in list) {
      if (!kIsWeb) {
        final file = File(entry.path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> _drain({
    Future<Track?> Function(Track track, {bool forceFresh})? customResolve,
  }) async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final id = _queue.removeAt(0);
        final entry = entryFor(id);
        if (entry == null || entry.status == DownloadStatus.paused || isDownloaded(id)) continue;
        final state = connection?.state;
        if (state != null && policy != null && !policy!.canUseNetwork(state, forDownload: true)) {
          entry.status = DownloadStatus.paused;
          entry.error = state.connected ? 'Waiting for Wi-Fi' : 'Network unavailable';
          await _save();
          notifyListeners();
          continue;
        }
        await _download(entry, customResolve: customResolve);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _download(
    DownloadEntry entry, {
    Future<Track?> Function(Track track, {bool forceFresh})? customResolve,
  }) async {
    entry.status = DownloadStatus.downloading;
    entry.error = null;
    await _save();
    notifyListeners();

    var track = entry.track;
    final resolver = customResolve ?? resolveTrack;
    if (track.streamUrl.isEmpty && track.streamUrls.isEmpty && resolver != null) {
      try {
        final resolved = await resolver(track);
        if (resolved != null && resolved.streamUrl.isNotEmpty) {
          track = resolved;
          entry.track = track;
        }
      } catch (_) {}
    }

    final downloadQuality = policy?.downloadQuality ?? 'high';
    var targetStreamUrl = track.getStreamUrlForQuality(downloadQuality);
    if (downloadQuality == 'high' || downloadQuality == 'normal' || downloadQuality == 'medium') {
      if (targetStreamUrl.contains('320.mp4')) {
        targetStreamUrl = targetStreamUrl.replaceAll('320.mp4', '128.mp4');
      }
    } else if (downloadQuality == 'low') {
      if (targetStreamUrl.contains('320.mp4') || targetStreamUrl.contains('128.mp4')) {
        targetStreamUrl = targetStreamUrl.replaceAll(RegExp(r'\b(?:128|320)\.mp4'), '64.mp4');
      }
    }
    final urlToDownload = targetStreamUrl.isNotEmpty ? targetStreamUrl : track.streamUrl;
    if (urlToDownload.isEmpty) {
      entry.status = DownloadStatus.failed;
      entry.error = 'Unable to resolve audio stream';
      await _save();
      notifyListeners();
      return;
    }

    if (_directory != null) {
      final isHls = urlToDownload.contains('.m3u8');
      final ext = isHls ? '.aac' : extensionForUrl(urlToDownload);
      final key = track.seokey.isNotEmpty ? track.seokey : track.id;
      entry.path = '${_directory!.path}${Platform.pathSeparator}${_safe(key)}$ext';
    }

    final client = http.Client();
    try {
      final initialUri = Uri.parse(urlToDownload);
      final initialResp = await client.get(initialUri);
      if (initialResp.statusCode < 200 || initialResp.statusCode >= 300) {
        throw HttpException('Download failed (${initialResp.statusCode})');
      }

      final bodyText = initialResp.body;
      if (bodyText.contains('#EXTM3U')) {
        // HLS Stream - download segments into single playable audio file
        var mediaPlaylistUri = initialUri;
        var mediaBody = bodyText;

        if (bodyText.contains('#EXT-X-STREAM-INF')) {
          final lines = bodyText.split('\n');
          final variants = <({int bandwidth, String uri})>[];
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.startsWith('#EXT-X-STREAM-INF') && i + 1 < lines.length) {
              final nextLine = lines[i + 1].trim();
              if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
                final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
                final bw = bwMatch != null ? int.tryParse(bwMatch.group(1)!) ?? 128000 : 128000;
                variants.add((bandwidth: bw, uri: nextLine));
              }
            }
          }
          String? variantUriStr;
          if (variants.isNotEmpty) {
            final targetBps = switch (downloadQuality) {
              'very_high' => 320000,
              'high' => 128000,
              'normal' || 'medium' => 128000,
              'low' => 64000,
              _ => 128000,
            };
            variants.sort((a, b) => (a.bandwidth - targetBps).abs().compareTo((b.bandwidth - targetBps).abs()));
            variantUriStr = variants.first.uri;
          }
          if (variantUriStr != null) {
            mediaPlaylistUri = initialUri.resolve(variantUriStr);
            if (mediaPlaylistUri.query.isEmpty && initialUri.query.isNotEmpty) {
              mediaPlaylistUri = mediaPlaylistUri.replace(query: initialUri.query);
            }
            final mediaResp = await client.get(mediaPlaylistUri);
            if (mediaResp.statusCode == 200) {
              mediaBody = mediaResp.body;
            }
          }
        }

        final segmentUris = <Uri>[];
        for (final rawLine in mediaBody.split('\n')) {
          final line = rawLine.trim();
          if (line.isNotEmpty && !line.startsWith('#')) {
            var segUri = mediaPlaylistUri.resolve(line);
            if (segUri.query.isEmpty && initialUri.query.isNotEmpty) {
              segUri = segUri.replace(query: initialUri.query);
            }
            segmentUris.add(segUri);
          }
        }

        if (segmentUris.isEmpty) {
          throw const FormatException('No media segments found in HLS playlist');
        }

        final file = File(entry.path);
        final sink = file.openWrite();
        var bytes = 0;
        entry.totalBytes = segmentUris.length * 160000;

        for (var i = 0; i < segmentUris.length; i++) {
          if (_disposed) break;
          final segUri = segmentUris[i];
          final segResp = await client.get(segUri);
          if (segResp.statusCode != 200 || segResp.bodyBytes.isEmpty) {
            throw HttpException('Failed downloading segment $i (${segResp.statusCode})');
          }
          final aacBytes = extractAacFrames(segResp.bodyBytes);
          sink.add(aacBytes);
          bytes += aacBytes.length;
          entry.downloadedBytes = bytes;
          entry.totalBytes = (bytes / (i + 1) * segmentUris.length).toInt();
          notifyListeners();
        }
        await sink.close();

        if (bytes <= 0) throw const FormatException('Empty audio file');
        entry.downloadedBytes = bytes;
        entry.totalBytes = bytes;
        entry.status = DownloadStatus.downloaded;
        await _save();
        notifyListeners();
      } else {
        // Direct audio stream (mp3, m4a, aac)
        final file = File(entry.path);
        final sink = file.openWrite();
        sink.add(initialResp.bodyBytes);
        final total = initialResp.bodyBytes.length;
        await sink.close();
        if (total <= 0) throw const FormatException('Empty audio file');
        entry.downloadedBytes = total;
        entry.totalBytes = total;
        entry.status = DownloadStatus.downloaded;
        await _save();
        notifyListeners();
      }
    } catch (error) {
      final offline = connection?.state.connected == false;
      entry.status = offline ? DownloadStatus.paused : DownloadStatus.failed;
      entry.error = offline ? 'Network unavailable' : '$error';
      await _save();
      notifyListeners();
    } finally {
      client.close();
    }
  }

  String _safe(String value) => value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    connection?.removeListener(onNetworkChanged);
    super.dispose();
  }
}
