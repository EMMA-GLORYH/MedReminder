// lib/services/auth_router.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ✅ FIXED: Normalized package path imports to solve Windows path-case duplicates
import 'package:mar/auth/login_screen.dart';
import 'package:mar/auth/onboarding_screen.dart';
import 'package:mar/home/patient_home_screen.dart';
import 'package:mar/home/caretaker_home_screen.dart';
import 'package:mar/services/auth_service.dart';

class AuthRouter {
  AuthRouter._();

  /// Returns the correct screen based on user's state
  static Future<Widget> getInitialScreen() async {
    final auth = AuthService.instance;

    debugPrint('🔍 AuthRouter: Checking auth state...');
    debugPrint('🔍 AuthRouter: isLoggedIn = ${auth.isLoggedIn}');

    if (!auth.isLoggedIn) {
      debugPrint('➡️ AuthRouter: Not logged in → LoginScreen');
      return const LoginScreen();
    }

    try {
      debugPrint('🔍 AuthRouter: Fetching profile...');
      final profile = await auth.getCurrentProfile();

      if (profile == null) {
        debugPrint('⚠️ AuthRouter: Profile is NULL → LoginScreen');
        return const LoginScreen();
      }

      debugPrint('✅ AuthRouter: Profile loaded');
      debugPrint('   - Name: ${profile.fullName}');
      debugPrint('   - Role: ${profile.role}');
      debugPrint('   - Onboarding done: ${profile.onboardingCompleted}');

      if (profile.needsOnboarding) {
        debugPrint('➡️ AuthRouter: Needs onboarding → OnboardingScreen');
        return const OnboardingScreen();
      }

      // ✅ FIXED: Safely fallback to an empty string if profile.role is null
      final role = (profile.role ?? '').toLowerCase().trim();

      if (role == 'patient') {
        debugPrint('➡️ AuthRouter: Patient → PatientHomeScreen');
        return const PatientHomeScreen();
      }

      if (role == 'caretaker' || role == 'caregiver' || profile.isCaretaker) {
        debugPrint('➡️ AuthRouter: Caretaker → CaretakerHomeScreen');
        return const CaretakerHomeScreen();
      }

      debugPrint('⚠️ AuthRouter: Unknown role "$role" → OnboardingScreen');
      return const OnboardingScreen();
    } catch (e, stack) {
      debugPrint('❌ AuthRouter ERROR: $e');
      debugPrint('❌ Stack: $stack');
      return const LoginScreen();
    }
  }

  /// Navigate to the correct screen after auth
  /// Throws so caller can show error message
  static Future<void> routeAfterAuth(BuildContext context) async {
    debugPrint('🚀 AuthRouter.routeAfterAuth: Starting...');

    final destination = await getInitialScreen();

    if (!context.mounted) {
      debugPrint('❌ Context not mounted, cannot navigate');
      return;
    }

    debugPrint('🚀 Navigating to: ${destination.runtimeType}');

    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, animation, __) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
          (route) => false,
    );

    debugPrint('✅ Navigation completed');
  }
}