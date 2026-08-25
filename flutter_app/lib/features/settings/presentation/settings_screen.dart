import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/core/api/api_endpoints.dart';
import 'package:music_hub_app/core/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late bool _autoplay;
  late bool _explicit;
  late bool _headphoneReminder;
  late String _quality;

  @override
  void initState() {
    super.initState();
    final store = ref.read(localStoreProvider);
    _autoplay = store.readSetting('autoplay', true);
    _explicit = store.readSetting('explicit_content', true);
    _headphoneReminder = store.readSetting('headphone_reminder', false);
    _quality = store.readSetting('audio_quality', 'high');
  }

  Future<void> _save(
    String key,
    Object value,
    Map<String, dynamic> remote,
  ) async {
    await ref.read(localStoreProvider).saveSetting(key, value);
    try {
      await ref
          .read(apiClientProvider)
          .patch(ApiEndpoints.preferences, data: remote);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved on this device. Server sync failed: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
        children: [
          const _SectionTitle('Playback'),
          _SettingsGroup(
            children: [
              SwitchListTile(
                title: const Text('Autoplay'),
                subtitle: Text(
                  'Continue with recommendations when the queue ends',
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
                value: _autoplay,
                onChanged: (value) {
                  setState(() => _autoplay = value);
                  _save('autoplay', value, {'autoplay': value});
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: const Text('Streaming quality'),
                subtitle: Text(
                  _quality.replaceAll('_', ' '),
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
                trailing: DropdownButton<String>(
                  value: _quality,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(
                      value: 'very_high',
                      child: Text('Very high'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _quality = value);
                    _save('audio_quality', value, {'audio_quality': value});
                  },
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                title: const Text('Headphone reminder'),
                subtitle: Text(
                  'Keep a reminder for private listening',
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
                value: _headphoneReminder,
                onChanged: (value) {
                  setState(() => _headphoneReminder = value);
                  _save('headphone_reminder', value, {
                    'settings': {'headphone_reminder': value},
                  });
                },
              ),
            ],
          ),
          const _SectionTitle('Content and privacy'),
          _SettingsGroup(
            children: [
              SwitchListTile(
                title: const Text('Allow explicit content'),
                value: _explicit,
                onChanged: (value) {
                  setState(() => _explicit = value);
                  _save('explicit_content', value, {'explicit_content': value});
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).mint,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.lock_outline_rounded, size: 20),
                  ),
                ),
                title: Text('Private by default'),
                subtitle: Text(
                  'Your playlists and listening profile stay private.',
                  style: TextStyle(color: AppPalette.of(context).muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Text(
      text,
      style: TextStyle(
        color: AppPalette.of(context).ink,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppPalette.of(context).panel,
      borderRadius: BorderRadius.circular(28),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}
