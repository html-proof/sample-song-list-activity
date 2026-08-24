import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/downloads/data/download_repository.dart';
import 'package:music_hub_app/shared/utils/item_actions.dart';
import 'package:music_hub_app/shared/widgets/music_tile.dart';

final downloadsRevisionProvider = StateProvider<int>((_) => 0);

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offline',
              style: TextStyle(
                fontSize: 31,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
            Text(
              'Music that travels with you',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: const DownloadsView(),
    );
  }
}

class DownloadsView extends ConsumerWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(downloadsRevisionProvider);
    final items = ref.watch(downloadRepositoryProvider).items();
    return items.isEmpty
        ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.peach,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(22),
                        child: Icon(
                          Icons.download_for_offline_outlined,
                          size: 44,
                        ),
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'No offline music yet',
                      style: TextStyle(fontSize: 20),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Downloads are stored only on this device and require a provider-supported direct audio file.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
          )
        : ListView.builder(
              padding: const EdgeInsets.only(top: 12, bottom: 130),
              itemCount: items.length,
              itemBuilder: (context, index) => MusicTile(
                item: items[index],
                onTap: () => openMusicItem(
                  context,
                  ref,
                  items[index],
                  queue: items,
                  index: index,
                  source: 'downloads',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    await ref
                        .read(downloadRepositoryProvider)
                        .remove(items[index]);
                    ref.read(downloadsRevisionProvider.notifier).state++;
                  },
                ),
              ),
          );
  }
}
