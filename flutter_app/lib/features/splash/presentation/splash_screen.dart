import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/core/startup/startup_controller.dart';
import 'package:music_hub_app/core/startup/startup_state.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _animationDuration = Duration(milliseconds: 1150);

  late final AnimationController _animation;
  Future<StartupDestination>? _resolution;
  bool _completing = false;
  bool _navigated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: _animationDuration)
      ..forward();
    // Resolving the destination costs a session round trip. Starting it with
    // the animation instead of after it hides that latency behind frames the
    // user is already watching.
    _resolution = ref.read(startupControllerProvider).completeSplash();
    unawaited(_finishAfterAnimation());
  }

  Future<void> _finishAfterAnimation() async {
    // Future.wait subscribes to both futures now, so a resolution failure that
    // lands mid-animation is delivered here rather than going unhandled.
    await _navigateWhenReady(
      Future.wait<Object?>([
        Future<void>.delayed(_animationDuration),
        _resolution!,
      ]).then((results) => results[1]! as StartupDestination),
    );
  }

  Future<void> _complete() async {
    if (_completing || _navigated) return;
    // Reuse the in-flight resolution when there is one; only a retry after a
    // failure needs to ask the controller again.
    final pending = _resolution ??= ref
        .read(startupControllerProvider)
        .completeSplash();
    setState(() {
      _completing = true;
      _error = null;
    });
    await _navigateWhenReady(pending);
  }

  Future<void> _navigateWhenReady(Future<StartupDestination> pending) async {
    try {
      final destination = await pending;
      if (!mounted || _navigated) return;
      _navigated = true;
      ref.invalidate(startupDestinationProvider);
      context.go(destination.location);
    } catch (error) {
      if (!mounted || _navigated) return;
      setState(() {
        _completing = false;
        _error = error.toString();
        // A settled failure can never succeed, so drop it and let the next
        // Skip or Try again press start a fresh attempt.
        _resolution = null;
      });
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fade = CurvedAnimation(parent: _animation, curve: Curves.easeOut);
    final scale = Tween<double>(
      begin: 0.72,
      end: 1,
    ).animate(CurvedAnimation(parent: _animation, curve: Curves.elasticOut));
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 18,
              child: TextButton(
                onPressed: _completing ? null : _complete,
                child: const Text('Skip'),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: FadeTransition(
                  opacity: fade,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: scale,
                        child: Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            color: palette.navBar,
                            borderRadius: BorderRadius.circular(42),
                            boxShadow: [
                              BoxShadow(
                                color: palette.navBar.withValues(alpha: 0.16),
                                blurRadius: 34,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: palette.onNavBar,
                            size: 62,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'music hub',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your sound. Your people. Your moment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 34),
                      if (_completing)
                        const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _complete,
                          child: const Text('Try again'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
