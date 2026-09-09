import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services.dart';
import '../theme/app_theme.dart';

// Languages and genres are universal taxonomy — static is correct here.
const _kLanguages = [
  {'label': 'English', 'flag': '🇬🇧'},
  {'label': 'Hindi', 'flag': '🇮🇳'},
  {'label': 'Tamil', 'flag': '🇮🇳'},
  {'label': 'Telugu', 'flag': '🇮🇳'},
  {'label': 'Spanish', 'flag': '🇪🇸'},
  {'label': 'French', 'flag': '🇫🇷'},
  {'label': 'Portuguese', 'flag': '🇧🇷'},
  {'label': 'Korean', 'flag': '🇰🇷'},
  {'label': 'Japanese', 'flag': '🇯🇵'},
  {'label': 'Arabic', 'flag': '🇸🇦'},
];

const _kGenres = [
  {'label': 'Pop', 'icon': '🎤'},
  {'label': 'Hip-Hop', 'icon': '🎧'},
  {'label': 'Electronic', 'icon': '🎛️'},
  {'label': 'Indie', 'icon': '🎸'},
  {'label': 'R&B / Soul', 'icon': '🎷'},
  {'label': 'Rock', 'icon': '🤘'},
  {'label': 'Jazz', 'icon': '🎺'},
  {'label': 'Classical', 'icon': '🎻'},
  {'label': 'Synthpop', 'icon': '🕹️'},
  {'label': 'Lo-fi', 'icon': '🌙'},
  {'label': 'Folk', 'icon': '🪕'},
  {'label': 'Reggae', 'icon': '🌴'},
];

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.musicApi,
    this.nextRoute = '/home',
  });

  final MusicApi musicApi;
  final String nextRoute;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  int _step = 0;

  final Set<String> _selectedLanguages = {};
  final Set<String> _selectedArtistSeokeys = {};
  final Set<String> _selectedArtistNames = {};
  final Set<String> _selectedGenres = {};

  // Artists fetched from backend for the current language selection.
  List<Artist> _artists = [];
  bool _loadingArtists = false;
  String? _artistError;

  static const _totalSteps = 3;

  bool get _canContinue => switch (_step) {
    0 => _selectedLanguages.isNotEmpty,
    1 => _selectedArtistSeokeys.isNotEmpty,
    _ => _selectedGenres.isNotEmpty,
  };

  Future<void> _fetchArtists() async {
    setState(() {
      _loadingArtists = true;
      _artistError = null;
    });
    try {
      final seen = <String>{};
      final all = <Artist>[];
      final languageList = _selectedLanguages.take(3).toList();
      final resultsList = await Future.wait(
        languageList.map(
          (lang) => widget.musicApi.searchArtists(lang, limit: 20),
        ),
      );
      for (final results in resultsList) {
        for (final a in results) {
          if (a.seokey.isNotEmpty && seen.add(a.seokey)) all.add(a);
        }
      }
      if (mounted) setState(() => _artists = all);
    } catch (_) {
      if (mounted) {
        setState(
          () => _artistError = 'Could not load artists. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingArtists = false);
    }
  }

  Future<void> _next() async {
    if (_step == 0) {
      // Transition to artist step immediately, fetch artists in background with spinner
      setState(() => _step = 1);
      if (_artists.isEmpty) {
        unawaited(_fetchArtists());
      }
      return;
    }
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      return;
    }
    // Final step — save preferences asynchronously and navigate immediately.
    Navigator.pushReplacementNamed(context, widget.nextRoute);
    unawaited(
      widget.musicApi.updateProfile({
        'languages': _selectedLanguages.toList(),
        'favorite_artists': _selectedArtistNames.toList(),
        'favorite_genres': _selectedGenres.toList(),
      }).catchError((_) => <String, dynamic>{}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildProgressBar(),
            const SizedBox(height: 20),
            _buildHeadline(),
            const SizedBox(height: 20),
            Expanded(child: _buildStepContent()),
            _buildContinueButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          if (_step > 0)
            GestureDetector(
              onTap: () => setState(() => _step--),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            )
          else
            const SizedBox(width: 20),
          const Spacer(),
          Text(
            'Step ${_step + 1} of $_totalSteps',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () =>
                Navigator.pushReplacementNamed(context, widget.nextRoute),
            child: const Text(
              'Skip',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        spacing: 6,
        children: List.generate(_totalSteps, (i) {
          final active = i <= _step;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHeadline() {
    const titles = [
      ('Choose your\n', 'language'),
      ('Pick your\n', 'favorite artists'),
      ('Select your\n', 'music genres'),
    ];
    final (prefix, bold) = titles[_step];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 26,
              color: AppColors.primary,
              height: 1.2,
            ),
            children: [
              TextSpan(
                text: prefix,
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
              TextSpan(
                text: bold,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    return switch (_step) {
      0 => _LanguagePicker(
        selected: _selectedLanguages,
        onToggle: (lang) => setState(() {
          _selectedLanguages.contains(lang)
              ? _selectedLanguages.remove(lang)
              : _selectedLanguages.add(lang);
        }),
      ),
      1 => _ArtistPicker(
        artists: _artists,
        selected: _selectedArtistSeokeys,
        loading: _loadingArtists,
        error: _artistError,
        onRetry: _fetchArtists,
        onToggle: (artist) => setState(() {
          if (_selectedArtistSeokeys.contains(artist.seokey)) {
            _selectedArtistSeokeys.remove(artist.seokey);
            _selectedArtistNames.remove(artist.name);
          } else {
            _selectedArtistSeokeys.add(artist.seokey);
            _selectedArtistNames.add(artist.name);
          }
        }),
      ),
      _ => _GenrePicker(
        selected: _selectedGenres,
        onToggle: (genre) => setState(() {
          _selectedGenres.contains(genre)
              ? _selectedGenres.remove(genre)
              : _selectedGenres.add(genre);
        }),
      ),
    };
  }

  Widget _buildContinueButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _canContinue && !_loadingArtists
              ? _next
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.muted,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
            elevation: 0,
          ),
          child: Text(
            _step < _totalSteps - 1 ? 'Continue' : 'Build my sound',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Language picker ──────────────────────────────────────────────────────────

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.selected, required this.onToggle});
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3.2,
      ),
      itemCount: _kLanguages.length,
      itemBuilder: (_, i) {
        final lang = _kLanguages[i]['label']!;
        final flag = _kLanguages[i]['flag']!;
        final on = selected.contains(lang);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onToggle(lang),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: on ? AppColors.primary : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? AppColors.primary : AppColors.divider,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(
                  lang,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : AppColors.primary,
                  ),
                ),
                if (on) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Artist picker — loads real artists from backend ─────────────────────────

class _ArtistPicker extends StatelessWidget {
  const _ArtistPicker({
    required this.artists,
    required this.selected,
    required this.loading,
    required this.onToggle,
    this.error,
    this.onRetry,
  });

  final List<Artist> artists;
  final Set<String> selected; // seokeys
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final void Function(Artist) onToggle;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: AppColors.muted,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.secondary),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (artists.isEmpty) {
      return const Center(
        child: Text(
          'No artists found for your languages.',
          style: TextStyle(color: AppColors.secondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        childAspectRatio: 0.78,
      ),
      itemCount: artists.length,
      itemBuilder: (_, i) {
        final artist = artists[i];
        final on = selected.contains(artist.seokey);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onToggle(artist),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: on
                          ? Border.all(color: AppColors.primary, width: 3)
                          : null,
                    ),
                    child: ClipOval(
                      child: ColorFiltered(
                        colorFilter: on
                            ? const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.multiply,
                              )
                            : const ColorFilter.matrix([
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0.2126,
                                0.7152,
                                0.0722,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ]),
                        child: artist.imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: artist.imageUrl,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                                placeholder: (_, _) =>
                                    Container(color: AppColors.surfaceCard),
                                errorWidget: (_, _, _) => _placeholder(),
                              )
                            : _placeholder(),
                      ),
                    ),
                  ),
                  if (on)
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                artist.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceCard,
    child: const Icon(Icons.person, color: AppColors.muted),
  );
}

// ─── Genre picker ─────────────────────────────────────────────────────────────

class _GenrePicker extends StatelessWidget {
  const _GenrePicker({required this.selected, required this.onToggle});
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.8,
      ),
      itemCount: _kGenres.length,
      itemBuilder: (_, i) {
        final genre = _kGenres[i]['label']!;
        final icon = _kGenres[i]['icon']!;
        final on = selected.contains(genre);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onToggle(genre),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: on ? AppColors.primary : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? AppColors.primary : AppColors.divider,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(
                  genre,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
