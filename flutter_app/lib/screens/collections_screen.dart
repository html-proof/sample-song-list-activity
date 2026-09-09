import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services.dart';
import '../theme/app_theme.dart';
import 'playlist_detail_screen.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key, required this.musicApi});
  final MusicApi musicApi;

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  List<CollectionItem> _collections = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await widget.musicApi.charts(limit: 20);
      if (mounted) setState(() { _collections = results; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load collections.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Collections',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                            letterSpacing: -0.8, color: AppColors.primary)),
                  ),
                  IconButton(icon: const Icon(Icons.refresh_rounded, size: 22), onPressed: _load),
                ],
              ),
            ),
          ),
        ),
        if (_loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
          )
        else if (_error != null)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.muted),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.secondary)),
                  const SizedBox(height: 16),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          )
        else if (_collections.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text('No collections found.', style: TextStyle(color: AppColors.secondary)),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text('${_collections.length} collections',
                  style: const TextStyle(fontSize: 13, color: AppColors.secondary)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = _collections[index];
                  return _CollectionCard(item: item, musicApi: widget.musicApi);
                },
                childCount: _collections.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.82,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.item, required this.musicApi});
  final CollectionItem item;
  final MusicApi musicApi;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(collection: item, musicApi: musicApi),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: item.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _placeholder())
                  : _placeholder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(item.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item.language.isNotEmpty)
            Text(item.language, style: const TextStyle(fontSize: 12, color: AppColors.secondary)),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceCard,
    child: const Center(child: Icon(Icons.queue_music_rounded, color: AppColors.muted, size: 40)),
  );
}
