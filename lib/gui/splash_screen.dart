// lib/gui/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/auth_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SplashScreen extends StatefulWidget {
  final bool showBranding;

  const SplashScreen({
    super.key,
    this.showBranding = true,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _routingStarted = false;

  // ── Fade-in animation for the logo and text ──
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );

    _animController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _init();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_routingStarted) return;

    _routingStarted = true;

    if (widget.showBranding) {
      await Future<void>.delayed(const Duration(milliseconds: 2000));
    }

    if (!mounted) return;

    await _waitUntilSplashIsCurrent();

    if (!mounted) return;

    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return;

    final route = ModalRoute.of(context);

    if (route?.isCurrent != true) {
      _routingStarted = false;
      await _init();
      return;
    }

    try {
      await AuthRouter.routeAfterAuth(context);
    } catch (error, stack) {
      debugPrint('❌ Authentication routing failed: $error');
      debugPrint('$stack');
      _routingStarted = false;
    }
  }

  Future<void> _waitUntilSplashIsCurrent() async {
    while (mounted) {
      final route = ModalRoute.of(context);
      if (route?.isCurrent == true) return;

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── No-branding fallback (loading only) ──────────────────
    if (!widget.showBranding) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    // ── Full branding splash ─────────────────────────────────
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // ── SVG Logo ─────────────────────────────
                  SvgPicture.asset(
                    'assets/images/MedReminder_Logo.svg',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => Container(
                      width: 120,
                      height: 120,
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.medication_rounded,
                        size: 64,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── App name ──────────────────────────────
                  Text(
                    'MedReminder',
                    style: AppTextStyles.displayLarge.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Tagline ───────────────────────────────
                  Text(
                    'Your health, on schedule',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Loading indicator at the bottom ───────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 3,
                            backgroundColor:
                            AppColors.primary.withOpacity(0.15),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading...',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}