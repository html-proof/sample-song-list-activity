import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
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
  List<MusicItem> _results = const [];
  List<MusicItem> _suggested = const [];
  bool _loadingSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
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
      if (widget.page == MusicPreferencesPage.artists) {
        unawaited(_loadSuggestions());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// Recommendations for the artists page, so it opens with something to pick
  /// from instead of an empty search box.
  Future<void> _loadSuggestions() async {
    setState(() => _loadingSuggestions = true);
    try {
      final values = await ref
          .read(onboardingRepositoryProvider)
          .suggestedArtists(_selectedLanguages);
      if (!mounted) return;
      setState(() {
        _suggested = values;
        _loadingSuggestions = false;
      });
    } catch (_) {
      // Suggestions are a convenience; searching still works without them.
      if (!mounted) return;
      setState(() => _loadingSuggestions = false);
    }
  }

  void _search(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final values = await ref
            .read(onboardingRepositoryProvider)
            .artists(query.trim());
        if (mounted) setState(() => _results = values);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    });
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
      List<MusicItem>? storedArtists;
      if (widget.page == MusicPreferencesPage.languages) {
        await repository.updateLanguages(_selectedLanguages);
      } else {
        storedArtists = await repository.updateArtists(_selectedArtists);
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (storedArtists != null) _selectedArtists = storedArtists;
      });
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
                    color: languagesPage
                        ? context.accents.blue
                        : context.accents.lilac,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Text(
                    languagesPage
                        ? 'These shape the music in your feed. Your app '
                              'language is a separate appearance setting.'
                        : 'Add or remove artists to reshape future mixes. '
                              'Search results come from the music provider.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (languagesPage) _languageChoices() else _artistChoices(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: context.colors.error)),
                ],
              ],
            ),
      bottomNavigationBar: _loading
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                18 + MediaQuery.paddingOf(context).bottom,
              ),
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

  Widget _artistChoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        onChanged: _search,
        decoration: const InputDecoration(
          hintText: 'Search artists',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      if (_selectedArtists.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: 22),
          child: Text(
            'No favorite artists yet. Tap any artist below, or search for '
            'one, then save.',
            style: TextStyle(color: context.secondaryText, height: 1.35),
          ),
        )
      else
        _artistSection('Selected', _selectedArtists),
      if (_results.isNotEmpty)
        _artistSection('Search results', _results)
      else if (_loadingSuggestions) ...[
        const SizedBox(height: 25),
        const Center(child: CircularProgressIndicator()),
      ] else if (_suggestions.isNotEmpty)
        _artistSection('Suggested for you', _suggestions),
    ],
  );

  /// Suggestions the user has already picked are dropped, so the list never
  /// shows the same artist twice.
  List<MusicItem> get _suggestions => [
    for (final artist in _suggested)
      if (!_selectedArtists.any((selected) => selected.id == artist.id)) artist,
  ];

  Widget _artistSection(String title, List<MusicItem> artists) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 25),
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 14,
        children: [
          for (final artist in artists)
            _ArtistChoice(
              artist: artist,
              selected: _selectedArtists.any(
                (selected) => selected.id == artist.id,
              ),
              onTap: () => _toggleArtist(artist),
            ),
        ],
      ),
    ],
  );

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
          SizedBox(
            width: 98,
            height: 98,
            child: Stack(
              children: [
                OrganicArtwork(url: artist.imageUrl, size: 98),
                if (selected)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: context.colors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: context.colors.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
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
