export 'search/scoring_engine.dart';
export 'search/deduplicator.dart';
export 'recommendations/recommendation_engine.dart';
export 'models/playback_session.dart';

enum PlaybackRepeatMode { off, all, one }

class Track {
  const Track({
    required this.seokey,
    required this.title,
    this.trackId = '',
    this.artist = '',
    this.artistIds = '',
    this.album = '',
    this.albumId = '',
    this.albumSeokey = '',
    this.genres = '',
    this.language = '',
    this.durationSeconds = 0,
    this.imageUrl = '',
    this.streamUrl = '',
    this.streamUrls = const {},
    this.isExplicit = false,
    this.reasons = const [],
    this.popularityScore = 0.0,
  });
  final String seokey,
      trackId,
      title,
      artist,
      artistIds,
      album,
      albumId,
      albumSeokey,
      genres,
      language,
      imageUrl,
      streamUrl;
  final Map<String, String> streamUrls;
  final int durationSeconds;
  final bool isExplicit;
  final List<String> reasons;
  final double popularityScore;

  factory Track.fromJson(Map<String, dynamic> json) {
    final artistValue = json['artist'];
    final artistsValue = json['artists'];
    String artistNames = '';
    String artistIds = '';
    if (artistsValue is List) {
      artistNames = artistsValue
          .whereType<Map>()
          .map((item) => '${item['name'] ?? item['title'] ?? ''}')
          .where((v) => v.isNotEmpty)
          .join(', ');
      artistIds = artistsValue
          .whereType<Map>()
          .map((item) => '${item['id'] ?? ''}')
          .where((v) => v.isNotEmpty)
          .join(', ');
    } else if (artistsValue is String && artistsValue.isNotEmpty) {
      artistNames = artistsValue;
      artistIds = '${json['artist_ids'] ?? json['artistIds'] ?? ''}';
    } else if (artistValue is Map) {
      artistNames = '${artistValue['name'] ?? artistValue['title'] ?? ''}';
      artistIds = '${artistValue['id'] ?? ''}';
    } else if (artistValue is String) {
      artistNames = artistValue;
    }

    final albumValue = json['album'];
    String albumTitle = '';
    String albumId = '';
    String albumSeokey = '';
    if (albumValue is Map) {
      albumTitle = '${albumValue['title'] ?? albumValue['name'] ?? ''}';
      albumId = '${albumValue['provider_id'] ?? albumValue['providerId'] ?? ''}';
      albumSeokey = '${albumValue['id'] ?? albumValue['seokey'] ?? ''}';
    } else if (albumValue is String) {
      albumTitle = albumValue;
      albumId = '${json['album_id'] ?? json['albumId'] ?? ''}';
      albumSeokey = '${json['album_seokey'] ?? json['albumSeokey'] ?? ''}';
    }

    final durationRaw = json['duration_ms'] ??
        json['durationMs'] ??
        json['duration'] ??
        json['duration_seconds'] ??
        json['durationSeconds'];
    int durationSec = 0;
    if (durationRaw is num) {
      durationSec = durationRaw > 1000 ? durationRaw.toInt() ~/ 1000 : durationRaw.toInt();
    } else if (durationRaw is String) {
      final parsed = int.tryParse(durationRaw) ?? 0;
      durationSec = parsed > 1000 ? parsed ~/ 1000 : parsed;
    }

    final rawUrls = _map(_map(json['stream_urls'])['urls']);
    final Map<String, String> parsedStreamUrls = {};
    rawUrls.forEach((k, v) {
      if (v != null && '$v'.trim().isNotEmpty) {
        parsedStreamUrls[k.toString().toLowerCase()] = '$v'.trim();
      }
    });
    final flatUrls = _map(json['stream_urls']);
    flatUrls.forEach((k, v) {
      if (k != 'urls' && v != null && '$v'.trim().isNotEmpty && v is String) {
        parsedStreamUrls[k.toString().toLowerCase()] = v.trim();
      }
    });
    if (json['stream_url'] is String && (json['stream_url'] as String).isNotEmpty) {
      parsedStreamUrls.putIfAbsent('default', () => (json['stream_url'] as String).trim());
    }
    if (json['streamUrl'] is String && (json['streamUrl'] as String).isNotEmpty) {
      parsedStreamUrls.putIfAbsent('default', () => (json['streamUrl'] as String).trim());
    }

    final streamUrl = _first([
      json['stream_url'],
      json['streamUrl'],
      parsedStreamUrls['high_quality'],
      parsedStreamUrls['medium_quality'],
      parsedStreamUrls['low_quality'],
      parsedStreamUrls['very_high_quality'],
    ]);

    // If stream_urls map was omitted by catalog but streamUrl has Gaana bitrate template,
    // synthesize the available quality tiers so getStreamUrlForQuality can switch accurately.
    if (!parsedStreamUrls.containsKey('high_quality') && streamUrl.isNotEmpty) {
      if (streamUrl.contains(RegExp(r'\b(?:16|64|128|320)\.mp4'))) {
        parsedStreamUrls['very_high_quality'] =
            streamUrl.replaceAll(RegExp(r'\b(?:16|64|128|320)\.mp4'), '320.mp4');
        parsedStreamUrls['high_quality'] =
            streamUrl.replaceAll(RegExp(r'\b(?:16|64|128|320)\.mp4'), '128.mp4');
        parsedStreamUrls['medium_quality'] =
            streamUrl.replaceAll(RegExp(r'\b(?:16|64|128|320)\.mp4'), '64.mp4');
        parsedStreamUrls['low_quality'] =
            streamUrl.replaceAll(RegExp(r'\b(?:16|64|128|320)\.mp4'), '16.mp4');
      }
    }

    final recommendation = _map(json['recommendation']);
    final reasons = (recommendation['reasons'] as List? ?? const [])
        .map((item) => '$item')
        .toList();

    return Track(
      seokey: '${json['seokey'] ?? json['id'] ?? ''}',
      trackId: '${json['track_id'] ?? json['provider_id'] ?? json['providerId'] ?? json['trackId'] ?? json['id'] ?? ''}',
      title: '${json['title'] ?? json['name'] ?? ''}',
      artist: artistNames,
      artistIds: artistIds,
      album: albumTitle,
      albumId: albumId,
      albumSeokey: albumSeokey,
      genres: _joined(json['genres']),
      language: '${json['language'] ?? ''}',
      durationSeconds: durationSec,
      imageUrl: _imageUrl(json, albumValue: albumValue),
      streamUrl: streamUrl,
      streamUrls: parsedStreamUrls,
      isExplicit: json['explicit'] == true || json['is_explicit'] == true || json['isExplicit'] == true,
      reasons: reasons,
      popularityScore: (json['popularity_score'] ?? json['popularityScore'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'seokey': seokey,
    'track_id': trackId,
    'title': title,
    'artist': artist,
    'artist_ids': artistIds,
    'album': album,
    'album_id': albumId,
    'album_seokey': albumSeokey,
    'genres': genres,
    'language': language,
    'duration_seconds': durationSeconds,
    'imageUrl': imageUrl,
    'image_url': imageUrl,
    'stream_url': streamUrl,
    'stream_urls': streamUrls,
    'explicit': isExplicit,
    'recommendation': {'reasons': reasons},
  };

  /// Estimated bitrate in kbps for the given quality profile.
  int getBitrateForQuality(String quality) {
    final q = quality.toLowerCase().trim();
    switch (q) {
      case 'very_high':
      case '320':
        return 320;
      case 'high':
      case '160':
        return 128; // Gaana high quality tier is 128 kbps (~4 MB per 4-min song)
      case 'normal':
      case 'medium':
      case '128':
        return 128;
      case 'low':
      case '64':
      case '96':
        return 64;
      case 'automatic':
      default:
        return 128;
    }
  }

  /// Estimated file size in megabytes:
  /// file_size_MB = bitrate_kbps * duration_seconds / 8 / 1000
  double getEstimatedSizeMb(String quality) {
    final kbps = getBitrateForQuality(quality);
    final secs = durationSeconds > 0 ? durationSeconds : 240;
    return (kbps * secs) / 8 / 1000;
  }

  /// Select the best stream URL matching the user's quality preference.
  String getStreamUrlForQuality(String quality) {
    if (streamUrls.isEmpty) {
      final q = quality.toLowerCase().trim();
      if (q == 'high' || q == '160' || q == 'normal' || q == 'medium' || q == '128' || q == 'automatic') {
        if (streamUrl.contains('320.mp4')) {
          return streamUrl.replaceAll('320.mp4', '128.mp4');
        }
      } else if (q == 'low' || q == '64') {
        if (streamUrl.contains('320.mp4') || streamUrl.contains('128.mp4')) {
          return streamUrl.replaceAll(RegExp(r'\b(?:128|320)\.mp4'), '64.mp4');
        }
      }
      return streamUrl;
    }
    final q = quality.toLowerCase().trim();

    List<String> preferenceKeys;
    switch (q) {
      case 'very_high':
      case '320':
        preferenceKeys = [
          'very_high_quality',
          'very_high',
          '320',
          'high_quality',
          'high',
          '160',
          'medium_quality',
          'medium',
          'normal',
          '128',
          'low_quality',
          'low',
          '64',
          '96',
          'default',
        ];
        break;
      case 'high':
      case '160':
        preferenceKeys = [
          'high_quality',
          'high',
          '160',
          'medium_quality',
          'medium',
          'normal',
          '128',
          'very_high_quality',
          'very_high',
          '320',
          'low_quality',
          'low',
          '64',
          '96',
          'default',
        ];
        break;
      case 'normal':
      case 'medium':
      case '128':
        preferenceKeys = [
          'medium_quality',
          'medium',
          'normal',
          '128',
          'low_quality',
          'low',
          '96',
          '64',
          'high_quality',
          'high',
          '160',
          'very_high_quality',
          'very_high',
          '320',
          'default',
        ];
        break;
      case 'low':
      case '64':
      case '96':
        preferenceKeys = [
          'low_quality',
          'low',
          '64',
          '96',
          'medium_quality',
          'medium',
          'normal',
          '128',
          'high_quality',
          'high',
          '160',
          'very_high_quality',
          'very_high',
          '320',
          'default',
        ];
        break;
      case 'automatic':
      default:
        preferenceKeys = [
          'high_quality',
          'high',
          'medium_quality',
          'medium',
          'normal',
          '128',
          'low_quality',
          'low',
          'very_high_quality',
          'very_high',
          'default',
        ];
        break;
    }

    for (final key in preferenceKeys) {
      final candidate = streamUrls[key];
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
    return streamUrl;
  }

  Track copyWith({
    String? seokey,
    String? trackId,
    String? title,
    String? artist,
    String? artistIds,
    String? album,
    String? albumId,
    String? albumSeokey,
    String? genres,
    String? language,
    int? durationSeconds,
    String? imageUrl,
    String? streamUrl,
    Map<String, String>? streamUrls,
    bool? isExplicit,
    List<String>? reasons,
    double? popularityScore,
  }) => Track(
    seokey: seokey ?? this.seokey,
    trackId: trackId ?? this.trackId,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    artistIds: artistIds ?? this.artistIds,
    album: album ?? this.album,
    albumId: albumId ?? this.albumId,
    albumSeokey: albumSeokey ?? this.albumSeokey,
    genres: genres ?? this.genres,
    language: language ?? this.language,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    imageUrl: imageUrl ?? this.imageUrl,
    streamUrl: streamUrl ?? this.streamUrl,
    streamUrls: streamUrls ?? this.streamUrls,
    isExplicit: isExplicit ?? this.isExplicit,
    reasons: reasons ?? this.reasons,
    popularityScore: popularityScore ?? this.popularityScore,
  );

  String get id => seokey.isNotEmpty ? seokey : trackId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toPersonalizationJson() {
    final effectiveSeokey = seokey.isNotEmpty ? seokey : trackId;
    return {
      'seokey': effectiveSeokey.isNotEmpty ? effectiveSeokey : 'unknown-track',
      'track_id': trackId,
      'title': title,
      'artist': artist,
      'artists': artist,
      'artist_ids': artistIds,
      'genres': genres,
      'language': language,
      'album': album,
      'album_id': albumId,
      'album_seokey': albumSeokey,
      'image_url': imageUrl,
      'imageUrl': imageUrl,
      'images': {
        'urls': {'large_artwork': imageUrl},
      },
    };
  }
  static List<Track> list(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Track.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } else if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map['items'] is List) {
        return list(map['items']);
      } else if (map['tracks'] is List) {
        return list(map['tracks']);
      } else if (map['songs'] is List) {
        return list(map['songs']);
      } else if (map['data'] != null) {
        return list(map['data']);
      }
      return [Track.fromJson(map)];
    }
    return [];
  }
}

class LyricLine {
  const LyricLine({required this.startMs, this.endMs, required this.text});
  final int startMs;
  final int? endMs;
  final String text;

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    startMs: (json['startMs'] as num?)?.toInt() ?? 0,
    endMs: (json['endMs'] as num?)?.toInt(),
    text: '${json['text'] ?? ''}',
  );
}

