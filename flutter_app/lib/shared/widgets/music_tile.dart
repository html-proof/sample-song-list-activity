import 'package:flutter/material.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class MusicTile extends StatelessWidget {
  const MusicTile({
    super.key,
    required this.item,
    required this.onTap,
    this.trailing,
  });

  final MusicItem item;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
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
      subtitle: item.subtitle == null
          ? null
          : Text(
              item.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF73716C)),
            ),
      trailing: trailing ?? const Icon(Icons.more_horiz_rounded),
      onTap: onTap,
    );
  }
}
