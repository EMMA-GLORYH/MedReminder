// lib/main.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'gui/splash_screen.dart';
import 'localization/app_localizations.dart';
import 'localization/locale_controller.dart';
import 'services/local_notification_service.dart';
import 'theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════
// ROOT NAVIGATOR
//
// MainActivity and LocalNotificationService use this navigator to open the
// medication reminder screen over splash, login, authenticated screens, or
// the startup error screen.
// ══════════════════════════════════════════════════════════════

final GlobalKey<NavigatorState> navigatorKey =
GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? startupError;
  StackTrace? startupStack;

  // ══════════════════════════════════════════════════════════════
  // LOCALIZATION
  // ══════════════════════════════════════════════════════════════

  try {
    await LocaleController.instance.load();

    debugPrint(
      '✅ Locale ready: '
          '${LocaleController.instance.notifier.value}',
    );
  } catch (error, stack) {
    /*
     * Locale loading is not allowed to prevent medication reminders from
     * opening. LocaleController will retain its default locale.
     */
    debugPrint(
      '⚠️ Could not restore the saved locale: $error',
    );
    debugPrint('$stack');
  }

  // ══════════════════════════════════════════════════════════════
  // NATIVE ALERT AND SCANNER ROUTING
  //
  // This is initialized separately from Supabase so that receiving and
  // displaying an already-scheduled medication reminder does not depend
  // on the user being logged in or the backend initializing successfully.
  // ══════════════════════════════════════════════════════════════

  try {
    await LocalNotificationService.instance.init();

    debugPrint(
      '✅ Local notifications and scanner routing ready',
    );
  } catch (error, stack) {
    /*
     * Do not prevent the rest of the app from starting. Native alarms can
     * still make sound, vibrate and flash even if Flutter notification
     * initialization encounters an error.
     */
    debugPrint(
      '⚠️ Local notification initialization failed: $error',
    );
    debugPrint('$stack');
  }

  // ══════════════════════════════════════════════════════════════
  // SUPABASE
  //
  // Supabase is required for the normal authenticated application flow,
  // but it is not required to reconstruct a medication screen from the
  // locally cached alarm payload.
  // ══════════════════════════════════════════════════════════════

  try {
    await SupabaseConfig.loadEnv();

    debugPrint(
      '✅ Environment configuration loaded',
    );

    if (SupabaseConfig.url.trim().isEmpty ||
        SupabaseConfig.anonKey.trim().isEmpty) {
      throw StateError(
        'Supabase credentials are empty. Check the .env file.',
      );
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );

    debugPrint(
      '✅ Supabase ready',
    );
  } catch (error, stack) {
    startupError = error;
    startupStack = stack;

    debugPrint(
      '❌ Supabase initialization failed: $error',
    );
    debugPrint('$stack');
  }

  /*
   * MaterialApp is always created, even when backend initialization fails.
   * This guarantees that navigatorKey.currentState can become available
   * for a queued medication reminder payload.
   */
  runApp(
    MyApp(
      startupError: startupError,
      startupStack: startupStack,
    ),
  );
}

// Access this only after Supabase initialization succeeds.
SupabaseClient get supabase => Supabase.instance.client;

// ══════════════════════════════════════════════════════════════
// ROOT APPLICATION
// ══════════════════════════════════════════════════════════════

class MyApp extends StatelessWidget {
  final Object? startupError;
  final StackTrace? startupStack;

  const MyApp({
    super.key,
    this.startupError,
    this.startupStack,
  });

  @override
  Widget build(BuildContext context) {
    /*
     * Rebuild the application when the user changes languages.
     *
     * The same global navigatorKey is retained across locale rebuilds, so
     * native medication reminder routing continues to target the root
     * navigator.
     */
    return ValueListenableBuilder<Locale>(
      valueListenable:
      LocaleController.instance.notifier,
      builder: (
          BuildContext context,
          Locale locale,
          Widget? child,
          ) {
        return MaterialApp(
          title: 'MedReminder',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,

          // Required by LocalNotificationService.
          navigatorKey: navigatorKey,

          /*
           * If Supabase failed, keep a valid root navigator and show an
           * error screen. A cached medication reminder can still be pushed
           * over this screen without authentication.
           */
          home: startupError == null
              ? const SplashScreen()
              : _StartupErrorScreen(
            error: startupError!,
            stackTrace: startupStack,
          ),

          locale: locale,
          supportedLocales:
          AppLocalizations.supportedLocales,
          localizationsDelegates: const <
              LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STARTUP ERROR SCREEN
//
// This screen deliberately stays inside the same root MaterialApp and
// navigator. Therefore, medication alarms can still open their reminder
// screen even when the normal authenticated application cannot start.
// ══════════════════════════════════════════════════════════════

class _StartupErrorScreen extends StatelessWidget {
  final Object error;
  final StackTrace? stackTrace;

  const _StartupErrorScreen({
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 520,
              ),
              child: Column(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(
                        alpha: 0.10,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: Colors.redAccent,
                      size: 38,
                    ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  const Text(
                    'The app could not finish starting',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  const Text(
                    'Medication alarms that were already scheduled '
                        'can still alert you. Please check your connection '
                        'or application configuration, then restart the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF7F1D1D),
                        fontSize: 13,
                      ),
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