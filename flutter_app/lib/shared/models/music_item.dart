enum MusicItemType { song, artist, album, playlist, unknown }

/// Parses the content type a provider payload declares.
///
/// An explicit `type` always wins. Only when the payload carries none do we
/// fall back to the identifier fields, and even then the order matters: an
/// album row also has an artist name, so nothing here may reason about
/// human-readable fields such as the title or the artist.
MusicItemType musicItemTypeFrom(Object? value) {
  return switch (value?.toString().trim().toLowerCase()) {
    'song' || 'songs' || 'track' || 'tracks' => MusicItemType.song,
    'artist' || 'artists' => MusicItemType.artist,
    'album' || 'albums' => MusicItemType.album,
    'playlist' || 'playlists' => MusicItemType.playlist,
    _ => MusicItemType.unknown,
  };
}

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
    this.artistName,
    this.albumName,
    this.songCount,
    this.year,
    this.provider,
  });

  final String id;
  final String? seokey;
  final String title;

  /// Pre-rendered supporting line. Prefer the typed fields below when a widget
  /// needs to know what the text actually means.
  final String? subtitle;
  final String? imageUrl;
  final String? streamUrl;
  final Duration? duration;
  final MusicItemType type;

  /// Songs and albums carry a performing artist; artists and playlists do not.
  final String? artistName;

  /// Songs may name the album they belong to.
  final String? albumName;

  /// Playlists and albums may report how many tracks they hold.
  final int? songCount;

  /// Release year, where the provider supplies one.
  final String? year;

  /// Which provider this row came from, used for identity and dedup.
  final String? provider;

  final Map<String, dynamic> raw;

  bool get playable =>
      type == MusicItemType.song && streamUrl?.isNotEmpty == true;

  /// The line a card shows under the title, chosen by what the item *is*.
  ///
  /// An artist never shows an album or a song name underneath, and a playlist
  /// never borrows an artist it does not have.
  String? get typedSubtitle => switch (type) {
    MusicItemType.song => artistName ?? subtitle,
    MusicItemType.album => artistName ?? subtitle,
    MusicItemType.artist => null,
    MusicItemType.playlist => songCount == null ? subtitle : '$songCount songs',
    MusicItemType.unknown => subtitle,
  };

  /// Stable identity for deduplication, scoped per type so a song and an album
  /// that share a name are never collapsed into one another.
  String get dedupKey {
    final scope = provider ?? 'provider';
    return switch (type) {
      MusicItemType.song =>
        'song|${_normalize(title)}|${_normalize(artistName ?? subtitle)}|'
            '${duration?.inSeconds ?? ''}',
      MusicItemType.artist => 'artist|${_normalize(title)}',
      MusicItemType.album =>
        'album|${_normalize(title)}|${_normalize(artistName ?? subtitle)}|'
            '${year ?? ''}',
      MusicItemType.playlist => 'playlist|$scope|${id.isEmpty ? seokey : id}',
      MusicItemType.unknown => 'unknown|${_normalize(title)}|$id',
    };
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
    final artistName = _text(
      type == MusicItemType.artist
          ? null
          : (json['artists'] ?? json['artist_name'] ?? json['album_artist']),
    );
    final albumName = _text(
      type == MusicItemType.album
          ? null
          : (json['album'] ?? json['album_name']),
    );
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
      subtitle: _subtitleFor(type, json, artistName, albumName),
      imageUrl:
          (imageUrls['large_artwork'] ??
                  imageUrls['medium_artwork'] ??
                  json['artwork_url'] ??
                  json['artist_image'] ??
                  json['image_url'] ??
                  json['image'])
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
      artistName: artistName,
      albumName: albumName,
      songCount: int.tryParse(
        (json['song_count'] ?? json['track_count'] ?? json['total_songs'])
                ?.toString() ??
            '',
      ),
      year: _text(json['year'] ?? json['release_year'] ?? json['release_date']),
      provider: _text(json['provider'] ?? json['source']),
      type: type,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() => raw;

  static String? _subtitleFor(
    MusicItemType type,
    Map<String, dynamic> json,
    String? artistName,
    String? albumName,
  ) {
    return switch (type) {
      MusicItemType.song => artistName ?? albumName,
      MusicItemType.album => artistName,
      // An artist row must not advertise one of its albums or songs as its
      // subtitle, which is what falling through to `album` used to do.
      MusicItemType.artist => null,
      MusicItemType.playlist => _text(json['description']),
      MusicItemType.unknown =>
        artistName ?? albumName ?? _text(json['language']),
    };
  }

  static MusicItemType _type(Map<String, dynamic> json) {
    final declared = musicItemTypeFrom(
      json['type'] ?? json['item_type'] ?? json['content_type'],
    );
    if (declared != MusicItemType.unknown) return declared;
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

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _normalize(String? value) {
    if (value == null) return '';
    final lower = value.toLowerCase();
    final buffer = StringBuffer();
    var previousSpace = false;
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final isAlphanumeric =
          (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x61 && rune <= 0x7a) ||
          rune > 0x7f;
      if (isAlphanumeric) {
        buffer.write(char);
        previousSpace = false;
      } else if (!previousSpace) {
        buffer.write(' ');
        previousSpace = true;
      }
    }
    return buffer.toString().trim();
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : const {};
}
