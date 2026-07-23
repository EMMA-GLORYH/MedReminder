// lib/services/medication_tts_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MedicationTtsService {
  MedicationTtsService._();

  static final MedicationTtsService instance = MedicationTtsService._();

  static const MethodChannel _channel = MethodChannel('medication_tts_background');

  // These values must match MainActivity.kt, TtsAlarmReceiver.kt,
  // BootRescheduleReceiver.kt and TtsSpeakService.kt.
  static const String _modeMedicationDue = 'medication_due';
  static const String _modePriorReminder = 'prior_reminder';
  static const String _modeCaretakerSos = 'caretaker_sos';
  static const String _vibrationContinuous = 'continuous';
  static const String _vibrationFivePulses = 'five_pulses';
  static const String _vibrationNone = 'none';
  static const int _defaultTtsRepeatCount = 3;

  // ✅ NEW: Control debug logging
  static const bool _debugLogging = kDebugMode;

  static void _log(String message) {
    if (_debugLogging) {
      debugPrint(message);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // STOP ACTIVE NATIVE ALERT
  // ══════════════════════════════════════════════════════════════

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
      _log('🔇 Native alert service stopped (TTS, sound, vibration, flashlight)');
    } on MissingPluginException catch (error, stack) {
      _log('⚠️ Native medication alert channel unavailable: $error');
      _log('$stack');
    } on PlatformException catch (error, stack) {
      _log('⚠️ Could not stop native alert service: ${error.message}');
      _log('$stack');
    } catch (error, stack) {
      _log('⚠️ Could not stop native alert service: $error');
      _log('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LEGACY MEDICATION REMINDER METHOD
  // ══════════════════════════════════════════════════════════════

  Future<void> speakUntilStopped({required String message}) async {
    final safeMessage = message.trim();

    if (safeMessage.isEmpty) {
      _log('⚠️ Medication speech skipped: empty message');
      return;
    }

    await _startConfiguredAlert(
      message: safeMessage,
      payload: '',
      alertMode: _modeMedicationDue,
      soundResource: 'alarm',
      loopSound: true,
      launchScanner: false,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // IMMEDIATE MEDICATION-DUE ALERT
  // ══════════════════════════════════════════════════════════════

  Future<void> startMedicationDueAlert({
    required String message,
    String payload = '',
  }) async {
    final safeMessage = message.trim();
    final safePayload = payload.trim();

    if (safeMessage.isEmpty) {
      _log('⚠️ Immediate medication alert skipped: empty message');
      return;
    }

    await _startConfiguredAlert(
      message: safeMessage,
      payload: safePayload,
      alertMode: _modeMedicationDue,
      soundResource: 'alarm',
      loopSound: true,
      launchScanner: safePayload.isNotEmpty,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // IMMEDIATE PRIOR REMINDER
  // ══════════════════════════════════════════════════════════════

  Future<void> startPriorReminder({
    required String medicationName,
    required String dosageDisplay,
    int minutesBefore = 10,
  }) async {
    final message = _buildPriorReminderMessage(
      medicationName: medicationName,
      dosageDisplay: dosageDisplay,
      minutesBefore: minutesBefore,
    );

    await _startConfiguredAlert(
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
  // IMMEDIATE CARETAKER SOS
  // ══════════════════════════════════════════════════════════════

  Future<void> startCaretakerSosAlert({required String patientName}) async {
    final safeName = patientName.trim().isEmpty ? 'A patient' : patientName.trim();
    final message = 'Urgent! Urgent! $safeName has sent an emergency SOS. Please respond immediately.';

    await _startConfiguredAlert(
      message: message,
      payload: '',
      alertMode: _modeCaretakerSos,
      soundResource: 'caretaker_sos',
      loopSound: true,
      launchScanner: false,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  Future<void> startCaretakerSosMessage({required String message}) async {
    final safeMessage = message.trim();

    if (safeMessage.isEmpty) {
      _log('⚠️ Caretaker SOS alert skipped: empty message');
      return;
    }

    await _startConfiguredAlert(
      message: safeMessage,
      payload: '',
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
  // ══════════════════════════════════════════════════════════════

  Future<void> scheduleAutoOpen({
    required int alarmId,
    required DateTime startAt,
    required String message,
    required String payload,
  }) async {
    final safeMessage = message.trim();
    final safePayload = payload.trim();

    if (safePayload.isEmpty) {
      _log('⚠️ Alarm $alarmId has empty payload - scanner won\'t open');
    }

    await _scheduleConfiguredAlert(
      alarmId: alarmId,
      startAt: startAt,
      message: safeMessage,
      payload: safePayload,
      alertMode: _modeMedicationDue,
      soundResource: 'alarm',
      loopSound: true,
      launchScanner: safePayload.isNotEmpty,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE TEN-MINUTE PRIOR REMINDER
  // ══════════════════════════════════════════════════════════════

  Future<void> schedulePriorReminder({
    required int alarmId,
    required DateTime startAt,
    required String medicationName,
    required String dosageDisplay,
    int minutesBefore = 10,
  }) async {
    if (!startAt.isAfter(DateTime.now())) {
      _log('ℹ️ Prior reminder skipped: time passed - $startAt');
      return;
    }

    final message = _buildPriorReminderMessage(
      medicationName: medicationName,
      dosageDisplay: dosageDisplay,
      minutesBefore: minutesBefore,
    );

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
  // OPTIONAL GENERIC IMMEDIATE ALERT
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
    final normalizedMode = _normalizeAlertMode(alertMode);
    final normalizedVibration = _normalizeVibrationMode(vibrationMode, normalizedMode);
    final safePayload = payload.trim();
    final safeLaunchScanner = normalizedMode == _modeMedicationDue && launchScanner && safePayload.isNotEmpty;

    await _startConfiguredAlert(
      message: message.trim(),
      payload: safePayload,
      alertMode: normalizedMode,
      soundResource: _normalizeSoundResource(soundResource, normalizedMode),
      loopSound: normalizedMode == _modePriorReminder ? false : loopSound,
      launchScanner: safeLaunchScanner,
      vibrationMode: normalizedVibration,
      ttsRepeatCount: ttsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL SCHEDULED NATIVE ALARM
  // ══════════════════════════════════════════════════════════════

  Future<void> cancelAutoOpen(int alarmId) async {
    if (alarmId <= 0) {
      _log('⚠️ Invalid alarm ID ignored: $alarmId');
      return;
    }

    try {
      await _channel.invokeMethod<void>('cancelAlarm', <String, dynamic>{
        'alarmId': alarmId,
      });

      // ✅ Only log in debug mode, reduce spam
      if (_debugLogging) {
        _log('🗑️ Alarm cancelled: $alarmId');
      }
    } on MissingPluginException catch (error, stack) {
      _log('⚠️ Native channel unavailable: $error');
      _log('$stack');
    } on PlatformException catch (error, stack) {
      _log('⚠️ Could not cancel alarm $alarmId: ${error.message}');
      _log('$stack');
    } catch (error, stack) {
      _log('⚠️ Could not cancel alarm $alarmId: $error');
      _log('$stack');
    }
  }

  Future<void> cancelPriorReminder(int alarmId) {
    return cancelAutoOpen(alarmId);
  }

  // ══════════════════════════════════════════════════════════════
  // PRIVATE MESSAGE HELPERS
  // ══════════════════════════════════════════════════════════════

  String _buildPriorReminderMessage({
    required String medicationName,
    required String dosageDisplay,
    required int minutesBefore,
  }) {
    final safeName = medicationName.trim().isEmpty ? 'your medication' : medicationName.trim();
    final safeDosage = dosageDisplay.trim();
    final safeMinutes = minutesBefore <= 0 ? 10 : minutesBefore;

    if (safeDosage.isEmpty) {
      return 'Medication reminder. $safeName is due in $safeMinutes minutes.';
    }

    return 'Medication reminder. $safeName, dosage $safeDosage, is due in $safeMinutes minutes.';
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
    final safeMessage = message.trim();
    final safePayload = payload.trim();
    final normalizedMode = _normalizeAlertMode(alertMode);
    final normalizedSound = _normalizeSoundResource(soundResource, normalizedMode);
    final normalizedVibration = _normalizeVibrationMode(vibrationMode, normalizedMode);
    final safeLaunchScanner = normalizedMode == _modeMedicationDue && launchScanner && safePayload.isNotEmpty;
    final safeLoopSound = normalizedMode == _modePriorReminder ? false : loopSound;
    final safeRepeatCount = ttsRepeatCount.clamp(0, 10);

    if (safeMessage.isEmpty && safeRepeatCount > 0) {
      _log('⚠️ Native $normalizedMode alert has empty TTS message');
    }

    try {
      await _channel.invokeMethod<void>('start', <String, dynamic>{
        'message': safeMessage,
        'payload': safePayload,
        'alertMode': normalizedMode,
        'soundResource': normalizedSound,
        'loopSound': safeLoopSound,
        'launchScanner': safeLaunchScanner,
        'vibrationMode': normalizedVibration,
        'ttsRepeatCount': safeRepeatCount,
      });

      _log('🔊 Native alert started: mode=$normalizedMode, sound=$normalizedSound, loop=$safeLoopSound, scanner=$safeLaunchScanner');
    } on MissingPluginException catch (error, stack) {
      _log('❌ Native channel unavailable: $error');
      _log('$stack');
    } on PlatformException catch (error, stack) {
      _log('❌ Could not start native $normalizedMode alert: ${error.message}');
      _log('$stack');
    } catch (error, stack) {
      _log('❌ Could not start native $normalizedMode alert: $error');
      _log('$stack');
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
    if (alarmId <= 0) {
      _log('❌ Invalid alarm ID: $alarmId');
      return;
    }

    if (!startAt.isAfter(DateTime.now())) {
      _log('⚠️ Alarm $alarmId skipped: $startAt is in the past');
      return;
    }

    final safePayload = payload.trim();
    final normalizedMode = _normalizeAlertMode(alertMode);
    final normalizedSound = _normalizeSoundResource(soundResource, normalizedMode);
    final normalizedVibration = _normalizeVibrationMode(vibrationMode, normalizedMode);
    final safeLaunchScanner = normalizedMode == _modeMedicationDue && launchScanner && safePayload.isNotEmpty;
    final safeLoopSound = normalizedMode == _modePriorReminder ? false : loopSound;
    final safeRepeatCount = ttsRepeatCount.clamp(0, 10);

    try {
      await _channel.invokeMethod<void>('scheduleStart', <String, dynamic>{
        'alarmId': alarmId,
        'startAtMillis': startAt.millisecondsSinceEpoch,
        'message': message.trim(),
        'payload': safePayload,
        'alertMode': normalizedMode,
        'soundResource': normalizedSound,
        'loopSound': safeLoopSound,
        'launchScanner': safeLaunchScanner,
        'vibrationMode': normalizedVibration,
        'ttsRepeatCount': safeRepeatCount,
      });

      // ✅ Reduced log output
      if (_debugLogging) {
        _log('⏰ Alarm scheduled: id=$alarmId, time=$startAt, mode=$normalizedMode');
      }
    } on MissingPluginException catch (error, stack) {
      _log('❌ Native channel unavailable: $error');
      _log('$stack');
    } on PlatformException catch (error, stack) {
      _log('❌ Could not schedule alarm: ${error.message}');
      _log('$stack');
    } catch (error, stack) {
      _log('❌ Could not schedule alarm: $error');
      _log('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CONFIGURATION NORMALIZATION
  // ══════════════════════════════════════════════════════════════

  String _normalizeAlertMode(String mode) {
    switch (mode.trim().toLowerCase()) {
      case _modePriorReminder:
        return _modePriorReminder;
      case _modeCaretakerSos:
        return _modeCaretakerSos;
      case _modeMedicationDue:
      default:
        return _modeMedicationDue;
    }
  }

  String _normalizeVibrationMode(String mode, String alertMode) {
    switch (mode.trim().toLowerCase()) {
      case _vibrationContinuous:
        return _vibrationContinuous;
      case _vibrationFivePulses:
        return _vibrationFivePulses;
      case _vibrationNone:
        return _vibrationNone;
      default:
        return alertMode == _modePriorReminder ? _vibrationFivePulses : _vibrationContinuous;
    }
  }

  String _normalizeSoundResource(String soundResource, String alertMode) {
    final normalized = soundResource
        .trim()
        .toLowerCase()
        .replaceAll('.mp3', '')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_');

    if (normalized.isNotEmpty) return normalized;

    switch (alertMode) {
      case _modePriorReminder:
        return 'prior_reminder';
      case _modeCaretakerSos:
        return 'caretaker_sos';
      case _modeMedicationDue:
      default:
        return 'alarm';
    }
  }
}