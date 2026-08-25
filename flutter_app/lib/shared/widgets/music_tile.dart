import 'package:flutter/material.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class MusicTile extends StatelessWidget {
  const MusicTile({
    super.key,
    required this.item,
    required this.onTap,
    this.trailing,
    this.subtitle,
  });

  final MusicItem item;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Replaces the item's own subtitle. Search uses it to name the content
  /// type on the card without changing the tile's two-line shape.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final secondary = subtitle ?? item.subtitle;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      leading: Artwork(url: item.imageUrl, size: 58, radius: 15),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: secondary == null
          ? null
          : Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
      trailing: trailing ?? const Icon(Icons.more_horiz_rounded),
      onTap: onTap,
    );
  }
}
