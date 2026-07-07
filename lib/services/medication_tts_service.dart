// lib/services/medication_tts_service.dart
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

  // Used by the “fallback” (tap notification) if needed.
  Future<void> speakUntilStopped({
    required String message,
  }) async {
    try {
      await _channel.invokeMethod('start', {'message': message});
    } catch (_) {}
  }
}