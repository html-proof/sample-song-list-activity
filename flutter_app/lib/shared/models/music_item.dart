enum MusicItemType { song, artist, album, playlist, unknown }

class MusicItem {
  const MusicItem({
    required this.id,
    required this.title,
    required this.type,
    required this.raw,
    this.seokey,
    this.subtitle,
    this.imageUrl,
    this.streamUrl,
    this.duration,
  });

  final String id;
  final String? seokey;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? streamUrl;
  final Duration? duration;
  final MusicItemType type;
  final Map<String, dynamic> raw;

  bool get playable =>
      type == MusicItemType.song && streamUrl?.isNotEmpty == true;

  /// The primary artist, as shown on a song or album result.
  String? get artistName => _text(raw['artists'] ?? raw['artist_name']);

  /// The album a song belongs to. Secondary metadata only: a song is still a
  /// song, and must never be presented as its album.
  String? get albumName => _text(raw['album']);

  String? get year {
    final release = _text(raw['release_date'] ?? raw['year']);
    if (release == null) return null;
    final match = RegExp(r'\d{4}').firstMatch(release);
    return match?.group(0);
  }

  int? get songCount => int.tryParse(
    (raw['song_count'] ?? raw['track_count'] ?? '').toString(),
  );

  /// The word shown on the result card so the user can tell at a glance what
  /// kind of thing they are looking at.
  String? get typeLabel => switch (type) {
    MusicItemType.song => 'Song',
    MusicItemType.artist => 'Artist',
    MusicItemType.album => 'Album',
    MusicItemType.playlist => 'Playlist',
    MusicItemType.unknown => null,
  };

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  factory MusicItem.fromJson(Map<String, dynamic> json) {
    final type = _type(json);
    final images = _map(json['images']);
    final imageUrls = _map(images['urls']);
    final streams = _map(json['stream_urls']);
    final streamUrls = _map(streams['urls']);
    final id =
        (json['provider_id'] ??
                json['track_id'] ??
                json['song_id'] ??
                json['artist_id'] ??
                json['provider_artist_id'] ??
                json['album_id'] ??
                json['playlist_id'] ??
                json['seokey'] ??
                json['id'] ??
                '')
            .toString();
    final durationSeconds = int.tryParse(json['duration']?.toString() ?? '');
    return MusicItem(
      id: id,
      seokey: (json['seokey'] ?? json['album_seokey'])?.toString(),
      title:
          (json['title'] ??
                  json['name'] ??
                  json['song_name'] ??
                  json['artist_name'] ??
                  'Unknown')
              .toString(),
      subtitle:
          (json['artists'] ??
                  json['artist_name'] ??
                  json['album'] ??
                  json['language'])
              ?.toString(),
      imageUrl:
          (imageUrls['large_artwork'] ??
                  imageUrls['medium_artwork'] ??
                  json['artwork_url'] ??
                  json['artist_image'] ??
                  json['image_url'])
              ?.toString(),
      streamUrl:
          (json['local_uri'] ??
                  streamUrls['very_high_quality'] ??
                  streamUrls['high_quality'] ??
                  streamUrls['medium_quality'] ??
                  streamUrls['low_quality'])
              ?.toString(),
      duration: durationSeconds == null
          ? null
          : Duration(seconds: durationSeconds),
      type: type,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() => raw;

  /// The content type the backend declared, falling back to field inference.
  ///
  /// Inference is only ever a fallback for the endpoints that predate the
  /// `type` field, because the fields overlap: a song carries `album_id` just
  /// as an album does, and both an album and a playlist carry a track count.
  /// Search always declares the type, so search results never reach the
  /// guessing branch.
  static MusicItemType _type(Map<String, dynamic> json) {
    final declared = json['type']?.toString().trim().toLowerCase();
    switch (declared) {
      case 'song':
      case 'track':
        return MusicItemType.song;
      case 'artist':
        return MusicItemType.artist;
      case 'album':
        return MusicItemType.album;
      case 'playlist':
        return MusicItemType.playlist;
    }
    if (json.containsKey('track_id') ||
        json.containsKey('song_id') ||
        json.containsKey('stream_urls') ||
        json.containsKey('local_uri')) {
      return MusicItemType.song;
    }
    if (json.containsKey('artist_id') ||
        json.containsKey('provider_artist_id')) {
      return MusicItemType.artist;
    }
    if (json.containsKey('album_id')) return MusicItemType.album;
    if (json.containsKey('playlist_id')) return MusicItemType.playlist;
    return MusicItemType.unknown;
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : const {};
}
