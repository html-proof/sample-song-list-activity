import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

Future<void> openMusicItem(
  BuildContext context,
  WidgetRef ref,
  MusicItem item, {
  List<MusicItem>? queue,
  int index = 0,
  String source = 'unknown',
}) async {
  switch (item.type) {
    case MusicItemType.song:
      var playableItem = item;
      if (!playableItem.playable && item.seokey != null) {
        try {
          final response = await ref
              .read(apiClientProvider)
              .getMap('${ApiEndpoints.songs}/${item.seokey}');
          playableItem = MusicItem.fromJson(response);
        } catch (_) {
          // Provider and connectivity failures share the same user-facing state.
        }
      }
      if (!playableItem.playable) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This song is not currently available for playback',
              ),
            ),
          );
        }
        return;
      }
      ref
          .read(eventTrackerProvider)
          .track('play', playableItem, source: source);
      ref.read(eventTrackerProvider).recordListen(playableItem, source: source);
      final playableQueue = item.playable
          ? (queue ?? [playableItem]).where((entry) => entry.playable).toList()
          : [playableItem];
      final matchedIndex = playableQueue.indexWhere(
        (entry) => entry.id == playableItem.id,
      );
      await ref
          .read(audioHandlerProvider)
          .playItems(
            playableQueue,
            initialIndex: matchedIndex < 0 ? index : matchedIndex,
          );
      if (context.mounted) context.push('/player');
      return;
    case MusicItemType.artist:
      final key = item.seokey;
      if (key != null && context.mounted) context.push('/artist/$key');
      return;
    case MusicItemType.album:
      final key = item.seokey;
      if (key != null && context.mounted) context.push('/album/$key');
      return;
    case MusicItemType.playlist:
    case MusicItemType.unknown:
      return;
  }
}
