// lib/services/medication_tts_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MedicationTtsService {
  MedicationTtsService._();

  static final MedicationTtsService instance =
  MedicationTtsService._();

  static const MethodChannel _channel =
  MethodChannel('medication_tts_background');

  // These values must match MainActivity.kt and TtsSpeakService.kt.
  static const String _modeMedicationDue = 'medication_due';
  static const String _modePriorReminder = 'prior_reminder';
  static const String _modeCaretakerSos = 'caretaker_sos';

  static const String _vibrationContinuous = 'continuous';
  static const String _vibrationFivePulses = 'five_pulses';
  static const String _vibrationNone = 'none';

  static const int _defaultTtsRepeatCount = 3;

  // ══════════════════════════════════════════════════════════════
  // STOP CURRENT TTS, SOUND, VIBRATION, AND FOREGROUND SERVICE
  // ══════════════════════════════════════════════════════════════

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
      debugPrint('🔇 Native alert service stopped');
    } on PlatformException catch (error, stack) {
      debugPrint(
        '⚠️ Could not stop native alert service: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '⚠️ Could not stop native alert service: $error',
      );
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LEGACY METHOD
  //
  // Keep this because existing scanner/reminder code already calls it.
  // Native defaults continue to provide the original medication behavior.
  // ══════════════════════════════════════════════════════════════

  Future<void> speakUntilStopped({
    required String message,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'start',
        {
          'message': message,
        },
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '⚠️ Could not start medication speech: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '⚠️ Could not start medication speech: $error',
      );
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // IMMEDIATE MEDICATION-DUE ALERT
  //
  // Speaks 3 times, then loops alarm.mp3, vibrates continuously,
  // and opens the scanner when a payload is supplied.
  // ══════════════════════════════════════════════════════════════

  Future<void> startMedicationDueAlert({
    required String message,
    String payload = '',
  }) async {
    await _startConfiguredAlert(
      message: message,
      payload: payload,
      alertMode: _modeMedicationDue,
      soundResource: 'alarm',
      loopSound: true,
      launchScanner: payload.trim().isNotEmpty,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // IMMEDIATE PRIOR REMINDER
  //
  // Speaks 3 times, vibrates exactly 5 times, then plays
  // prior_reminder.mp3 once. It does not open the scanner.
  // ══════════════════════════════════════════════════════════════

  Future<void> startPriorReminder({
    required String medicationName,
    required String dosageDisplay,
    int minutesBefore = 10,
  }) async {
    final safeName = medicationName.trim().isEmpty
        ? 'your medication'
        : medicationName.trim();

    final safeDosage = dosageDisplay.trim();

    final message = safeDosage.isEmpty
        ? 'Medication reminder. $safeName is due in '
        '$minutesBefore minutes.'
        : 'Medication reminder. $safeName, dosage '
        '$safeDosage, is due in $minutesBefore minutes.';

    await _startConfiguredAlert(
      message: message,
      alertMode: _modePriorReminder,
      soundResource: 'prior_reminder',
      loopSound: false,
      launchScanner: false,
      vibrationMode: _vibrationFivePulses,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // IMMEDIATE CARETAKER SOS
  //
  // Speaks "Urgent! Urgent!" with the patient's name 3 times,
  // then loops caretaker_sos.mp3 and vibrates continuously.
  // It does not open the medication scanner.
  // ══════════════════════════════════════════════════════════════

  Future<void> startCaretakerSosAlert({
    required String patientName,
  }) async {
    final safeName = patientName.trim().isEmpty
        ? 'A patient'
        : patientName.trim();

    final message =
        'Urgent! Urgent! $safeName has sent an emergency SOS. '
        'Please respond immediately.';

    await _startConfiguredAlert(
      message: message,
      alertMode: _modeCaretakerSos,
      soundResource: 'caretaker_sos',
      loopSound: true,
      launchScanner: false,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  /// Allows an already translated or customized SOS message.
  Future<void> startCaretakerSosMessage({
    required String message,
  }) async {
    await _startConfiguredAlert(
      message: message,
      alertMode: _modeCaretakerSos,
      soundResource: 'caretaker_sos',
      loopSound: true,
      launchScanner: false,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE EXACT MEDICATION-DUE ALERT
  //
  // Backward-compatible replacement for the existing scheduleAutoOpen.
  // ══════════════════════════════════════════════════════════════

  Future<void> scheduleAutoOpen({
    required int alarmId,
    required DateTime startAt,
    required String message,
    required String payload,
  }) async {
    await _scheduleConfiguredAlert(
      alarmId: alarmId,
      startAt: startAt,
      message: message,
      payload: payload,
      alertMode: _modeMedicationDue,
      soundResource: 'alarm',
      loopSound: true,
      launchScanner: payload.trim().isNotEmpty,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE TEN-MINUTE PRIOR REMINDER
  //
  // The caller should pass the actual prior DateTime, normally:
  // scheduledFor.subtract(const Duration(minutes: 10)).
  // ══════════════════════════════════════════════════════════════

  Future<void> schedulePriorReminder({
    required int alarmId,
    required DateTime startAt,
    required String medicationName,
    required String dosageDisplay,
    int minutesBefore = 10,
  }) async {
    if (!startAt.isAfter(DateTime.now())) {
      debugPrint(
        'ℹ️ Prior reminder skipped because its time has passed: '
            '$startAt',
      );
      return;
    }

    final safeName = medicationName.trim().isEmpty
        ? 'your medication'
        : medicationName.trim();

    final safeDosage = dosageDisplay.trim();

    final message = safeDosage.isEmpty
        ? 'Medication reminder. $safeName is due in '
        '$minutesBefore minutes.'
        : 'Medication reminder. $safeName, dosage '
        '$safeDosage, is due in $minutesBefore minutes.';

    await _scheduleConfiguredAlert(
      alarmId: alarmId,
      startAt: startAt,
      message: message,
      payload: '',
      alertMode: _modePriorReminder,
      soundResource: 'prior_reminder',
      loopSound: false,
      launchScanner: false,
      vibrationMode: _vibrationFivePulses,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // OPTIONAL GENERIC IMMEDIATE NATIVE ALERT
  // ══════════════════════════════════════════════════════════════

  Future<void> startCustomAlert({
    required String message,
    required String alertMode,
    required String soundResource,
    required bool loopSound,
    required bool launchScanner,
    required String vibrationMode,
    String payload = '',
    int ttsRepeatCount = _defaultTtsRepeatCount,
  }) async {
    await _startConfiguredAlert(
      message: message,
      payload: payload,
      alertMode: alertMode,
      soundResource: soundResource,
      loopSound: loopSound,
      launchScanner: launchScanner,
      vibrationMode: vibrationMode,
      ttsRepeatCount: ttsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL SCHEDULED NATIVE ALARM
  // ══════════════════════════════════════════════════════════════

  Future<void> cancelAutoOpen(int alarmId) async {
    try {
      await _channel.invokeMethod<void>(
        'cancelAlarm',
        {
          'alarmId': alarmId,
        },
      );

      debugPrint(
        '🗑️ Native alert alarm cancelled: $alarmId',
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '⚠️ Could not cancel native alert alarm $alarmId: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '⚠️ Could not cancel native alert alarm $alarmId: '
            '$error',
      );
      debugPrint('$stack');
    }
  }

  /// Descriptive alias for prior-reminder cancellation.
  Future<void> cancelPriorReminder(int alarmId) {
    return cancelAutoOpen(alarmId);
  }

  // ══════════════════════════════════════════════════════════════
  // PRIVATE METHOD-CHANNEL HELPERS
  // ══════════════════════════════════════════════════════════════

  Future<void> _startConfiguredAlert({
    required String message,
    required String alertMode,
    required String soundResource,
    required bool loopSound,
    required bool launchScanner,
    required String vibrationMode,
    String payload = '',
    int ttsRepeatCount = _defaultTtsRepeatCount,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'start',
        {
          'message': message,
          'payload': payload,
          'alertMode': alertMode,
          'soundResource': soundResource,
          'loopSound': loopSound,
          'launchScanner': launchScanner,
          'vibrationMode': vibrationMode,
          'ttsRepeatCount': ttsRepeatCount.clamp(0, 10),
        },
      );

      debugPrint(
        '🔊 Native alert started: '
            'mode=$alertMode, '
            'sound=$soundResource, '
            'loop=$loopSound, '
            'vibration=$vibrationMode, '
            'tts=$ttsRepeatCount',
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '❌ Could not start native $alertMode alert: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '❌ Could not start native $alertMode alert: $error',
      );
      debugPrint('$stack');
    }
  }

  Future<void> _scheduleConfiguredAlert({
    required int alarmId,
    required DateTime startAt,
    required String message,
    required String alertMode,
    required String soundResource,
    required bool loopSound,
    required bool launchScanner,
    required String vibrationMode,
    String payload = '',
    int ttsRepeatCount = _defaultTtsRepeatCount,
  }) async {
    if (!startAt.isAfter(DateTime.now())) {
      debugPrint(
        '⚠️ Native alert $alarmId was not scheduled because '
            '$startAt is not in the future.',
      );
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'scheduleStart',
        {
          'alarmId': alarmId,
          'startAtMillis': startAt.millisecondsSinceEpoch,
          'message': message,
          'payload': payload,
          'alertMode': alertMode,
          'soundResource': soundResource,
          'loopSound': loopSound,
          'launchScanner': launchScanner,
          'vibrationMode': vibrationMode,
          'ttsRepeatCount': ttsRepeatCount.clamp(0, 10),
        },
      );

      debugPrint(
        '⏰ Native alert scheduled: '
            'id=$alarmId, '
            'time=$startAt, '
            'mode=$alertMode, '
            'sound=$soundResource',
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '❌ Could not schedule native $alertMode alert: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '❌ Could not schedule native $alertMode alert: '
            '$error',
      );
      debugPrint('$stack');
    }
  }
}