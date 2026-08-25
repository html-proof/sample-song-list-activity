import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/artists/presentation/artist_controller.dart';
import 'package:music_hub_app/features/artists/presentation/artist_views.dart';
import 'package:music_hub_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

enum MusicPreferencesPage { languages, artists }

class MusicPreferencesScreen extends ConsumerStatefulWidget {
  const MusicPreferencesScreen({required this.page, super.key});
  final MusicPreferencesPage page;

  @override
  ConsumerState<MusicPreferencesScreen> createState() =>
      _MusicPreferencesScreenState();
}

class _MusicPreferencesScreenState
    extends ConsumerState<MusicPreferencesScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<String> _languages = const [];
  List<String> _selectedLanguages = const [];
  List<MusicItem> _selectedArtists = const [];

  @override
  void initState() {
    super.initState();
    // The artist controller is shared with the Library tab, so this screen
    // starts from recommendations rather than inheriting a query typed there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(artistControllerProvider.notifier).cancelSearch();
    });
    unawaited(_load());
  }

  @override
  void deactivate() {
    // Leave the shared controller clean for whichever screen comes next.
    ref.read(artistControllerProvider.notifier).cancelSearch();
    super.deactivate();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(onboardingRepositoryProvider);
      final values = await Future.wait<dynamic>([
        repository.currentPreferences(),
        repository.languages(),
      ]);
      final current = values[0] as Map<String, dynamic>;
      final available = values[1] as List<String>;
      final languages = current['languages'];
      final artists = current['artists'];
      if (!mounted) return;
      setState(() {
        _languages = available;
        _selectedLanguages = languages is List
            ? languages
                  .whereType<Map>()
                  .map((item) => item['language_code'].toString())
                  .toList()
            : const [];
        _selectedArtists = artists is List
            ? artists
                  .whereType<Map>()
                  .map(
                    (item) => MusicItem.fromJson(
                      item.map((key, value) => MapEntry(key.toString(), value)),
                    ),
                  )
                  .toList()
            : const [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (widget.page == MusicPreferencesPage.languages &&
        _selectedLanguages.isEmpty) {
      setState(() => _error = 'Choose at least one music language');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(onboardingRepositoryProvider);
      if (widget.page == MusicPreferencesPage.languages) {
        await repository.updateLanguages(_selectedLanguages);
      } else {
        await repository.updateArtists(_selectedArtists);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Music preferences updated')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final languagesPage = widget.page == MusicPreferencesPage.languages;
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(languagesPage ? 'Music languages' : 'Favorite artists'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 120),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: languagesPage ? palette.blue : palette.lilac,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Text(
                    languagesPage
                        ? 'These shape the music in your feed. Your app '
                              'language is a separate appearance setting.'
                        : 'Add or remove artists to reshape future mixes. '
                              'Search results come from the music provider.',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: palette.onTile,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (languagesPage) _languageChoices() else _artistChoices(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
    );
  }

  Widget _languageChoices() => Wrap(
    spacing: 10,
    runSpacing: 11,
    children: [
      for (final language in _languages)
        FilterChip(
          label: Text(language),
          selected: _selectedLanguages.contains(language),
          showCheckmark: true,
          onSelected: (_) {
            setState(() {
              final next = [..._selectedLanguages];
              next.contains(language)
                  ? next.remove(language)
                  : next.add(language);
              _selectedLanguages = next;
            });
          },
        ),
    ],
  );

  Widget _artistChoices() {
    final searching =
        ref.watch(artistControllerProvider).mode == ArtistMode.search;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ArtistSearchField(),
        if (_selectedArtists.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text(
            'Selected',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              for (final artist in _selectedArtists)
                _ArtistChoice(
                  artist: artist,
                  selected: true,
                  onTap: () => _toggleArtist(artist),
                ),
            ],
          ),
        ],
        const SizedBox(height: 25),
        Text(
          searching ? 'Search results' : 'Recommended for you',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        // A fixed height because this sits inside a ListView; the grids scroll
        // on their own.
        SizedBox(
          height: 420,
          child: searching
              ? ArtistSearchResults(
                  padding: const EdgeInsets.only(bottom: 12),
                  isSelected: _isSelected,
                  onArtistTap: _toggleArtist,
                )
              : RecommendedArtistsView(
                  padding: const EdgeInsets.only(bottom: 12),
                  isSelected: _isSelected,
                  onArtistTap: _toggleArtist,
                ),
        ),
      ],
    );
  }

  bool _isSelected(MusicItem artist) =>
      _selectedArtists.any((selected) => selected.id == artist.id);

  void _toggleArtist(MusicItem artist) {
    setState(() {
      final next = [..._selectedArtists];
      final index = next.indexWhere((item) => item.id == artist.id);
      index < 0 ? next.add(artist) : next.removeAt(index);
      _selectedArtists = next;
    });
  }
}

class _ArtistChoice extends StatelessWidget {
  const _ArtistChoice({
    required this.artist,
    required this.selected,
    required this.onTap,
  });
  final MusicItem artist;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              OrganicArtwork(url: artist.imageUrl, size: 98),
              if (selected)
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: AppTheme.ink),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            artist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
