import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../app_state.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SharedPreferences? _local;
  bool _loading = true, _saving = false;
  String _version = 'Loading…';
  int _cacheSizeBytes = 0;
  final Map<String, dynamic> _values = {
    'data_saver_enabled': false, 'autoplay_enabled': true,
    'push_notifications_enabled': false, 'explicit_content_enabled': false,
    'streaming_quality_wifi': 'automatic', 'streaming_quality_mobile': 'automatic',
    'download_quality': 'high', 'equalizer_preset': 'Default',
    'sleep_timer_minutes': 0, 'stream_mobile_data': true,
    'download_mobile_data': false, 'preload_next_song': true,
    'background_data_allowed': true, 'image_quality': 'automatic',
    'offline_mode': false, 'cache_limit_mb': 500,
  };

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      _local = await SharedPreferences.getInstance();
      Map<String, dynamic> cloud = widget.state.profile;
      if (widget.state.auth.isSignedIn) {
        try {
          cloud = await widget.state.api.profile();
          widget.state.profile = cloud;
        } catch (_) {}
      }
      for (final key in _values.keys) {
        _values[key] = cloud[key] ?? _local!.get(key) ?? _values[key];
      }
      widget.state.player.autoplayEnabled = _values['autoplay_enabled'] == true;
      final timer = _values['sleep_timer_minutes'] as int?;
      if (timer != null && timer > 0) {
        widget.state.player.setSleepTimer(Duration(minutes: timer));
      }
      final limitMb = _values['cache_limit_mb'] as int? ?? 500;
      widget.state.audioCache?.maxSizeBytes = limitMb * 1024 * 1024;
      _cacheSizeBytes = await widget.state.audioCache?.calculateCacheSize() ?? 0;
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }
  Future<void> _set(String key, dynamic value) async {
    if (_saving) return;
    final old = _values[key]; setState(() => _values[key] = value);
    try {
      if (_local != null) { if (value is bool) await _local!.setBool(key, value); if (value is int) await _local!.setInt(key, value); if (value is String) await _local!.setString(key, value); }
      if (widget.state.auth.isSignedIn && key != 'sleep_timer_minutes' && key != 'cache_limit_mb') { setState(() => _saving = true); await widget.state.api.updateProfile({key: value}); widget.state.profile[key] = value; }
      if (key == 'autoplay_enabled') widget.state.player.autoplayEnabled = value == true;
      await widget.state.api.policy?.setValue(key, value);
      if (key == 'download_mobile_data' && value == true) await widget.state.downloads.resumeAll();
      if (key == 'sleep_timer_minutes') widget.state.player.setSleepTimer(value == 0 ? null : Duration(minutes: value as int));
      if (key == 'cache_limit_mb') widget.state.audioCache?.maxSizeBytes = (value as int) * 1024 * 1024;
      if (mounted) _toast('Setting saved');
    } catch (_) { if (mounted) { setState(() => _values[key] = old); _toast("Couldn't update this setting. Check your connection.", error: true); } }
    finally { if (mounted) setState(() => _saving = false); }
  }
  void _toast(String s, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), backgroundColor: error ? Colors.red.shade700 : null));
  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      _cacheSizeBytes = await widget.state.audioCache?.calculateCacheSize() ?? 0;
      setState(() {});
    }
  }

  @override Widget build(BuildContext context) {
    final user = widget.state.auth.user;
    final langs = (widget.state.profile['languages'] as List? ?? const []).join(', ');
    final totalStorageBytes = widget.state.downloads.downloadedBytes + _cacheSizeBytes;
    return Scaffold(appBar: AppBar(title: const Text('Settings'), centerTitle: true), body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
      _heading('Account'), _tile(Icons.account_circle_outlined, user?.displayName ?? 'Guest account', trailing: user?.email ?? 'Sign in to sync your music', onTap: user == null ? widget.state.auth.signInWithGoogle : () => _open(AccountDetailsScreen(state: widget.state))),
      if (user != null) _tile(Icons.person_outline, 'Edit profile', onTap: () => _open(EditProfileScreen(state: widget.state))),
      _heading('Appearance'), AnimatedBuilder(animation: ThemePreferenceController.instance, builder: (_, _) => RadioGroup<ThemePreference>(groupValue: ThemePreferenceController.instance.preference, onChanged: (value) { if (value != null) ThemePreferenceController.instance.setPreference(value); }, child: Column(children: ThemePreference.values.map((option) => RadioListTile<ThemePreference>(contentPadding: EdgeInsets.zero, value: option, title: Text(_themeLabel(option)), subtitle: Text(_themeDescription(option)))).toList()))),
      _heading('Preferences'), _tile(Icons.language, 'Language', trailing: langs.isEmpty ? 'Not set' : langs, onTap: () => _open(LanguagePreferencesScreen(state: widget.state))), _tile(Icons.high_quality_outlined, 'Audio quality', trailing: _qualitySummary(_values['streaming_quality_wifi'], _values['streaming_quality_mobile']), onTap: () => _open(AudioQualityScreen(values: _values, onSave: _set))), _switch(Icons.data_saver_off_outlined, 'Data saver', _values['data_saver_enabled'] == true, (v) => _set('data_saver_enabled', v), enabled: _values['data_saver_enabled'] != null), _switch(Icons.signal_cellular_alt, 'Stream using mobile data', _values['stream_mobile_data'] == true, (v) => _set('stream_mobile_data', v), enabled: _values['stream_mobile_data'] != null), _switch(Icons.download_for_offline, 'Download using mobile data', _values['download_mobile_data'] == true, (v) => _set('download_mobile_data', v), enabled: _values['download_mobile_data'] != null), _switch(Icons.skip_next, 'Preload next song', _values['preload_next_song'] == true, (v) => _set('preload_next_song', v), enabled: _values['preload_next_song'] != null),
      _heading('Playback'), _tile(Icons.bedtime_outlined, 'Sleep timer', trailing: _timerLabel, onTap: _chooseTimer), _tile(Icons.equalizer_rounded, 'Equalizer', trailing: _textValue(_values['equalizer_preset']), onTap: () => _open(EqualizerScreen(values: _values, onSave: _set))), _switch(Icons.play_circle_outline, 'Autoplay', _values['autoplay_enabled'] == true, (v) => _set('autoplay_enabled', v), enabled: _values['autoplay_enabled'] != null), _switch(Icons.sync, 'Background data', _values['background_data_allowed'] == true, (v) => _set('background_data_allowed', v), enabled: _values['background_data_allowed'] != null), _switch(Icons.offline_bolt_outlined, 'Offline mode', _values['offline_mode'] == true, (v) => _set('offline_mode', v), enabled: _values['offline_mode'] != null),
      _heading('Notifications & content'), _switch(Icons.notifications_none, 'Push notifications', _values['push_notifications_enabled'] == true, _setNotifications, enabled: _values['push_notifications_enabled'] != null), _switch(Icons.explicit_outlined, 'Show explicit content', _values['explicit_content_enabled'] == true, (v) => _set('explicit_content_enabled', v), enabled: _values['explicit_content_enabled'] != null),
      _heading('Storage'), _tile(Icons.storage_outlined, 'Storage used', trailing: _formatBytes(totalStorageBytes), onTap: () => _open(StorageDetailsScreen(state: widget.state, cacheSizeBytes: _cacheSizeBytes))), _tile(Icons.cleaning_services_outlined, 'Clear cache', trailing: _formatBytes(_cacheSizeBytes), onTap: _clearCache), _tile(Icons.tune_outlined, 'Cache limit', trailing: '${_values['cache_limit_mb'] ?? 500} MB', onTap: _chooseCacheLimit), _tile(Icons.download_outlined, 'Downloads', trailing: '${widget.state.downloads.downloaded.length} songs', onTap: () => _open(DownloadsScreen(state: widget.state))),
      _heading('Support'), _tile(Icons.help_outline, 'Help & support', onTap: () => _open(const SupportScreen())), _tile(Icons.privacy_tip_outlined, 'Privacy policy', onTap: () => _open(const WebLinkScreen(title: 'Privacy policy', url: 'https://soundwaves-cdn.imeseban.workers.dev/privacy-policy'))), _tile(Icons.info_outline, 'Version', trailing: _version, onTap: () => _open(AboutScreen(version: _version))),
      if (user != null) ...[const SizedBox(height: 18), OutlinedButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout), label: const Text('Sign out')), const SizedBox(height: 10), TextButton.icon(onPressed: _deleteAccount, style: TextButton.styleFrom(foregroundColor: Colors.red), icon: const Icon(Icons.delete_forever_outlined), label: const Text('Delete account'))],
    ]));
  }
  String get _timerLabel { final m = _values['sleep_timer_minutes'] as int?; return m == null ? 'Not set' : m == 0 ? 'Off' : '$m min'; }
  String _textValue(dynamic v) => v == null ? 'Not set' : '$v';
  String _quality(dynamic v) {
    if (v == null) return 'Automatic';
    final s = '$v';
    switch (s.toLowerCase()) {
      case 'very_high': return 'Very High (320k)';
      case 'high': return 'High (160k)';
      case 'normal':
      case 'medium': return 'Normal (128k)';
      case 'low': return 'Low (64k)';
      case 'automatic':
      default: return 'Automatic';
    }
  }
  String _qualitySummary(dynamic wifi, dynamic mobile) => 'Wi-Fi: ${_quality(wifi)} • Mobile: ${_quality(mobile)}';
  String _formatBytes(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(0)} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  String _themeLabel(ThemePreference value) => switch (value) { ThemePreference.system => 'System default', ThemePreference.light => 'Light', ThemePreference.dark => 'Dark' };
  String _themeDescription(ThemePreference value) => switch (value) { ThemePreference.system => 'Use the same appearance as your device.', ThemePreference.light => 'Always use Music Hub light appearance.', ThemePreference.dark => 'Always use Music Hub dark appearance.' };
  Future<void> _chooseTimer() async { const options = <int, String>{0: 'Off', 5: '5 minutes', 10: '10 minutes', 15: '15 minutes', 30: '30 minutes', 45: '45 minutes', 60: '1 hour'}; final value = await showModalBottomSheet<int>(context: context, builder: (_) => SafeArea(child: ListView(shrinkWrap: true, children: options.entries.map((e) => ListTile(title: Text(e.value), trailing: _values['sleep_timer_minutes'] == e.key ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, e.key))).toList()))); if (value != null) await _set('sleep_timer_minutes', value); }
  Future<void> _chooseCacheLimit() async {
    const options = <int, String>{250: '250 MB', 500: '500 MB (Default)', 1000: '1 GB', 2000: '2 GB'};
    final currentVal = _values['cache_limit_mb'] as int? ?? 500;
    final value = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: options.entries.map((e) => ListTile(
            title: Text(e.value),
            trailing: currentVal == e.key ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, e.key),
          )).toList(),
        ),
      ),
    );
    if (value != null) await _set('cache_limit_mb', value);
  }
  Future<void> _setNotifications(bool value) async { if (!value) { await _set('push_notifications_enabled', false); return; } try { if (!kIsWeb) { final p = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true); if (p.authorizationStatus == AuthorizationStatus.denied) { _toast('Notifications are disabled in your device settings.', error: true); return; } final token = await FirebaseMessaging.instance.getToken(); if (token != null && widget.state.auth.isSignedIn) await widget.state.api.registerDevice(token); } await _set('push_notifications_enabled', true); } catch (_) { _toast('Notifications could not be enabled.', error: true); } }
  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'Temporary streaming audio files will be removed. Your downloaded offline music and account data will not be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear cache')),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.audioCache?.clearCache();
      _cacheSizeBytes = await widget.state.audioCache?.calculateCacheSize() ?? 0;
      if (mounted) {
        setState(() {});
        _toast('Cache cleared');
      }
    }
  }
  Future<void> _signOut() async { final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Sign out of Music Hub?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out'))])); if (ok == true) { await widget.state.auth.signOut(); if (mounted) Navigator.of(context).popUntil((r) => r.isFirst); } }
  Future<void> _deleteAccount() async { final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete account?'), content: const Text('Deleting your account permanently removes your Music Hub profile and associated account data according to the application retention policy.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete permanently'))])); if (ok != true || !mounted) return; setState(() => _saving = true); try { await widget.state.api.deleteAccount(); await widget.state.downloads.removeAll(); await widget.state.auth.signOut(); if (mounted) Navigator.of(context).popUntil((r) => r.isFirst); } catch (_) { if (mounted) _toast('Account deletion failed. Please try again.', error: true); } finally { if (mounted) setState(() => _saving = false); } }
  Widget _heading(String s) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 6), child: Text(s.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8)));
  Widget _switch(IconData icon, String title, bool value, ValueChanged<bool> change, {bool enabled = true}) => SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, secondary: Icon(icon), title: Text(title), value: value, onChanged: _saving || !enabled ? null : change);
  Widget _tile(IconData icon, String title, {String? trailing, VoidCallback? onTap}) => ListTile(contentPadding: EdgeInsets.zero, minVerticalPadding: 8, leading: Icon(icon), title: Text(title), subtitle: title.contains('account') && trailing != null ? Text(trailing) : null, trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (trailing != null && !title.contains('account')) Text(trailing, style: const TextStyle(color: AppColors.muted)), const SizedBox(width: 4), const Icon(Icons.chevron_right, color: AppColors.muted)]), onTap: onTap);
}

