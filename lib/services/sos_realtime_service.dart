// lib/services/sos_realtime_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SosRealtimeNativeService {
  SosRealtimeNativeService._();

  static final SosRealtimeNativeService instance =
  SosRealtimeNativeService._();

  static const MethodChannel _channel =
  MethodChannel('sos_realtime_background');

  bool _started = false;

  /// Starts the native background WebSocket that listens for SOS alerts.
  ///
  /// [caregiverId] is the logged‑in caretaker's user id. The native service
  /// uses it as the Realtime filter so only this caretaker's alerts arrive.
  Future<void> startForCurrentCaretaker({
    required String caregiverId,
  }) async {
    if (caregiverId.isEmpty) return;

    // ✅ Use SupabaseConfig (from .env) — these are guaranteed to exist
    // because main.dart loads the env before the app starts.
    final url = SupabaseConfig.url;
    final anonKey = SupabaseConfig.anonKey;

    // The user's session JWT is required so Row Level Security returns
    // this caretaker's rows over the socket.
    final accessToken = Supabase.instance
        .client
        .auth
        .currentSession
        ?.accessToken ??
        '';

    if (url.isEmpty || anonKey.isEmpty) {
      debugPrint(
        '⚠️ SosRealtimeNativeService: missing Supabase config',
      );
      return;
    }

    if (accessToken.isEmpty) {
      debugPrint(
        '⚠️ SosRealtimeNativeService: no session token yet',
      );
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'startSosRealtime',
        <String, String>{
          'caregiverId': caregiverId,
          'supabaseUrl': url,
          'supabaseAnonKey': anonKey,
          'accessToken': accessToken,
        },
      );

      _started = true;

      debugPrint(
        '✅ Native SOS realtime started for $caregiverId',
      );
    } catch (e) {
      debugPrint(
        '⚠️ Could not start native SOS realtime: $e',
      );
    }
  }

  /// Stops the native background WebSocket.
  Future<void> stop() async {
    if (!_started) return;

    try {
      await _channel.invokeMethod<void>('stopSosRealtime');
      _started = false;
      debugPrint('🔇 Native SOS realtime stopped');
    } catch (e) {
      debugPrint('⚠️ Could not stop native SOS realtime: $e');
    }
  }
}