class Lyrics {
  const Lyrics({
    required this.trackId,
    required this.status,
    required this.synced,
    required this.instrumental,
    this.provider,
    this.plainLyrics,
    this.lines = const [],
  });

  const Lyrics.empty({
    this.trackId = '',
    this.status = 'not_found',
    this.synced = false,
    this.instrumental = false,
    this.provider,
    this.plainLyrics,
    this.lines = const [],
  });
  final String trackId;
  final String status;
  final bool synced;
  final bool instrumental;
  final String? provider;
  final String? plainLyrics;
  final List<LyricLine> lines;

  factory Lyrics.fromJson(Map<String, dynamic> json) => Lyrics(
    trackId: '${json['trackId'] ?? ''}',
    status: '${json['status'] ?? 'not_found'}',
    synced: json['synced'] == true,
    instrumental: json['instrumental'] == true,
    provider: json['provider'] as String?,
    plainLyrics: json['plainLyrics'] as String?,
    lines: (json['lines'] as List? ?? const [])
        .whereType<Map>()
        .map((line) => LyricLine.fromJson(Map<String, dynamic>.from(line)))
        .toList(),
  );
}

class Album {
  const Album({
    String? id,
    String? seokey,
    required this.title,
    this.artist = '',
    this.artistIds = const [],
    this.imageUrl = '',
    this.trackCount = 0,
    this.language = '',
    this.releaseDate = '',
    this.label = '',
    this.tracks = const [],
  }) : seokey = seokey ?? id ?? '';
  final String seokey, title, artist, imageUrl, language, releaseDate, label;
  final List<String> artistIds;
  final int trackCount;
  final List<Track> tracks;
  String get id => seokey;

