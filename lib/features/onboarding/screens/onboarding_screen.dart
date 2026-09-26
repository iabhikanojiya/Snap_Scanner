import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_prefs_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/screens/home_screen.dart';

/// Three-step welcome shown only on first launch: full-screen photo per
/// step with the copy on the photo's dark lower area.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _pages = [
    _OnboardingPageData(
      image: 'assets/images/onboarding/onboarding_scan.jpg',
      title: 'Scan Documents Easily',
      description: 'Turn your paper documents into clear, organized PDFs in seconds.',
    ),
    _OnboardingPageData(
      image: 'assets/images/onboarding/onboarding_sign.jpg',
      title: 'Sign PDFs with Ease',
      description: 'Add your signature to documents and keep everything ready to share.',
    ),
    _OnboardingPageData(
      image: 'assets/images/onboarding/onboarding_features.jpg',
      title: 'And So Much More',
      description: 'Merge, split, compress, lock and convert your files. All your PDF tools in one place.',
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode every step up front so swiping never shows a blank frame.
    for (final page in _pages) {
      precacheImage(AssetImage(page.image), context);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await AppPrefsService.setOnboardingCompleted();
    if (!mounted) return;
    // Replace so HomeScreen becomes the first route (other flows rely on
    // popUntil(route.isFirst) to return home).
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Photo + copy swipe together.
            PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => _OnboardingPage(data: _pages[index]),
            ),

            // Skip (hidden on the last step).
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
                  child: AnimatedOpacity(
                    opacity: _isLast ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _isLast ? null : _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.25),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ),

            // Dots + CTA stay fixed at the bottom.
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _pages.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _page ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? AppColors.brandRed
                                    : Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandRed,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_isLast ? 'Get Started' : 'Next'),
                              if (!_isLast) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, size: 20),
                              ],
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
    );
  }
}

class _OnboardingPageData {
  final String image;
  final String title;
  final String description;

  const _OnboardingPageData({
    required this.image,
    required this.title,
    required this.description,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  /// Space reserved at the bottom for the fixed dots + CTA.
  static const double _controlsHeight = 8 + 22 + 54 + 20;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          data.image,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          gaplessPlayback: true,
        ),
        // Extra shade so the copy stays readable on every phone height.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.45, 0.72, 1],
              colors: [Colors.transparent, Color(0xB3000000), Color(0xF2000000)],
            ),
          ),
        ),
        Positioned(
          left: 28,
          right: 28,
          bottom: bottomInset + _controlsHeight + 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
