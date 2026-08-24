import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_hub_app/app/theme.dart';
import 'package:music_hub_app/features/auth/presentation/auth_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error.toString())));
      }
    });
    return Scaffold(
      body: CustomPaint(
        painter: _ContourPainter(),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        _BrandMark(),
                        SizedBox(width: 10),
                        Text(
                          'music hub',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(
                      height: 290,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 4,
                            right: 26,
                            child: _MusicBlob(
                              size: 126,
                              color: AppTheme.blue,
                              icon: Icons.headphones_rounded,
                              rotation: 0.16,
                            ),
                          ),
                          Positioned(
                            left: -14,
                            top: 88,
                            child: _MusicBlob(
                              size: 154,
                              color: AppTheme.peach,
                              icon: Icons.album_rounded,
                              rotation: -0.12,
                            ),
                          ),
                          Positioned(
                            right: 4,
                            bottom: 0,
                            child: _MusicBlob(
                              size: 162,
                              color: AppTheme.lilac,
                              icon: Icons.graphic_eq_rounded,
                              rotation: 0.08,
                            ),
                          ),
                          Positioned(
                            left: 137,
                            top: 92,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppTheme.accent,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Icon(Icons.play_arrow_rounded, size: 34),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Elevate ',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(fontSize: 46),
                          ),
                          TextSpan(
                            text: 'every\nmoment ',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontSize: 46,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                          TextSpan(
                            text: 'with music',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(fontSize: 46),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Your languages, favorite artists, and a soundtrack that becomes more personal every day.',
                      style: TextStyle(
                        color: AppTheme.muted,
                        height: 1.45,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => ref
                                .read(authControllerProvider.notifier)
                                .signIn(),
                      icon: state.isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.g_mobiledata_rounded, size: 26),
                      label: Text(
                        state.isLoading
                            ? 'Connecting…'
                            : 'Continue with Google',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                      ),
                    ),
                    const SizedBox(height: 13),
                    const Center(
                      child: Text(
                        'Secure sign-in powered by Firebase',
                        style: TextStyle(color: AppTheme.muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: AppTheme.ink,
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 21),
  );
}

class _MusicBlob extends StatelessWidget {
  const _MusicBlob({
    required this.size,
    required this.color,
    required this.icon,
    required this.rotation,
  });

  final double size;
  final Color color;
  final IconData icon;
  final double rotation;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: rotation,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppTheme.ink, width: 1.2),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(62),
          topRight: Radius.circular(34),
          bottomLeft: Radius.circular(38),
          bottomRight: Radius.circular(72),
        ),
      ),
      child: Icon(icon, size: size * 0.42),
    ),
  );
}

class _ContourPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.ink.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final inset = i * 26.0;
      final path = Path()
        ..moveTo(size.width * 0.48, -20 + inset)
        ..cubicTo(
          size.width * 0.72,
          size.height * 0.12 + inset,
          size.width * 0.28,
          size.height * 0.19 + inset,
          size.width + 30,
          size.height * 0.30 + inset,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
