import 'package:audio_service/audio_service.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

MediaItem mediaItemFromMusicItem(MusicItem item) => MediaItem(
  id: item.id,
  title: item.title,
  artist: item.subtitle,
  album: (item.raw['album'] ?? item.raw['album_name'])?.toString(),
  artUri: item.imageUrl == null ? null : Uri.tryParse(item.imageUrl!),
  duration: item.duration,
  extras: {'streamUrl': item.streamUrl, 'raw': item.raw},
);
