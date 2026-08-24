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

  static MusicItemType _type(Map<String, dynamic> json) {
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