class AccountDetailsScreen extends StatelessWidget { const AccountDetailsScreen({super.key, required this.state}); final AppState state; @override Widget build(BuildContext context) { final u = state.auth.user; return _Page(title: 'Account details', children: [_Avatar(url: u?.photoURL), Text(u?.displayName ?? 'Unknown user', style: Theme.of(context).textTheme.headlineSmall), Text(u?.email ?? 'No email available'), _Info('Account ID', u?.uid ?? 'Unavailable'), _Info('Authentication', u?.providerData.isNotEmpty == true ? u!.providerData.first.providerId : 'Firebase')]); } }
class EditProfileScreen extends StatefulWidget { const EditProfileScreen({super.key, required this.state}); final AppState state; @override State<EditProfileScreen> createState() => _EditProfileState(); }
class _EditProfileState extends State<EditProfileScreen> { late final TextEditingController name; bool saving = false; @override void initState() { super.initState(); name = TextEditingController(text: widget.state.profile['display_name'] as String? ?? widget.state.auth.user?.displayName ?? ''); } @override void dispose() { name.dispose(); super.dispose(); } @override Widget build(BuildContext context) => _Page(title: 'Edit profile', children: [_Avatar(url: widget.state.auth.user?.photoURL), TextField(controller: name, decoration: const InputDecoration(labelText: 'Display name')), const SizedBox(height: 20), FilledButton(onPressed: saving ? null : save, child: saving ? const CircularProgressIndicator() : const Text('Save changes'))]); Future<void> save() async { if (name.text.trim().isEmpty) return; setState(() => saving = true); try { widget.state.profile = await widget.state.api.updateProfile({'display_name': name.text.trim()}); if (mounted) Navigator.pop(context); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save profile.'))); } finally { if (mounted) setState(() => saving = false); } } }

class LanguagePreferencesScreen extends StatefulWidget {
  const LanguagePreferencesScreen({super.key, required this.state});
  final AppState state;

