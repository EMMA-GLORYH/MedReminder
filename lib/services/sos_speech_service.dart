// lib/services/sos_speech_service.dart

import 'package:flutter/foundation.dart';
import 'package:mar/services/medication_tts_service.dart';

class SosSpeechService {
  SosSpeechService._();

  static final SosSpeechService instance = SosSpeechService._();

  bool _isStarting = false;

  /// Announces a newly received emergency SOS on the caretaker's device.
  ///
  /// Native behavior:
  /// 1. Speaks the emergency message three times.
  /// 2. Uses the Android alarm audio stream.
  /// 3. Starts continuous vibration.
  /// 4. Plays caretaker_sos.mp3 continuously after TTS.
  /// 5. Continues until [stop] is called.
  Future<void> announceEmergency({
    required String patientName,
  }) async {
    if (_isStarting) {
      debugPrint(
        'ℹ️ Another caretaker SOS announcement is already starting',
      );
      return;
    }

    _isStarting = true;

    final safeName = patientName.trim().isEmpty
        ? 'A patient'
        : patientName.trim();

    try {
      await MedicationTtsService.instance.startCaretakerSosAlert(
        patientName: safeName,
      );

      debugPrint(
        '🔊 Caretaker SOS announcement started for $safeName',
      );
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to start caretaker SOS announcement: $error',
      );
      debugPrint('$stack');
    } finally {
      _isStarting = false;
    }
  }

  /// Starts a caretaker SOS alert using a fully customized message.
  Future<void> announceCustomEmergency({
    required String message,
  }) async {
    final safeMessage = message.trim();

    if (safeMessage.isEmpty) {
      debugPrint(
        '⚠️ Caretaker SOS message was empty',
      );
      return;
    }

    if (_isStarting) return;

    _isStarting = true;

    try {
      await MedicationTtsService.instance.startCaretakerSosMessage(
        message: safeMessage,
      );

      debugPrint(
        '🔊 Custom caretaker SOS announcement started',
      );
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to start custom caretaker SOS: $error',
      );
      debugPrint('$stack');
    } finally {
      _isStarting = false;
    }
  }

  /// Stops caretaker SOS speech, looping MP3, vibration,
  /// and the native foreground alert service.
  Future<void> stop() async {
    try {
      await MedicationTtsService.instance.stop();

      debugPrint(
        '🔇 Caretaker SOS announcement stopped',
      );
    } catch (error, stack) {
      debugPrint(
        '⚠️ Failed to stop caretaker SOS announcement: $error',
      );
      debugPrint('$stack');
    }
  }
}