import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/core/providers.dart';
import 'package:music_hub_app/features/settings/data/app_settings.dart';
import 'package:music_hub_app/features/settings/presentation/settings_controller.dart';

enum SettingsPage {
  appearance,
  playback,
  downloads,
  recommendations,
  notifications,
  privacy,
  storage,
}

class SettingsDetailScreen extends ConsumerStatefulWidget {
  const SettingsDetailScreen({required this.page, super.key});
  final SettingsPage page;

  @override
  ConsumerState<SettingsDetailScreen> createState() =>
      _SettingsDetailScreenState();
}

class _SettingsDetailScreenState extends ConsumerState<SettingsDetailScreen> {
  late bool _headphoneReminder;
  late int _reminderMinutes;
  late int _breakMinutes;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    final store = ref.read(localStoreProvider);
    _headphoneReminder = store.readSetting('headphone_reminder', false);
    _reminderMinutes = store.readSetting('reminder_minutes', 60);
    _breakMinutes = store.readSetting('break_minutes', 10);
  }

  String get _title => switch (widget.page) {
    SettingsPage.appearance => 'Appearance',
    SettingsPage.playback => 'Playback',
    SettingsPage.downloads => 'Downloads',
    SettingsPage.recommendations => 'Recommendations',
    SettingsPage.notifications => 'Notifications',
    SettingsPage.privacy => 'Privacy & data',
    SettingsPage.storage => 'Storage',
  };

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults();
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          40 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _Intro(page: widget.page),
          const SizedBox(height: 18),
          ...switch (widget.page) {
            SettingsPage.appearance => _appearance(settings),
            SettingsPage.playback => _playback(settings),
            SettingsPage.downloads => _downloads(settings),
            SettingsPage.recommendations => _recommendations(settings),
            SettingsPage.notifications => _notifications(settings),
            SettingsPage.privacy => _privacy(settings),
            SettingsPage.storage => _storage(),
          },
        ],
      ),
    );
  }

  List<Widget> _appearance(AppSettings settings) {
    final group = settings.general;
    return [
      _Group(
        children: [
          _ChoiceSetting<String>(
            title: 'App language',
            value: group['app_language'] as String? ?? 'en',
            choices: const {
              'en': 'English',
              'hi': 'Hindi',
              'ml': 'Malayalam',
              'ta': 'Tamil',
              'te': 'Telugu',
            },
            onChanged: (value) => _update('general', 'app_language', value),
          ),
          const Divider(height: 1, indent: 16),
          _ChoiceSetting<String>(
            title: 'Theme',
            value: group['theme_mode'] as String? ?? 'system',
            choices: const {
              'system': 'Use device setting',
              'light': 'Light',
              'dark': 'Dark',
            },
            onChanged: (value) => _update('general', 'theme_mode', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Artwork colors',
            subtitle: 'Let album artwork gently influence the interface',
            value: group['dynamic_artwork_colors'] as bool? ?? true,
            onChanged: (value) =>
                _update('general', 'dynamic_artwork_colors', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Motion & animations',
            subtitle: 'Use transitions and artwork movement',
            value: group['animations_enabled'] as bool? ?? true,
            onChanged: (value) =>
                _update('general', 'animations_enabled', value),
          ),
        ],
      ),
    ];
  }

  List<Widget> _playback(AppSettings settings) {
    final group = settings.playback;
    const qualities = {
      'auto': 'Automatic',
      'low': 'Data saver',
      'medium': 'Balanced',
      'high': 'High quality',
    };
    return [
      _Group(
        children: [
          _ChoiceSetting<String>(
            title: 'Default quality',
            value: group['streaming_quality'] as String? ?? 'auto',
            choices: qualities,
            onChanged: (value) =>
                _update('playback', 'streaming_quality', value),
          ),
          const Divider(height: 1, indent: 16),
          _ChoiceSetting<String>(
            title: 'On mobile data',
            value: group['mobile_streaming_quality'] as String? ?? 'medium',
            choices: qualities,
            onChanged: (value) =>
                _update('playback', 'mobile_streaming_quality', value),
          ),
          const Divider(height: 1, indent: 16),
          _ChoiceSetting<String>(
            title: 'On Wi-Fi',
            value: group['wifi_streaming_quality'] as String? ?? 'high',
            choices: qualities,
            onChanged: (value) =>
                _update('playback', 'wifi_streaming_quality', value),
          ),
        ],
      ),
      const _Subheading('Queue & transitions'),
      _Group(
        children: [
          _SwitchSetting(
            title: 'Autoplay',
            subtitle: 'Keep music playing after your queue ends',
            value: group['autoplay'] as bool? ?? true,
            onChanged: (value) => _update('playback', 'autoplay', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Normalize volume',
            subtitle: 'Keep songs at a similar listening level',
            value: group['normalize_volume'] as bool? ?? true,
            onChanged: (value) =>
                _update('playback', 'normalize_volume', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Gapless playback',
            subtitle: 'Remove silence between connected tracks',
            value: group['gapless_playback'] as bool? ?? true,
            onChanged: (value) =>
                _update('playback', 'gapless_playback', value),
          ),
          const Divider(height: 1, indent: 16),
          _SliderSetting(
            title: 'Crossfade',
            value: (group['crossfade_seconds'] as num? ?? 0).toDouble(),
            max: 12,
            label: '${group['crossfade_seconds'] ?? 0} sec',
            onChanged: (value) =>
                _update('playback', 'crossfade_seconds', value.round()),
          ),
        ],
      ),
      const _Subheading('Content'),
      _Group(
        children: [
          _SwitchSetting(
            title: 'Allow explicit content',
            value: group['explicit_content'] as bool? ?? true,
            onChanged: (value) =>
                _update('playback', 'explicit_content', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Resume where I stopped',
            value: group['auto_resume'] as bool? ?? true,
            onChanged: (value) => _update('playback', 'auto_resume', value),
          ),
          const Divider(height: 1, indent: 16),
          _ChoiceSetting<String>(
            title: 'Default repeat mode',
            value: group['repeat_mode'] as String? ?? 'off',
            choices: const {'off': 'Off', 'all': 'Repeat all', 'one': 'One'},
            onChanged: (value) => _update('playback', 'repeat_mode', value),
          ),
        ],
      ),
    ];
  }

  List<Widget> _downloads(AppSettings settings) {
    final group = settings.downloads;
    return [
      _Group(
        children: [
          _ChoiceSetting<String>(
            title: 'Download quality',
            value: group['quality'] as String? ?? 'high',
            choices: const {
              'low': 'Data saver',
              'medium': 'Balanced',
              'high': 'High quality',
            },
            onChanged: (value) => _update('downloads', 'quality', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Download on Wi-Fi only',
            value: group['wifi_only'] as bool? ?? true,
            onChanged: (value) => _update('downloads', 'wifi_only', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Download liked songs',
            subtitle: 'Automatically keep new likes offline',
            value: group['auto_download_liked'] as bool? ?? false,
            onChanged: (value) =>
                _update('downloads', 'auto_download_liked', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Download saved playlists',
            value: group['auto_download_playlists'] as bool? ?? false,
            onChanged: (value) =>
                _update('downloads', 'auto_download_playlists', value),
          ),
          const Divider(height: 1, indent: 16),
          _ChoiceSetting<String>(
            title: 'Remove played downloads',
            value: (group['delete_played_after_days'] ?? 'never').toString(),
            choices: const {
              'never': 'Never',
              '7': 'After 7 days',
              '30': 'After 30 days',
              '90': 'After 90 days',
            },
            onChanged: (value) => _update(
              'downloads',
              'delete_played_after_days',
              value == 'never' ? null : int.parse(value),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _recommendations(AppSettings settings) {
    final group = settings.recommendations;
    final enabled = group['enabled'] as bool? ?? true;
    return [
      _Group(
        children: [
          _SwitchSetting(
            title: 'Personal music recommendations',
            subtitle: 'Build mixes around your music taste',
            value: enabled,
            onChanged: (value) => _update('recommendations', 'enabled', value),
          ),
        ],
      ),
      const _Subheading('Signals you allow'),
      Opacity(
        opacity: enabled ? 1 : 0.45,
        child: IgnorePointer(
          ignoring: !enabled,
          child: _Group(
            children: [
              _SwitchSetting(
                title: 'Listening history',
                value: group['use_listening_history'] as bool? ?? true,
                onChanged: (value) =>
                    _update('recommendations', 'use_listening_history', value),
              ),
              const Divider(height: 1, indent: 16),
              _SwitchSetting(
                title: 'Search history',
                value: group['use_search_history'] as bool? ?? true,
                onChanged: (value) =>
                    _update('recommendations', 'use_search_history', value),
              ),
              const Divider(height: 1, indent: 16),
              _SwitchSetting(
                title: 'Liked songs',
                value: group['use_likes'] as bool? ?? true,
                onChanged: (value) =>
                    _update('recommendations', 'use_likes', value),
              ),
              const Divider(height: 1, indent: 16),
              _SwitchSetting(
                title: 'Cross-language discovery',
                value: group['cross_language_discovery'] as bool? ?? true,
                onChanged: (value) => _update(
                  'recommendations',
                  'cross_language_discovery',
                  value,
                ),
              ),
              const Divider(height: 1, indent: 16),
              _SwitchSetting(
                title: 'Discover new artists',
                value: group['discover_new_artists'] as bool? ?? true,
                onChanged: (value) =>
                    _update('recommendations', 'discover_new_artists', value),
              ),
              const Divider(height: 1, indent: 16),
              _SliderSetting(
                title: 'Familiar ↔ adventurous',
                value: (group['exploration_level'] as num? ?? 20).toDouble(),
                max: 100,
                label: '${group['exploration_level'] ?? 20}%',
                onChanged: (value) => _update(
                  'recommendations',
                  'exploration_level',
                  value.round(),
                ),
              ),
              const Divider(height: 1, indent: 16),
              _SliderSetting(
                title: 'Mix diversity',
                value: (group['diversity_level'] as num? ?? 50).toDouble(),
                max: 100,
                label: '${group['diversity_level'] ?? 50}%',
                onChanged: (value) => _update(
                  'recommendations',
                  'diversity_level',
                  value.round(),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _notifications(AppSettings settings) {
    final group = settings.notifications;
    final enabled = group['enabled'] as bool? ?? true;
    Widget toggle(String key, String title) => _SwitchSetting(
      title: title,
      value: group[key] as bool? ?? true,
      onChanged: (value) => _update('notifications', key, value),
    );
    return [
      _Group(
        children: [
          _SwitchSetting(
            title: 'Allow notifications',
            value: enabled,
            onChanged: (value) => _update('notifications', 'enabled', value),
          ),
        ],
      ),
      const _Subheading('Music updates'),
      Opacity(
        opacity: enabled ? 1 : 0.45,
        child: IgnorePointer(
          ignoring: !enabled,
          child: _Group(
            children: [
              toggle('artist_releases', 'Releases from followed artists'),
              const Divider(height: 1, indent: 16),
              toggle('new_music', 'New music'),
              const Divider(height: 1, indent: 16),
              toggle('recommendations', 'Mix recommendations'),
              const Divider(height: 1, indent: 16),
              toggle('playlist_updates', 'Playlist updates'),
              const Divider(height: 1, indent: 16),
              toggle('download_complete', 'Downloads complete'),
            ],
          ),
        ),
      ),
      const _Subheading('Listening health · this device'),
      _Group(
        children: [
          _SwitchSetting(
            title: 'Headphone break reminder',
            subtitle: 'A local reminder; it never leaves this device',
            value: _headphoneReminder,
            onChanged: (value) {
              setState(() => _headphoneReminder = value);
              ref
                  .read(localStoreProvider)
                  .saveSetting('headphone_reminder', value);
              _update('notifications', 'headphone_health', value);
            },
          ),
          const Divider(height: 1, indent: 16),
          _ChoiceSetting<int>(
            title: 'Remind me after',
            value: _reminderMinutes,
            choices: const {30: '30 min', 45: '45 min', 60: '60 min'},
            onChanged: (value) {
              setState(() => _reminderMinutes = value);
              ref
                  .read(localStoreProvider)
                  .saveSetting('reminder_minutes', value);
            },
          ),
          const Divider(height: 1, indent: 16),
          _ChoiceSetting<int>(
            title: 'Suggested break',
            value: _breakMinutes,
            choices: const {5: '5 min', 10: '10 min', 15: '15 min'},
            onChanged: (value) {
              setState(() => _breakMinutes = value);
              ref.read(localStoreProvider).saveSetting('break_minutes', value);
            },
          ),
        ],
      ),
    ];
  }

  List<Widget> _privacy(AppSettings settings) {
    final group = settings.privacy;
    return [
      _Group(
        children: [
          _SwitchSetting(
            title: 'Save listening history',
            subtitle: 'Used for Recently played and Continue listening',
            value: group['save_listening_history'] as bool? ?? true,
            onChanged: (value) =>
                _update('privacy', 'save_listening_history', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Save search history',
            value: group['save_search_history'] as bool? ?? true,
            onChanged: (value) =>
                _update('privacy', 'save_search_history', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Personalized recommendations',
            subtitle: 'When off, your feed uses broad trends and releases',
            value: group['personalized_recommendations'] as bool? ?? true,
            onChanged: (value) =>
                _update('privacy', 'personalized_recommendations', value),
          ),
          const Divider(height: 1, indent: 16),
          _SwitchSetting(
            title: 'Anonymous product analytics',
            value: group['analytics_enabled'] as bool? ?? true,
            onChanged: (value) =>
                _update('privacy', 'analytics_enabled', value),
          ),
        ],
      ),
      const _Subheading('Delete stored activity'),
      _Group(
        children: [
          _ActionSetting(
            title: 'Clear listening history',
            onTap: () => _confirmAction(
              'Clear listening history?',
              ref
                  .read(settingsControllerProvider.notifier)
                  .clearListeningHistory,
            ),
          ),
          const Divider(height: 1, indent: 16),
          _ActionSetting(
            title: 'Clear search history',
            onTap: () => _confirmAction(
              'Clear search history?',
              ref.read(settingsControllerProvider.notifier).clearSearchHistory,
            ),
          ),
          const Divider(height: 1, indent: 16),
          _ActionSetting(
            title: 'Reset recommendation profile',
            onTap: () => _confirmAction(
              'Reset your recommendation profile?',
              ref
                  .read(settingsControllerProvider.notifier)
                  .resetRecommendations,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _storage() {
    final store = ref.read(localStoreProvider);
    final downloads = store.downloads().length;
    return [
      _Group(
        children: [
          ListTile(
            title: const Text('Offline downloads'),
            subtitle: Text('$downloads saved item${downloads == 1 ? '' : 's'}'),
            trailing: const Icon(Icons.download_done_rounded),
          ),
          const Divider(height: 1, indent: 16),
          ListTile(
            title: const Text('Temporary artwork & metadata'),
            subtitle: Text('${store.metadataCacheEntries} cached entries'),
            trailing: TextButton(
              onPressed: _clearingCache
                  ? null
                  : () async {
                      setState(() => _clearingCache = true);
                      await store.clearMetadataCache();
                      if (mounted) setState(() => _clearingCache = false);
                    },
              child: Text(_clearingCache ? 'Clearing…' : 'Clear'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          'Clearing temporary data does not remove your playlists, likes, '
          'account settings or downloaded music.',
          style: TextStyle(color: context.secondaryText, height: 1.4),
        ),
      ),
    ];
  }

  Future<void> _update(String group, String key, Object? value) {
    return ref.read(settingsControllerProvider.notifier).update(group, {
      key: value,
    });
  }

  Future<void> _confirmAction(
    String title,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Done')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete the request: $error')),
        );
      }
    }
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.page});
  final SettingsPage page;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (page) {
      SettingsPage.appearance => (
        Icons.palette_outlined,
        'Make Music Hub feel comfortable on every device.',
        context.accents.peach,
      ),
      SettingsPage.playback => (
        Icons.graphic_eq_rounded,
        'Shape how every song sounds and flows into the next.',
        context.accents.blue,
      ),
      SettingsPage.downloads => (
        Icons.download_for_offline_outlined,
        'Choose what stays ready when your connection is not.',
        context.accents.mint,
      ),
      SettingsPage.recommendations => (
        Icons.auto_awesome_outlined,
        'You decide which signals can influence your music discovery.',
        context.accents.lilac,
      ),
      SettingsPage.notifications => (
        Icons.notifications_none_rounded,
        'Stay informed without letting the app become noisy.',
        context.accents.peach,
      ),
      SettingsPage.privacy => (
        Icons.shield_outlined,
        'Your activity controls affect what the server stores immediately.',
        context.accents.blue,
      ),
      SettingsPage.storage => (
        Icons.storage_outlined,
        'See what Music Hub keeps on this device.',
        context.accents.mint,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Icon(icon, size: 31),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Subheading extends StatelessWidget {
  const _Subheading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(5, 22, 5, 9),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(28),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: TextStyle(color: context.secondaryText)),
    value: value,
    onChanged: onChanged,
  );
}

class _ChoiceSetting<T> extends StatelessWidget {
  const _ChoiceSetting({
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  final String title;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(18),
      items: choices.entries
          .map(
            (entry) =>
                DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.value,
    required this.max,
    required this.label,
    required this.onChanged,
  });
  final String title;
  final double value;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 13, 10, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(label, style: TextStyle(color: context.secondaryText)),
          ],
        ),
        Slider(
          value: value.clamp(0, max).toDouble(),
          max: max,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _ActionSetting extends StatelessWidget {
  const _ActionSetting({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(
      title,
      style: const TextStyle(
        color: Color(0xFFB3261E),
        fontWeight: FontWeight.w700,
      ),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
