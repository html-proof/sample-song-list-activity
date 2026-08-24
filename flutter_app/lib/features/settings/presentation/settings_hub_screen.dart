import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/auth/presentation/auth_controller.dart';
import 'package:music_hub_app/features/settings/presentation/settings_controller.dart';

class SettingsHubScreen extends ConsumerWidget {
  const SettingsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final syncError = ref.watch(settingsSyncErrorProvider);
    final user = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(settingsControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
          children: [
            if (syncError != null)
              _SyncBanner(
                onRetry: () =>
                    ref.read(settingsControllerProvider.notifier).refresh(),
              ),
            _AccountCard(
              name: user?.displayName ?? 'Music listener',
              email: user?.email ?? '',
              onTap: () => context.go('/profile'),
            ),
            const _SectionTitle('Your music'),
            const _SettingsGroup(
              children: [
                _SettingsLink(
                  icon: Icons.language_rounded,
                  color: AppTheme.blue,
                  title: 'Music languages',
                  subtitle: 'Languages used to shape your music feed',
                  route: '/settings/music-languages',
                ),
                _Line(),
                _SettingsLink(
                  icon: Icons.people_alt_outlined,
                  color: AppTheme.lilac,
                  title: 'Favorite artists',
                  subtitle: 'Artists that anchor your recommendations',
                  route: '/settings/favorite-artists',
                ),
              ],
            ),
            const _SectionTitle('Your experience'),
            _SettingsGroup(
              children: [
                _SettingsLink(
                  icon: Icons.palette_outlined,
                  color: AppTheme.peach,
                  title: 'Appearance & language',
                  subtitle: _summary(
                    settings.value?.general['theme_mode'],
                    'System theme',
                  ),
                  route: '/settings/appearance',
                ),
                const _Line(),
                _SettingsLink(
                  icon: Icons.graphic_eq_rounded,
                  color: AppTheme.blue,
                  title: 'Playback',
                  subtitle: _summary(
                    settings.value?.playback['streaming_quality'],
                    'Quality, autoplay and crossfade',
                  ),
                  route: '/settings/playback',
                ),
                const _Line(),
                const _SettingsLink(
                  icon: Icons.download_for_offline_outlined,
                  color: AppTheme.mint,
                  title: 'Downloads',
                  subtitle: 'Quality, Wi-Fi and automatic downloads',
                  route: '/settings/downloads',
                ),
                const _Line(),
                const _SettingsLink(
                  icon: Icons.auto_awesome_outlined,
                  color: AppTheme.lilac,
                  title: 'Recommendations',
                  subtitle: 'Control how your mixes learn',
                  route: '/settings/recommendations',
                ),
              ],
            ),
            const _SectionTitle('Control & privacy'),
            const _SettingsGroup(
              children: [
                _SettingsLink(
                  icon: Icons.notifications_none_rounded,
                  color: AppTheme.peach,
                  title: 'Notifications & listening health',
                  subtitle: 'Releases, downloads and break reminders',
                  route: '/settings/notifications',
                ),
                _Line(),
                _SettingsLink(
                  icon: Icons.shield_outlined,
                  color: AppTheme.blue,
                  title: 'Privacy & data',
                  subtitle: 'History, personalization and analytics',
                  route: '/settings/privacy',
                ),
                _Line(),
                _SettingsLink(
                  icon: Icons.storage_outlined,
                  color: AppTheme.mint,
                  title: 'Storage',
                  subtitle: 'Downloads and temporary app data',
                  route: '/settings/storage',
                ),
              ],
            ),
            const _SectionTitle('Account'),
            _SettingsGroup(
              children: [
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Restore default settings'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _confirmReset(context, ref),
                ),
                const _Line(indent: 56),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
                const _Line(indent: 56),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Color(0xFFB3261E),
                  ),
                  title: const Text(
                    'Delete account',
                    style: TextStyle(
                      color: Color(0xFFB3261E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => _confirmDelete(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'Music Hub 1.0.0',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(Object? value, String fallback) {
    if (value == null) return fallback;
    final text = value.toString().replaceAll('_', ' ');
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  static Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore defaults?'),
        content: const Text(
          'Your playback, download, recommendation and privacy choices will '
          'return to their original values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(settingsControllerProvider.notifier).reset();
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your Google account will be requested again. Then Music Hub will '
          'permanently delete your preferences, history, playlists, likes, '
          'devices, and recommendation profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await ref
        .read(authControllerProvider.notifier)
        .deleteAccount();
    if (!deleted && context.mounted) {
      final state = ref.read(authControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account deletion failed: ${state.error?.toString() ?? 'try again'}',
          ),
        ),
      );
    }
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.email,
    required this.onTap,
  });
  final String name;
  final String email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(30),
    child: Ink(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 27,
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.ink,
            child: Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60),
                  ),
              ],
            ),
          ),
          const Icon(Icons.arrow_outward_rounded, color: Colors.white),
        ],
      ),
    ),
  );
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppTheme.peach,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Expanded(
          child: Text('Saved locally. Waiting to sync with your account.'),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(28),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 21),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => context.push(route),
  );
}

class _Line extends StatelessWidget {
  const _Line({this.indent = 74});
  final double indent;

  @override
  Widget build(BuildContext context) => Divider(height: 1, indent: indent);
}
