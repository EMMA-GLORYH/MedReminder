// lib/main.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'gui/splash_screen.dart';
import 'services/local_notification_service.dart';
import 'theme/app_theme.dart';

// Global navigator key - Used to open full-screen scanner from notifications and background handlers
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseConfig.loadEnv();
    debugPrint('✅ Env loaded');

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    debugPrint('✅ Supabase ready');

    await LocalNotificationService.instance.init();
    debugPrint('✅ Local notifications ready');

    runApp(const MyApp());
  } catch (e, stack) {
    debugPrint('❌ Init error: $e\n$stack');

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error: $e',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  debugPrint('🔵 Supabase URL: ${SupabaseConfig.url}');
  debugPrint('🔵 Supabase Key length: ${SupabaseConfig.anonKey.length}');

  if (SupabaseConfig.url.isEmpty || SupabaseConfig.anonKey.isEmpty) {
    debugPrint('❌❌❌ SUPABASE CREDENTIALS ARE EMPTY - CHECK .env FILE');
  }
}

SupabaseClient get supabase => Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedReminder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: navigatorKey,           // ← Required for scanner screen
      home: const SplashScreen(),
    );
  }
}