// lib/services/medication_tts_service.dart
//
// No changes needed here for this round — included for reference only.
// The TTS-x3-then-alarm-tone logic lives natively in TtsSpeakService.kt
// (from the previous turn); this Dart-side channel wrapper is unaffected
// by localization, the schedule-button removal, or the scanner-screen
// image update.

import 'package:flutter/services.dart';

class MedicationTtsService {
  MedicationTtsService._();
  static final MedicationTtsService instance = MedicationTtsService._();

  static const MethodChannel _channel = MethodChannel('medication_tts_background');

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> speakUntilStopped({required String message}) async {
    try {
      await _channel.invokeMethod('start', {'message': message});
    } catch (_) {}
  }

  /// Schedules a native AlarmManager alarm that fires even if the app has
  /// been killed. When it fires it starts a foreground service that wakes
  /// the screen, shows over the lock screen, speaks [message] on repeat,
  /// and auto-opens the scanner screen using [payload] — no notification
  /// tap required.
  Future<void> scheduleAutoOpen({
    required int alarmId,
    required DateTime startAt,
    required String message,
    required String payload,
  }) async {
    try {
      await _channel.invokeMethod('scheduleStart', {
        'alarmId': alarmId,
        'startAtMillis': startAt.millisecondsSinceEpoch,
        'message': message,
        'payload': payload,
      });
    } catch (_) {}
  }

  Future<void> cancelAutoOpen(int alarmId) async {
    try {
      await _channel.invokeMethod('cancelAlarm', {'alarmId': alarmId});
    } catch (_) {}
  }
}