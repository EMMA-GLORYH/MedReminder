// lib/screens/gui/splash_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SplashScreen extends StatefulWidget {
  final bool showBranding;

  const SplashScreen({super.key, this.showBranding = true});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.showBranding) {
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    if (!mounted) return;
    await AuthRouter.routeAfterAuth(context);
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
          children: [
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
            const SizedBox(height: 24),
            Text(
              'MedReminder',
              style: AppTextStyles.displayLarge.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Your health, on schedule',
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}