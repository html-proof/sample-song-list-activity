import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/shared/models/music_item.dart';

/// Opens an artist straight away using the metadata already loaded into the
/// card, so the screen paints before its details request finishes.
///
/// The open is reported afterwards and never awaited: analytics must not sit
/// between a tap and a screen.
void openArtist(
  BuildContext context,
  WidgetRef ref,
  MusicItem artist, {
  String source = 'unknown',
}) {
  final key = artist.seokey;
  if (key == null || key.isEmpty || !context.mounted) return;
  context.push('/artist/$key', extra: artist);
  unawaited(
    Future<void>.sync(
      () => ref
          .read(eventTrackerProvider)
          .track('impression', artist, source: source),
    ).catchError((Object _) {
      // Losing an interaction event must never surface to the user.
    }),
  );
}

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
            source: source,
          );
      if (context.mounted) context.push('/player');
      return;
    case MusicItemType.artist:
      openArtist(context, ref, item, source: source);
      return;
    case MusicItemType.album:
      // Opens the album and shows its tracks. Nothing plays until the user
      // asks for it there.
      final albumKey = item.seokey;
      if (albumKey != null && albumKey.isNotEmpty && context.mounted) {
        context.push('/album/$albumKey');
      }
      return;
    case MusicItemType.playlist:
      final playlistKey = item.seokey;
      if (playlistKey != null && playlistKey.isNotEmpty && context.mounted) {
        context.push('/playlist/$playlistKey', extra: item);
      }
      return;
    case MusicItemType.unknown:
      return;
  }
}
