// lib/gui/splash_screen.dart

import 'package:flutter/material.dart';

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
  State<SplashScreen> createState() =>
      _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _routingStarted = false;

  @override
  void initState() {
    super.initState();

    /*
     * Schedule initialization after the first frame so this screen already
     * has a ModalRoute and is attached to the root navigator.
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _init();
      }
    });
  }

  Future<void> _init() async {
    if (_routingStarted) {
      return;
    }

    _routingStarted = true;

    if (widget.showBranding) {
      await Future<void>.delayed(
        const Duration(milliseconds: 1500),
      );
    }

    if (!mounted) {
      return;
    }

    /*
     * A medication alarm may have pushed
     * MedicationReminderScannerScreen above this splash screen.
     *
     * Calling AuthRouter while the splash route is not current could cause
     * pushReplacement or another navigator operation to replace the active
     * medication reminder. Wait until this splash route becomes current
     * again, which happens after the reminder screen is closed.
     */
    await _waitUntilSplashIsCurrent();

    if (!mounted) {
      return;
    }

    /*
     * Wait one additional frame and verify again. This reduces the chance
     * of racing with a scanner route that is being pushed by the native
     * alarm during application startup.
     */
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) {
      return;
    }

    final route = ModalRoute.of(context);

    if (route?.isCurrent != true) {
      _routingStarted = false;
      await _init();
      return;
    }

    try {
      await AuthRouter.routeAfterAuth(context);
    } catch (error, stack) {
      debugPrint(
        '❌ Authentication routing failed: $error',
      );
      debugPrint('$stack');

      /*
       * Allow another routing attempt if this screen is rebuilt or if the
       * application invokes initialization again.
       */
      _routingStarted = false;
    }
  }

  Future<void> _waitUntilSplashIsCurrent() async {
    while (mounted) {
      final route = ModalRoute.of(context);

      if (route?.isCurrent == true) {
        return;
      }

      /*
       * The medication reminder is currently above the splash screen, or
       * the splash route has not been attached yet. Do not perform login
       * routing until it becomes safe.
       */
      await Future<void>.delayed(
        const Duration(milliseconds: 250),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showBranding) {
      return const Scaffold(
        backgroundColor: AppColors.background,
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

    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
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
            const SizedBox(
              height: 24,
            ),
            Text(
              'MedReminder',
              style: AppTextStyles.displayLarge.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Your health, on schedule',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(
              height: 40,
            ),
            const CircularProgressIndicator(
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}