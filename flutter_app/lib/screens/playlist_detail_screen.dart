import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services.dart';
import '../theme/app_theme.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.collection,
    required this.musicApi,
  });

  final CollectionItem collection;
  final MusicApi musicApi;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<Track> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await widget.musicApi.playlist(widget.collection.seokey);
      if (mounted) setState(() { _tracks = results; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatSeconds(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    ),
                    const Spacer(),
                    const Text('Playlist',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    const SizedBox(width: 20),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0E8DC),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selected for you',
                      style: TextStyle(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(collection.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                          color: AppColors.primary, letterSpacing: -0.5)),
                  const SizedBox(height: 16),
                  if (collection.imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: collection.imageUrl,
                        width: double.infinity, height: 200, fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _coverPlaceholder(),
                      ),
                    )
                  else _coverPlaceholder(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.bar_chart_rounded, size: 18, color: AppColors.secondary),
                      const SizedBox(width: 6),
                      Text('${_tracks.length} soundtracks',
                          style: const TextStyle(fontSize: 13, color: AppColors.secondary)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
              ),
            )
          else if (_tracks.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: Text('No tracks found.', style: TextStyle(color: AppColors.secondary))),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final t = _tracks[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: t.imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: t.imageUrl, width: 50, height: 50, fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => _trackThumb())
                                : _trackThumb(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(t.artist,
                                    style: const TextStyle(fontSize: 12, color: AppColors.secondary)),
                              ],
                            ),
                          ),
                          Text(_formatSeconds(t.durationSeconds),
                              style: const TextStyle(fontSize: 13, color: AppColors.secondary)),
                        ],
                      ),
                    );
                  },
                  childCount: _tracks.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
    width: double.infinity, height: 200, color: AppColors.surfaceCard,
    child: const Center(child: Icon(Icons.queue_music_rounded, color: AppColors.muted, size: 48)),
  );

  Widget _trackThumb() => Container(
    width: 50, height: 50, color: AppColors.surfaceCard,
    child: const Icon(Icons.music_note_rounded, color: AppColors.muted, size: 22),
  );
}
