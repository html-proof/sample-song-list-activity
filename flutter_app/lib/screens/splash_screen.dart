import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _buildArtistCollage(size),
          _buildGradientOverlay(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Music Hub',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _navigate(context),
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                fontSize: 38,
                                height: 1.1,
                                color: AppColors.primary,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Elevate\nEvery\nMoment With ',
                                  style: TextStyle(fontWeight: FontWeight.w400),
                                ),
                                TextSpan(
                                  text: 'Music',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Immerse yourself in a world where every beat enhances your mood and every melody tells your story.',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.secondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _navigate(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Get Started',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.secondary,
                                ),
                                children: [
                                  const TextSpan(text: 'Already have an account? '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => _navigate(context),
                                      child: const Text(
                                        'Log In',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context) {
    Navigator.pushReplacementNamed(context, '/preferences');
  }

  Widget _buildArtistCollage(Size size) {
    return SizedBox(
      height: size.height * 0.62,
      width: size.width,
      child: Stack(
        children: [
          _blobImage(
            'https://picsum.photos/seed/splash1/400/500',
            left: -30,
            top: 60,
            width: 200,
            height: 240,
            rotation: -0.15,
          ),
          _blobImage(
            'https://picsum.photos/seed/splash2/300/380',
            right: -20,
            top: 20,
            width: 180,
            height: 220,
            rotation: 0.1,
            greyscale: true,
          ),
          _blobImage(
            'https://picsum.photos/seed/splash3/350/420',
            left: size.width * 0.28,
            top: 100,
            width: 160,
            height: 200,
            rotation: 0.05,
          ),
          _blobImage(
            'https://picsum.photos/seed/splash4/300/300',
            left: 20,
            top: size.height * 0.28,
            width: 120,
            height: 130,
            rotation: -0.08,
            greyscale: true,
          ),
        ],
      ),
    );
  }

  Widget _blobImage(
    String url, {
    double? left,
    double? right,
    double? top,
    double? bottom,
    required double width,
    required double height,
    double rotation = 0,
    bool greyscale = false,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Transform.rotate(
        angle: rotation,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: ColorFiltered(
            colorFilter: greyscale
                ? const ColorFilter.matrix([
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0, 0, 0, 1, 0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.color),
            child: Image.network(
              url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: width,
                height: height,
                color: AppColors.surfaceCard,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.of(context).size.height * 0.35,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background.withValues(alpha: 0),
              AppColors.background.withValues(alpha: 0.85),
              AppColors.background,
            ],
            stops: const [0, 0.4, 0.7],
          ),
        ),
      ),
    );
  }
}