  @override
  State<LanguagePreferencesScreen> createState() => _LanguageState();
}

class _LanguageState extends State<LanguagePreferencesScreen> {
  List<Map<String, dynamic>> items = [];
  final selected = <String>{};
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    selected.addAll(
      (widget.state.profile['language_ids'] as List? ?? const []).map(
        (value) => '$value',
      ),
    );
    load();
  }

  Future<void> load() async {
    try {
      items = await widget.state.api.languages();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one language.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final response = await widget.state.api.saveLanguageIds(selected.toList());
      final savedIds = response['language_ids'];
      final List<String> ids = (savedIds is List ? savedIds : selected.toList())
          .map((value) => '$value')
          .toList();
      final List<String> names = ids
          .map((id) => '${items.cast<Map<String, dynamic>?>().firstWhere(
                (item) => '${item?['id'] ?? item?['name']}' == id,
                orElse: () => null,
              )?['name'] ?? id}')
          .toList();
      await widget.state.updateLanguages(ids, names);
      try {
        await widget.state.loadPersonalized(refresh: true);
      } catch (_) {
        // The preference is already saved; cached content can refresh later.
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save languages.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Language preferences',
    children: [
      if (loading)
        const Center(child: CircularProgressIndicator())
      else ...[
        const Text('Choose the languages used for music discovery.'),
        ...items.map((language) {
          final id = '${language['id'] ?? language['name']}';
          return CheckboxListTile(
            value: selected.contains(id),
            title: Text('${language['name'] ?? language['label'] ?? id}'),
            onChanged: (value) => setState(
              () => value == true ? selected.add(id) : selected.remove(id),
            ),
          );
        }),
        FilledButton(
          onPressed: saving ? null : save,
          child: saving
              ? const CircularProgressIndicator()
              : const Text('Save'),
        ),
      ],
    ],
  );
}

class AudioQualityScreen extends StatefulWidget {
  const AudioQualityScreen({super.key, required this.values, required this.onSave});
  final Map<String, dynamic> values;
  final Future<void> Function(String, dynamic) onSave;