  Album copyWith({
    String? id,
    String? seokey,
    String? title,
    String? artist,
    List<String>? artistIds,
    String? imageUrl,
    int? trackCount,
    String? language,
    String? releaseDate,
    String? label,
    List<Track>? tracks,
  }) =>
      Album(
        id: id ?? this.id,
        seokey: seokey ?? this.seokey,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artistIds: artistIds ?? this.artistIds,
        imageUrl: imageUrl ?? this.imageUrl,
        trackCount: trackCount ?? this.trackCount,
        language: language ?? this.language,
        releaseDate: releaseDate ?? this.releaseDate,
        label: label ?? this.label,
        tracks: tracks ?? this.tracks,
      );
  factory Album.fromJson(Map<String, dynamic> json) {
    if (json['type'] == 'album' || json.containsKey('image_url') || json.containsKey('id') || json.containsKey('imageUrl')) {
      final artists = json['artists'] is List
          ? (json['artists'] as List)
                .whereType<Map>()
                .map((item) => '${item['name'] ?? ''}')
                .where((value) => value.isNotEmpty)
                .join(', ')
          : json['artist'] is String
          ? json['artist'] as String
          : json['artists'] is String
          ? json['artists'] as String
          : '';
      final artistIds = json['artistIds'] is List
          ? (json['artistIds'] as List)
                .map((value) => '$value')
                .where((value) => value.isNotEmpty)
                .toList()
          : json['artists'] is List
          ? (json['artists'] as List)
                .whereType<Map>()
                .map((item) => '${item['id'] ?? ''}')
                .where((value) => value.isNotEmpty)
                .toList()
          : <String>[];
      return Album(
        seokey: '${json['id'] ?? json['seokey'] ?? ''}',
        title: '${json['title'] ?? json['name'] ?? ''}',
        artist: artists,
        artistIds: artistIds,
        imageUrl: _imageUrl(json),
        trackCount:
            (json['trackCount'] as num?)?.toInt() ??
            (json['song_count'] as num?)?.toInt() ??
            0,
        language: '${json['language'] ?? ''}',
        releaseDate: '${json['releaseYear'] ?? json['release_date'] ?? ''}',
        label: '${json['label'] ?? ''}',
        tracks: Track.list(json['songs'] ?? json['tracks']),
      );
    }
    final urls = _map(_map(json['images'])['urls']);
    return Album(
      seokey: '${json['id'] ?? json['seokey'] ?? ''}',
      title: '${json['title'] ?? json['name'] ?? ''}',
      artist: json['artist'] is String ? json['artist'] as String : _joined(json['artists']),
      artistIds: _joined(json['artist_seokeys'] ?? json['artistIds'])
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      imageUrl: _imageUrl(json, imageUrls: urls),
      trackCount: int.tryParse('${json['track_count'] ?? json['trackCount'] ?? 0}') ?? 0,
      language: '${json['language'] ?? ''}',
      releaseDate: '${json['release_date'] ?? json['releaseYear'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'seokey': seokey,
    'title': title,
    'artist': artist,
    'artist_ids': artistIds,
    'imageUrl': imageUrl,
    'image_url': imageUrl,
    'trackCount': trackCount,
    'language': language,
    'release_date': releaseDate,
    'label': label,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  static List<Album> list(dynamic raw) {
    final rawList = raw is List
        ? raw
        : raw is Map && raw['albums'] is List
            ? raw['albums'] as List
            : raw is Map && raw['data'] is List
                ? raw['data'] as List
                : const [];

    final seenIds = <String>{};
    final seenTitles = <String>{};
    final results = <Album>[];

    for (final item in rawList) {
      if (item is! Map) continue;
      final album = Album.fromJson(Map<String, dynamic>.from(item));
      if (album.id.isEmpty) continue;

      final cleanTitle = album.title
          .toLowerCase()
          .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '')
          .replaceAll(
            RegExp(
              r'\b(?:original motion picture soundtrack|soundtrack|ost|vol(?:ume)?\.?\s*\d+|ep|single)\b',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(RegExp(r'[^a-z0-9]+'), '')
          .trim();
      final artistKey = album.artist
          .toLowerCase()
          .split(',')
          .first
          .replaceAll(RegExp(r'[^a-z0-9]+'), '')
          .trim();
      final titleArtistKey = '$cleanTitle-$artistKey';

      if (seenIds.contains(album.id.toLowerCase())) continue;
      if (cleanTitle.isNotEmpty && seenTitles.contains(titleArtistKey)) continue;

      seenIds.add(album.id.toLowerCase());
      if (cleanTitle.isNotEmpty) seenTitles.add(titleArtistKey);
      results.add(album);
    }
    return results;
  }
}

class AlbumRecommendation {
  const AlbumRecommendation({
    required this.id,
    required this.title,
    this.artistId = '',
    this.artistName = '',
    this.imageUrl = '',
    this.releaseYear,
    this.language = '',
    this.genre = '',
    this.songCount = 0,
    this.reason = 'same_artist',
  });

  final String id;
  final String title;
  final String artistId;
  final String artistName;
  final String imageUrl;
  final int? releaseYear;
  final String language;
  final String genre;
  final int songCount;
  final String reason;

  factory AlbumRecommendation.fromJson(Map<String, dynamic> json) =>
      AlbumRecommendation(
        id: '${json['id'] ?? json['seokey'] ?? ''}',
        title: '${json['title'] ?? json['name'] ?? ''}',
        artistId: '${json['artistId'] ?? ''}',
        artistName: '${json['artistName'] ?? json['artist'] ?? ''}',
        imageUrl: '${json['imageUrl'] ?? json['image_url'] ?? ''}',
        releaseYear: (json['releaseYear'] as num?)?.toInt(),
        language: '${json['language'] ?? ''}',
        genre: '${json['genre'] ?? ''}',
        songCount: (json['songCount'] as num?)?.toInt() ??
            (json['song_count'] as num?)?.toInt() ??
            0,
        reason: '${json['reason'] ?? 'same_artist'}',
      );

  Album toAlbum() => Album(
        seokey: id,
        title: title,
        artist: artistName,
        artistIds: artistId.isNotEmpty ? [artistId] : const [],
        imageUrl: imageUrl,
        trackCount: songCount,
        language: language,
        releaseDate: releaseYear != null ? '$releaseYear' : '',
        label: genre,
      );
}

class Artist {
  const Artist({
    required this.seokey,
    required this.name,
    this.artistId = '',
    this.imageUrl = '',
  });
  final String seokey, artistId, name, imageUrl;
  String get id => seokey.isNotEmpty ? seokey : artistId;
  factory Artist.fromJson(Map<String, dynamic> json) {
    if (json['type'] == 'artist' || json.containsKey('image_url')) {
      return Artist(
        seokey: '${json['id'] ?? json['seokey'] ?? ''}',
        artistId: '${json['provider_id'] ?? json['artist_id'] ?? ''}',
        name: '${json['name'] ?? json['title'] ?? ''}',
        imageUrl: _imageUrl(json, includeArtistImage: true),
      );
    }
    final urls = _map(_map(json['images'])['urls']);
    return Artist(
      seokey: '${json['seokey'] ?? ''}',
      artistId: '${json['artist_id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      imageUrl: _first([
        urls['large_artwork'],
        urls['medium_artwork'],
        urls['small_artwork'],
      ]),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'seokey': seokey,
    'artist_id': artistId,
    'name': name,
    'imageUrl': imageUrl,
    'image_url': imageUrl,
  };

  static List<Artist> list(dynamic raw) {
    final rawList = raw is List
        ? raw
        : raw is Map && raw['artists'] is List
            ? raw['artists'] as List
            : raw is Map && raw['data'] is List
                ? raw['data'] as List
                : null;
    if (rawList == null) return const [];
    return rawList
        .whereType<Map>()
        .map((e) => Artist.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class CollectionItem {
  const CollectionItem({
    required this.seokey,
    required this.title,
    this.id = '',
    this.imageUrl = '',
    this.language = '',
  });
  final String seokey, id, title, imageUrl, language;
  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    final urls = _map(_map(json['images'])['urls']);
    return CollectionItem(
      seokey: '${json['seokey'] ?? ''}',
      id: '${json['playlist_id'] ?? ''}',
      title: '${json['title'] ?? 'Collection'}',
      imageUrl: _first([
        urls['large_artwork'],
        urls['medium_artwork'],
        urls['small_artwork'],
      ]),
      language: '${json['language'] ?? ''}',
    );
  }
}

String upgradeImageUrlQuality(String url) {
  var clean = url.trim();
  if (clean.isEmpty) return '';
  if (clean.startsWith('http://')) {
    clean = 'https://${clean.substring(7)}';
  }

  // Gaana artwork size upgrades (size_s, size_m, size_xs, size_m_1748450138 -> size_l / size_l_1748450138)
  clean = clean.replaceAll(
    RegExp(r'size_[smx]+(?=[_0-9\.\-])', caseSensitive: false),
    'size_l',
  );
  clean = clean.replaceAll(
    RegExp(r'img_[smx]+(?=[_0-9\.\-])', caseSensitive: false),
    'img_l',
  );

  // JioSaavn / Saavn and standard CDNs: 50x50, 150x150, 250x250, 320x320 -> 500x500 HD
  clean = clean.replaceAllMapped(
    RegExp(r'[-_](?:50x50|80x80|150x150|250x250|320x320)([-_/\.\?])', caseSensitive: false),
    (match) => '-500x500${match.group(1)}',
  );
  clean = clean.replaceAllMapped(
    RegExp(r'[-_](?:50x50|80x80|150x150|250x250|320x320)$', caseSensitive: false),
    (match) => '-500x500',
  );
  clean = clean.replaceAllMapped(
    RegExp(r'/(?:50x50|80x80|150x150|250x250|320x320)/', caseSensitive: false),
    (_) => '/500x500/',
  );

  // YouTube thumbnail upgrades
  clean = clean.replaceAllMapped(
    RegExp(r'/(?:default|mqdefault|sddefault)\.jpg', caseSensitive: false),
    (_) => '/hqdefault.jpg',
  );

  // Google / Firebase avatars
  clean = clean.replaceAllMapped(
    RegExp(r'=s(?:96|120|150|200|300)-c', caseSensitive: false),
    (_) => '=s500-c',
  );

  // Dimension query parameters
  clean = clean.replaceAllMapped(
    RegExp(r'([?&]w=)(?:50|80|100|150|200|250|300)', caseSensitive: false),
    (match) => '${match.group(1)}500',
  );
  clean = clean.replaceAllMapped(
    RegExp(r'([?&]width=)(?:50|80|100|150|200|250|300)', caseSensitive: false),
    (match) => '${match.group(1)}500',
  );
  clean = clean.replaceAllMapped(
    RegExp(r'([?&]h=)(?:50|80|100|150|200|250|300)', caseSensitive: false),
    (match) => '${match.group(1)}500',
  );
  clean = clean.replaceAllMapped(
    RegExp(r'([?&]height=)(?:50|80|100|150|200|250|300)', caseSensitive: false),
    (match) => '${match.group(1)}500',
  );

  return clean;
}

String _imageUrl(
  Map<String, dynamic> json, {
  Map<String, dynamic>? imageUrls,
  dynamic albumValue,
  bool includeArtistImage = false,
}) {
  final directImage = _map(json['image']);
  final urls = imageUrls ?? _map(_map(json['images'])['urls']);
  final albumImage = albumValue is Map
      ? (_map(albumValue)['artworkUrl'] ?? _map(albumValue)['image_url'] ?? _map(albumValue)['imageUrl'])
      : null;
  return upgradeImageUrlQuality(
    _first([
      urls['large_artwork'],
      urls['large'],
      directImage['large_artwork'],
      directImage['large'],
      json['artwork_large'],
      albumImage,
      json['imageUrl'],
      json['image_url'],
      json['artworkUrl'],
      urls['medium_artwork'],
      urls['medium'],
      directImage['medium_artwork'],
      directImage['medium'],
      json['artwork_web'],
      json['artwork_medium'],
      json['album_artwork'],
      json['thumbnail'],
      json['photo'],
      json['atw'],
      directImage['small_artwork'],
      directImage['small'],
      directImage['url'],
      urls['small_artwork'],
      urls['small'],
      if (includeArtistImage) json['artist_image'],
    ]),
  );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String _first(List<dynamic> values) => values
    .map((item) => '$item')
    .firstWhere((item) => item.isNotEmpty && item != 'null', orElse: () => '');
String _joined(dynamic value) =>
    value is List ? value.join(', ') : '${value ?? ''}';

class SearchTopResult {
  const SearchTopResult({
    required this.type,
    required this.confidence,
    this.track,
    this.album,
    this.artist,
    this.rawItem,
  });

  final String type;
  final double confidence;
  final Track? track;
  final Album? album;
  final Artist? artist;
  final Map<String, dynamic>? rawItem;

  factory SearchTopResult.fromJson(Map<String, dynamic> json) {
    final type = '${json['type'] ?? ''}'.toLowerCase();
    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    final item = json['item'] is Map
        ? Map<String, dynamic>.from(json['item'] as Map)
        : <String, dynamic>{};
    Track? track;
    Album? album;
    Artist? artist;
    if (type == 'song' || type == 'track') {
      track = Track.fromJson(item);
    } else if (type == 'album') {
      album = Album.fromJson(item);
    } else if (type == 'artist') {
      artist = Artist.fromJson(item);
    }
    return SearchTopResult(
      type: type,
      confidence: confidence,
      track: track,
      album: album,
      artist: artist,
      rawItem: item,
    );
  }
}

