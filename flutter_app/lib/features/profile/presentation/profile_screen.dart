import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/auth/presentation/auth_controller.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value;
    final signingOut = ref.watch(authControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const Text(
          'Your profile',
          style: TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton.filledTonal(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.peach,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Row(
              children: [
                OrganicArtwork(url: user?.photoUrl, size: 104, variant: 1),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LISTENER PROFILE',
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        user?.displayName ?? 'Music listener',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: _ProfileMetric(value: 'Personal', label: 'Feed'),
                ),
                _MetricDivider(),
                Expanded(
                  child: _ProfileMetric(value: 'Adaptive', label: 'Mixes'),
                ),
                _MetricDivider(),
                Expanded(
                  child: _ProfileMetric(value: 'Private', label: 'Library'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text('Your account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 7,
                  ),
                  leading: const _ListIcon(
                    icon: Icons.tune_rounded,
                    color: AppTheme.blue,
                  ),
                  title: const Text(
                    'Playback & content',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Quality, autoplay and privacy',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                  trailing: const Icon(Icons.arrow_outward_rounded),
                  onTap: () => context.push('/settings'),
                ),
                const Divider(height: 1, indent: 74),
                const ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 7,
                  ),
                  leading: _ListIcon(
                    icon: Icons.info_outline_rounded,
                    color: AppTheme.mint,
                  ),
                  title: Text(
                    'Music Hub',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Version 1.0.0',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: signingOut
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: Text(signingOut ? 'Signing out…' : 'Sign out'),
          ),
        ],
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
    ],
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: AppTheme.surfaceHigh);
}

class _ListIcon extends StatelessWidget {
  const _ListIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, size: 21),
  );
}
