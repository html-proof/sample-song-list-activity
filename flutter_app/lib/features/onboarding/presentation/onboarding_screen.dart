import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/auth/presentation/auth_controller.dart';
import 'package:music_hub_app/features/onboarding/presentation/onboarding_controller.dart';
import 'package:music_hub_app/shared/models/music_item.dart';
import 'package:music_hub_app/shared/widgets/artwork.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: state.step == 1
            ? IconButton.filledTonal(
                onPressed: controller.back,
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.navBar,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: palette.onNavBar,
                    size: 19,
                  ),
                ),
              ),
        title: const Text('Your playlist'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Text(
              '${state.step + 1} / 2',
              style: TextStyle(
                color: palette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= state.step
                            ? palette.ink
                            : palette.panelHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  if (i == 0) const SizedBox(width: 5),
                ],
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: state.step == 0
              ? _Languages(state: state, controller: controller)
              : _Artists(state: state, controller: controller),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  state.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            FilledButton(
              onPressed: state.saving
                  ? null
                  : state.step == 0
                  ? controller.next
                  : () async {
                      final done = await controller.finish();
                      if (done && context.mounted) {
                        ref.read(sessionRepositoryProvider).clear();
                        ref.invalidate(sessionProvider);
                        context.go('/');
                      }
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: state.saving
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          state.step == 0 ? 'Continue' : 'Build my soundtrack',
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Languages extends ConsumerWidget {
  const _Languages({required this.state, required this.controller});

  final OnboardingState state;
  final OnboardingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languages = ref.watch(availableLanguagesProvider);
    final palette = AppPalette.of(context);
    return ListView(
      key: const ValueKey('languages'),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 120),
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Choose your\n',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontSize: 40),
              ),
              TextSpan(
                text: 'listening languages',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontSize: 40, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Pick at least one. We will tune your first mixes around these choices.',
          style: TextStyle(color: palette.muted, height: 1.4),
        ),
        const SizedBox(height: 30),
        languages.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(error.toString()),
          data: (items) => Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              for (final language in items)
                FilterChip(
                  selected: state.languages.contains(language),
                  showCheckmark: false,
                  avatar: state.languages.contains(language)
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 17,
                        )
                      : null,
                  label: Text(language),
                  onSelected: (_) => controller.toggleLanguage(language),
                ),
            ],
          ),
        ),
        const SizedBox(height: 34),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: palette.peach,
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Your feed keeps evolving as you listen, like, skip, and replay.',
                  style: TextStyle(fontWeight: FontWeight.w600, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Artists extends StatelessWidget {
  const _Artists({required this.state, required this.controller});

  final OnboardingState state;
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      key: const ValueKey('artists'),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 120),
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Choose your\n',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontSize: 40),
              ),
              TextSpan(
                text: 'favorite artists',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontSize: 40, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${state.artists.length} selected · choose at least 3',
          style: TextStyle(color: palette.muted),
        ),
        const SizedBox(height: 22),
        TextField(
          autofocus: true,
          onChanged: controller.searchArtists,
          decoration: const InputDecoration(
            hintText: 'Search an artist',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 24),
        state.results.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(error.toString()),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 50),
                child: Column(
                  children: [
                    Icon(
                      Icons.person_search_rounded,
                      size: 52,
                      color: palette.muted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Search to shape your first playlist',
                      style: TextStyle(color: palette.muted),
                    ),
                  ],
                ),
              );
            }
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 10,
              runSpacing: 22,
              children: [
                for (var index = 0; index < items.length; index++)
                  _ArtistChoice(
                    artist: items[index],
                    index: index,
                    selected: state.artists.any(
                      (selected) => selected.id == items[index].id,
                    ),
                    onTap: () => controller.toggleArtist(items[index]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ArtistChoice extends StatelessWidget {
  const _ArtistChoice({
    required this.artist,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final MusicItem artist;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 105,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              OrganicArtwork(url: artist.imageUrl, size: 102, variant: index),
              if (selected)
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: AppTheme.ink),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
