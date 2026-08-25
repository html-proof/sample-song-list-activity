import 'package:audio_service/audio_service.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

MediaItem mediaItemFromMusicItem(MusicItem item) {
  final artist = item.artistName ?? item.subtitle;
  final album = item.albumName ??
      (item.raw['album'] ?? item.raw['album_name'])?.toString();
  final rawArt = item.imageUrl?.trim();
  final artUri = (rawArt != null &&
          rawArt.isNotEmpty &&
          (rawArt.startsWith('http://') ||
              rawArt.startsWith('https://') ||
              rawArt.startsWith('file://') ||
              rawArt.startsWith('content://')))
      ? Uri.tryParse(rawArt)
      : null;

  return MediaItem(
    id: item.id,
    title: item.title,
    artist: artist,
    album: album,
    artUri: artUri,
    duration: item.duration,
    extras: {'streamUrl': item.streamUrl, 'raw': item.raw},
  );
}
