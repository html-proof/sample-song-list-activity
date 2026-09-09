import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.state,
    required this.onContinue,
  });
  final AppState state;
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Music Hub',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.4,
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onContinue, child: const Text('Skip')),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 310,
              child: Stack(
                children: const [
                  Positioned(
                    left: 0,
                    top: 70,
                    child: _RecordBlob(
                      size: 150,
                      icon: Icons.graphic_eq_rounded,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 0,
                    child: _RecordBlob(size: 125, icon: Icons.album_rounded),
                  ),
                  Positioned(
                    right: 30,
                    bottom: 0,
                    child: _RecordBlob(
                      size: 165,
                      icon: Icons.headphones_rounded,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.displayLarge
                    ?.copyWith(color: context.hubColors.textPrimary),
                children: const [
                  TextSpan(text: 'Welcome to\n'),
                  TextSpan(
                    text: 'Music Hub',
                    style: TextStyle(color: AppColors.orange),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sign in to keep your playlists in sync, or explore instantly as a guest.',
              style: TextStyle(
                color: context.hubColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            PillButton(
              label: state.auth.available
                  ? 'Continue with Google'
                  : 'Explore as guest',
              busy: state.auth.busy,
              onPressed: () async {
                if (state.auth.available) await state.auth.signInWithGoogle();
                onContinue();
              },
            ),
            if (state.auth.available)
              Center(
                child: TextButton(
                  onPressed: onContinue,
                  child: const Text('Explore as guest'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _RecordBlob extends StatelessWidget {
  const _RecordBlob({required this.size, required this.icon});
  final double size;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(size * .34),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .12),
          blurRadius: 25,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: Icon(icon, color: Colors.white, size: size * .43),
  );
}

class ArtistPickerScreen extends StatefulWidget {
  const ArtistPickerScreen({
    super.key,
    required this.state,
    required this.onDone,
    this.onBack,
  });
  final AppState state;
  final VoidCallback onDone;
  final VoidCallback? onBack;

  @override
  State<ArtistPickerScreen> createState() => _ArtistPickerScreenState();
}

class _ArtistPickerScreenState extends State<ArtistPickerScreen> {
  bool _loading = false;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_refresh);
    _scrollController.addListener(_onScroll);
    if (widget.state.onboardingArtists.isEmpty) {
      _load();
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) {
      widget.state.loadMoreOnboardingArtists();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_refresh);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.state.onboardingArtists.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.state.loadOnboardingArtists();
      if (mounted && widget.state.onboardingArtists.isEmpty) {
        setState(
          () => _error = 'No artists found for your selected languages.',
        );
      }
    } catch (_) {
      if (mounted && widget.state.onboardingArtists.isEmpty) {
        setState(
          () => _error = 'Couldn\'t load artists. Check your connection.',
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final artists = widget.state.onboardingArtists;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('Your sound'),
        actions: [
          TextButton(onPressed: widget.onDone, child: const Text('Skip')),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text(
                'Choose your favorite artists',
                style: TextStyle(
                  fontSize: 32,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Text(
                'Pick at least three. We will tune your recommendations.',
                style: TextStyle(color: context.hubColors.textSecondary),
              ),
            ),
            Expanded(
              child: _loading && artists.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && artists.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.hubColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: .78,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                      itemCount:
                          artists.length +
                          (widget.state.onboardingArtistsHasMore ? 1 : 0),
                      itemBuilder: (_, index) {
                        if (index >= artists.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final artist = artists[index];
                        final artistKey = artist.id.isNotEmpty
                            ? artist.id
                            : artist.seokey;
                        final selected = widget.state.selectedArtists.contains(
                              artistKey,
                            ) ||
                            widget.state.selectedArtists.contains(
                              artist.seokey,
                            ) ||
                            widget.state.selectedArtists.contains(
                              artist.artistId,
                            );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.state.toggleArtist(artistKey);
                          },
                          child: Column(
                            children: [
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.orange
                                          : Theme.of(context)
                                                .colorScheme
                                                .outline,
                                      width: selected ? 3 : 1,
                                    ),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipOval(
                                        child: Artwork(
                                          url: artist.imageUrl,
                                          label: artist.name,
                                          radius: 999,
                                          cacheKey: 'artist-${artist.seokey}',
                                          debugKind: 'Artist',
                                        ),
                                      ),
                                      if (selected)
                                        Align(
                                          alignment: Alignment.bottomRight,
                                          child: Container(
                                            margin: const EdgeInsets.all(3),
                                            decoration: const BoxDecoration(
                                              color: AppColors.orange,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.all(5),
                                              child: Icon(
                                                Icons.check,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                artist.name,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: PillButton(
                label: widget.state.selectedArtists.isEmpty
                    ? 'Select at least one artist'
                    : 'Build my sound',
                onPressed: widget.state.selectedArtists.isEmpty
                    ? null
                    : widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