  @override
  State<AudioQualityScreen> createState() => _AudioQualityScreenState();
}

class _AudioQualityScreenState extends State<AudioQualityScreen> {
  late final Map<String, dynamic> _localValues;

  @override
  void initState() {
    super.initState();
    _localValues = Map<String, dynamic>.from(widget.values);
  }

  Future<void> _update(String key, String value) async {
    setState(() => _localValues[key] = value);
    await widget.onSave(key, value);
  }

  static const _streamingOptions = <String, Map<String, String>>{
    'automatic': {
      'title': 'Automatic (Recommended)',
      'subtitle': 'Selects optimal quality before playback; strictly locked during track',
    },
    'very_high': {
      'title': 'Very High (256–320 kbps)',
      'subtitle': 'Studio quality • WARNING: Uses significantly more data (~9–10 MB/song)',
    },
    'high': {
      'title': 'High (128–160 kbps AAC)',
      'subtitle': 'Crisp and clear • Recommended balance (~4–5 MB/song)',
    },
    'normal': {
      'title': 'Normal (96–128 kbps)',
      'subtitle': 'Standard balanced quality • Uses ~3–4 MB/song',
    },
    'low': {
      'title': 'Low (64–96 kbps - Data Saver)',
      'subtitle': 'Minimal mobile data usage • Uses ~1.5–2 MB/song',
    },
  };

