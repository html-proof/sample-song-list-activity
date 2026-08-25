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
  late final AnimationController _animation;
  bool _completing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..forward();
    unawaited(_finishAfterAnimation());
  }

  Future<void> _finishAfterAnimation() async {
    await Future<void>.delayed(const Duration(milliseconds: 1650));
    if (mounted) await _complete();
  }

  Future<void> _complete() async {
    if (_completing) return;
    setState(() {
      _completing = true;
      _error = null;
    });
    try {
      final destination = await ref
          .read(startupControllerProvider)
          .completeSplash();
      ref.invalidate(startupDestinationProvider);
      if (mounted) context.go(destination.location);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _error = error.toString();
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
    final fade = CurvedAnimation(parent: _animation, curve: Curves.easeOut);
    final scale = Tween<double>(
      begin: 0.72,
      end: 1,
    ).animate(CurvedAnimation(parent: _animation, curve: Curves.elasticOut));
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                            color: context.colors.primary,
                            borderRadius: BorderRadius.circular(42),
                            boxShadow: [
                              BoxShadow(
                                color: context.colors.shadow.withValues(
                                  alpha: 0.16,
                                ),
                                blurRadius: 34,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: context.colors.onPrimary,
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
                          color: context.secondaryText,
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
                          style: const TextStyle(color: Color(0xFFB3261E)),
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
