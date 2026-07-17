// lib/services/auth_router.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mar/auth/login_screen.dart';
import 'package:mar/auth/onboarding_screen.dart';
import 'package:mar/home/caretaker_home_screen.dart';
import 'package:mar/home/patient_home_screen.dart';
import 'package:mar/services/auth_service.dart';

class AuthRouter {
  AuthRouter._();

  // ══════════════════════════════════════════════════════════════
  // DETERMINE INITIAL SCREEN
  // ══════════════════════════════════════════════════════════════

  /// Returns the correct screen for the current authentication,
  /// onboarding, and user-role state.
  static Future<Widget> getInitialScreen() async {
    final auth = AuthService.instance;

    debugPrint(
      '🔍 AuthRouter: Checking authentication state...',
    );
    debugPrint(
      '🔍 AuthRouter: isLoggedIn = ${auth.isLoggedIn}',
    );

    if (!auth.isLoggedIn) {
      debugPrint(
        '➡️ AuthRouter: Not logged in → LoginScreen',
      );

      return const LoginScreen();
    }

    try {
      debugPrint(
        '🔍 AuthRouter: Fetching current profile...',
      );

      final profile = await auth.getCurrentProfile();

      if (profile == null) {
        debugPrint(
          '⚠️ AuthRouter: Profile is null → LoginScreen',
        );

        return const LoginScreen();
      }

      debugPrint(
        '✅ AuthRouter: Profile loaded',
      );
      debugPrint(
        '   - Name: ${profile.fullName}',
      );
      debugPrint(
        '   - Role: ${profile.role}',
      );
      debugPrint(
        '   - Onboarding completed: '
            '${profile.onboardingCompleted}',
      );

      if (profile.needsOnboarding) {
        debugPrint(
          '➡️ AuthRouter: Needs onboarding → '
              'OnboardingScreen',
        );

        return const OnboardingScreen();
      }

      final role =
      (profile.role ?? '').toLowerCase().trim();

      if (role == 'patient') {
        debugPrint(
          '➡️ AuthRouter: Patient → PatientHomeScreen',
        );

        return const PatientHomeScreen();
      }

      if (role == 'caretaker' ||
          role == 'caregiver' ||
          profile.isCaretaker) {
        debugPrint(
          '➡️ AuthRouter: Caretaker → '
              'CaretakerHomeScreen',
        );

        return const CaretakerHomeScreen();
      }

      debugPrint(
        '⚠️ AuthRouter: Unknown role "$role" → '
            'OnboardingScreen',
      );

      return const OnboardingScreen();
    } catch (error, stack) {
      debugPrint(
        '❌ AuthRouter profile lookup failed: $error',
      );
      debugPrint('$stack');

      /*
       * Authentication or network errors must not prevent the app from
       * presenting a valid screen. The user can retry from LoginScreen.
       */
      return const LoginScreen();
    }
  }

  // ══════════════════════════════════════════════════════════════
  // NAVIGATE AFTER AUTHENTICATION CHECK
  // ══════════════════════════════════════════════════════════════

  /// Navigates to the appropriate authentication destination.
  ///
  /// This method only navigates when the route that requested the
  /// authentication check is still the current route.
  ///
  /// If a medication reminder opens while the asynchronous profile lookup
  /// is running, this method returns without changing the navigator. This
  /// protects MedicationReminderScannerScreen from being removed by
  /// pushAndRemoveUntil().
  static Future<void> routeAfterAuth(
      BuildContext context,
      ) async {
    debugPrint(
      '🚀 AuthRouter.routeAfterAuth: Starting...',
    );

    if (!context.mounted) {
      debugPrint(
        '⚠️ AuthRouter: Context is not mounted',
      );
      return;
    }

    /*
     * Capture the route that initiated authentication routing. Usually this
     * is SplashScreen, but the method remains safe if called from another
     * route.
     */
    final sourceRoute = ModalRoute.of(context);

    if (sourceRoute == null) {
      debugPrint(
        '⚠️ AuthRouter: Calling context has no ModalRoute',
      );
      return;
    }

    /*
     * Do not begin routing from a screen that is already covered by the
     * medication reminder or another route.
     */
    if (!sourceRoute.isCurrent) {
      debugPrint(
        '⏸️ AuthRouter: Source route is not current; '
            'navigation postponed',
      );
      return;
    }

    final destination = await getInitialScreen();

    if (!context.mounted) {
      debugPrint(
        '⚠️ AuthRouter: Context was disposed while '
            'checking authentication',
      );
      return;
    }

    /*
     * This is the critical alarm-screen protection.
     *
     * During getInitialScreen(), a native alarm can push the medication
     * reminder above splash or login. If that happens, sourceRoute is no
     * longer current and authentication navigation must not run.
     */
    if (!sourceRoute.isCurrent) {
      debugPrint(
        '⏸️ AuthRouter: A different route opened during '
            'authentication lookup. Navigation cancelled.',
      );
      return;
    }

    /*
     * Confirm that the context still belongs to the same source route.
     * This protects against the widget being moved or rebuilt under a
     * different navigator.
     */
    final currentContextRoute = ModalRoute.of(context);

    if (!identical(currentContextRoute, sourceRoute)) {
      debugPrint(
        '⏸️ AuthRouter: Source route changed before '
            'navigation. Navigation cancelled.',
      );
      return;
    }

    final navigator = Navigator.of(context);

    if (!navigator.mounted) {
      debugPrint(
        '⚠️ AuthRouter: Navigator is not mounted',
      );
      return;
    }

    debugPrint(
      '🚀 AuthRouter: Navigating to '
          '${destination.runtimeType}',
    );

    /*
     * No await occurs between the final isCurrent check and this navigator
     * operation. Therefore, another Dart route cannot be pushed between
     * the safety check and pushAndRemoveUntil().
     */
    navigator.pushAndRemoveUntil<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(
          milliseconds: 300,
        ),
        reverseTransitionDuration: const Duration(
          milliseconds: 200,
        ),
        pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            ) {
          return destination;
        },
        transitionsBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
            ) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
          (Route<dynamic> route) => false,
    );

    debugPrint(
      '✅ AuthRouter: Navigation requested',
    );
  }
}