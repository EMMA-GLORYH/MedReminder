// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/firebase_config.dart';
import 'config/supabase_config.dart';
import 'gui/splash_screen.dart';
import 'services/local_notification_service.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: FirebaseConfig.currentPlatform);
  debugPrint('📨 [BG] ${message.notification?.title}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseConfig.loadEnv();
    debugPrint('✅ Env loaded');

    await Firebase.initializeApp(options: FirebaseConfig.currentPlatform);
    debugPrint('✅ Firebase ready');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await Supabase.initialize(
      url:     SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    debugPrint('✅ Supabase ready');

    // ✅ NEW: Initialize local notifications
    await LocalNotificationService.instance.init();
    debugPrint('✅ Local notifications ready');

    runApp(const MyApp());
  } catch (e, stack) {
    debugPrint('❌ Init error: $e\n$stack');
    runApp(MaterialApp(
      home: Scaffold(body: Center(child: Text('Error: $e'))),
    ));
  }

  // ✅ ADD THIS DEBUG CHECK
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
      home: const SplashScreen(),
    );
  }
}