  static const _downloadOptions = <String, Map<String, String>>{
    'very_high': {
      'title': 'Very High (256–320 kbps)',
      'subtitle': 'Highest fidelity • Heavy storage (~8–10 MB/song)',
    },
    'high': {
      'title': 'High (128–160 kbps AAC)',
      'subtitle': 'Recommended high quality • ~4–5 MB/song',
    },
    'normal': {
      'title': 'Normal (96–128 kbps)',
      'subtitle': 'Moderate download size • ~3–4 MB/song',
    },
    'low': {
      'title': 'Low (64–96 kbps)',
      'subtitle': 'Fastest download & minimal storage • ~1.5–2 MB/song',
    },
  };

  Widget _buildSection(String title, String key, Map<String, Map<String, String>> options) {
    final current = (_localValues[key] as String?) ?? (key == 'download_quality' ? 'high' : 'automatic');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: options.entries.map((entry) {
              return RadioListTile<String>(
                value: entry.key,
                groupValue: current,
                title: Text(entry.value['title']!, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  entry.value['subtitle']!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
                onChanged: (val) {
                  if (val != null) _update(key, val);
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Audio quality',
    children: [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_clock_outlined, size: 20, color: Colors.blueAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Quality is locked during playback so songs never stutter or change pitch mid-track. Changes take effect on the next song.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
      _buildSection('Wi-Fi streaming quality', 'streaming_quality_wifi', _streamingOptions),
      _buildSection('Mobile data streaming quality', 'streaming_quality_mobile', _streamingOptions),
      _buildSection('Download quality', 'download_quality', _downloadOptions),
    ],
  );
}
class EqualizerScreen extends StatelessWidget { const EqualizerScreen({super.key, required this.values, required this.onSave}); final Map<String, dynamic> values; final Future<void> Function(String, dynamic) onSave; @override Widget build(BuildContext context) => _Page(title: 'Equalizer', children: [RadioGroup<String>(groupValue: values['equalizer_preset'] as String?, onChanged: (v) { if (v != null) onSave('equalizer_preset', v); }, child: Column(children: ['Default', 'Bass Boost', 'Vocal', 'Rock', 'Pop', 'Classical'].map((e) => RadioListTile<String>(value: e, title: Text(e))).toList()))]); }
class StorageDetailsScreen extends StatelessWidget {
  const StorageDetailsScreen({super.key, required this.state, this.cacheSizeBytes = 0});
  final AppState state;
  final int cacheSizeBytes;

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Storage details',
    children: [
      Text('Downloaded offline music — ${_formatBytes(state.downloads.downloadedBytes)} (${state.downloads.downloaded.length} songs)'),
      Text('Temporary streaming cache — ${_formatBytes(cacheSizeBytes)}'),
      const Text('Artwork and metadata — included with cached tracks'),
      const Divider(),
      FilledButton.icon(
        onPressed: state.downloads.hasDownloads ? () => state.downloads.removeAll() : null,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Remove all downloads'),
      ),
    ],
  );
}
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.state});
  final AppState state;

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.downloads,
    builder: (context, _) {
      final downloaded = state.downloads.downloaded;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Offline Downloads'),
          actions: [
            if (downloaded.isNotEmpty)
              IconButton(
                tooltip: 'Delete all downloads',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete all downloads?'),
                      content: const Text('This will remove all offline downloaded music from your device storage.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete All'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await state.downloads.removeAll();
                  }
                },
              ),
          ],
        ),
        body: downloaded.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 64,
                        color: Theme.of(context).disabledColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No offline songs',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Downloaded tracks will appear here so you can listen without internet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: downloaded.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final entry = downloaded[index];
                  final track = entry.track;
                  final isCurrent = state.player.current?.id == track.id;
                  final sizeFormatted = _formatBytes(entry.downloadedBytes);

                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: track.imageUrl.isNotEmpty
                          ? Image.network(
                              track.imageUrl,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 52,
                                height: 52,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.music_note),
                              ),
                            )
                          : Container(
                              width: 52,
                              height: 52,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.music_note),
                            ),
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                    subtitle: Text(
                      '${track.artist} • $sizeFormatted',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete song from storage',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete downloaded song?'),
                            content: Text('Remove "${track.title}" from your device storage?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await state.downloads.remove(track.seokey);
                          if (track.id.isNotEmpty) await state.downloads.remove(track.id);
                        }
                      },
                    ),
                    onTap: () {
                      final queue = downloaded.map((e) => e.track).toList();
                      state.play(track, queue);
                    },
                  );
                },
              ),
      );
    },
  );
}
class SupportScreen extends StatelessWidget { const SupportScreen({super.key}); @override Widget build(BuildContext context) => _Page(title: 'Help & support', children: [_Action('Help center', 'https://soundwaves-cdn.imeseban.workers.dev/help'), _Action('Frequently asked questions', 'https://soundwaves-cdn.imeseban.workers.dev/faq'), _Action('Contact support', 'mailto:support@music-hub-d7489.firebaseapp.com')]); }
class AboutScreen extends StatelessWidget { const AboutScreen({super.key, required this.version}); final String version; @override Widget build(BuildContext context) => _Page(title: 'About Music Hub', children: [const Icon(Icons.graphic_eq, size: 72, color: AppColors.orange), const Text('Music Hub'), _Info('Version', version), const _Info('Privacy', 'Available online')]); }
class WebLinkScreen extends StatelessWidget { const WebLinkScreen({super.key, required this.title, required this.url}); final String title, url; @override Widget build(BuildContext context) { unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)); return _Page(title: title, children: [Text('Opening $title…'), TextButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: const Text('Retry'))]); } }
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children
            .map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: w,
                ))
            .toList(),
      ),
    ),
  );
}
class _Info extends StatelessWidget { const _Info(this.label, this.value); final String label, value; @override Widget build(BuildContext context) => ListTile(title: Text(label), subtitle: Text(value)); }
class _Avatar extends StatelessWidget { const _Avatar({this.url}); final String? url; @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.only(bottom: 24), child: CircleAvatar(radius: 42, backgroundImage: url == null ? null : CachedNetworkImageProvider(url!), child: url == null ? const Icon(Icons.person, size: 42) : null))); }
class _Action extends StatelessWidget { const _Action(this.title, this.url); final String title, url; @override Widget build(BuildContext context) => ListTile(title: Text(title), trailing: const Icon(Icons.open_in_new), onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)); }
