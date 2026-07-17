// lib/services/medication_tts_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MedicationTtsService {
  MedicationTtsService._();

  static final MedicationTtsService instance =
  MedicationTtsService._();

  static const MethodChannel _channel = MethodChannel(
    'medication_tts_background',
  );

  // These values must match MainActivity.kt, TtsAlarmReceiver.kt,
  // BootRescheduleReceiver.kt and TtsSpeakService.kt.
  static const String _modeMedicationDue =
      'medication_due';

  static const String _modePriorReminder =
      'prior_reminder';

  static const String _modeCaretakerSos =
      'caretaker_sos';

  static const String _vibrationContinuous =
      'continuous';

  static const String _vibrationFivePulses =
      'five_pulses';

  static const String _vibrationNone =
      'none';

  static const int _defaultTtsRepeatCount = 3;

  // ══════════════════════════════════════════════════════════════
  // STOP ACTIVE NATIVE ALERT
  // ══════════════════════════════════════════════════════════════

  /// Stops every effect owned by the native alert service:
  ///
  /// - Text-to-speech
  /// - MP3 alarm playback
  /// - Vibration
  /// - Physical camera flashlight
  /// - Foreground-service notification
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>(
        'stop',
      );

      debugPrint(
        '🔇 Native alert service stopped '
            '(TTS, sound, vibration and flashlight)',
      );
    } on MissingPluginException catch (error, stack) {
      debugPrint(
        '⚠️ Native medication alert channel is unavailable: '
            '$error',
      );
      debugPrint('$stack');
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
  // LEGACY MEDICATION REMINDER METHOD
  // ══════════════════════════════════════════════════════════════

  /// Starts the active medication reminder from an already-open reminder
  /// screen.
  ///
  /// This method remains for compatibility with
  /// MedicationReminderScannerScreen. Its configuration is now explicit
  /// instead of relying on Kotlin defaults.
  ///
  /// Since it has no payload, it does not attempt to open another scanner
  /// screen.
  Future<void> speakUntilStopped({
    required String message,
  }) async {
    final safeMessage = message.trim();

    if (safeMessage.isEmpty) {
      debugPrint(
        '⚠️ Medication speech was not started because '
            'the message was empty',
      );
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

  /// Starts an immediate medication-due alert.
  ///
  /// Native behavior:
  ///
  /// - Speaks the supplied message three times.
  /// - Vibrates continuously.
  /// - Flashes the physical camera flashlight when available.
  /// - Plays alarm.mp3 continuously after speech.
  /// - Opens the medication screen when [payload] is not empty.
  Future<void> startMedicationDueAlert({
    required String message,
    String payload = '',
  }) async {
    final safeMessage = message.trim();
    final safePayload = payload.trim();

    if (safeMessage.isEmpty) {
      debugPrint(
        '⚠️ Immediate medication alert was not started '
            'because its message was empty',
      );
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

  /// Starts an immediate informational prior reminder.
  ///
  /// Native behavior:
  ///
  /// - Speaks three times.
  /// - Vibrates five times.
  /// - Plays prior_reminder.mp3 once.
  /// - Does not flash the camera light.
  /// - Does not open the medication screen.
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

  /// Starts a caretaker SOS alert.
  ///
  /// Native behavior:
  ///
  /// - Speaks the emergency message three times.
  /// - Vibrates continuously.
  /// - Flashes the physical camera flashlight when available.
  /// - Loops caretaker_sos.mp3.
  /// - Does not open the medication screen.
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
      payload: '',
      alertMode: _modeCaretakerSos,
      soundResource: 'caretaker_sos',
      loopSound: true,
      launchScanner: false,
      vibrationMode: _vibrationContinuous,
      ttsRepeatCount: _defaultTtsRepeatCount,
    );
  }

  /// Starts an SOS alert using an already localized or customized message.
  Future<void> startCaretakerSosMessage({
    required String message,
  }) async {
    final safeMessage = message.trim();

    if (safeMessage.isEmpty) {
      debugPrint(
        '⚠️ Caretaker SOS alert was not started because '
            'its message was empty',
      );
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

  /// Schedules the exact due-time medication alert.
  ///
  /// The payload must contain the dose details needed to build TodayDose,
  /// including pillImageUrl. That allows the screen to open without making
  /// an authenticated database request.
  Future<void> scheduleAutoOpen({
    required int alarmId,
    required DateTime startAt,
    required String message,
    required String payload,
  }) async {
    final safeMessage = message.trim();
    final safePayload = payload.trim();

    if (safePayload.isEmpty) {
      debugPrint(
        '⚠️ Medication alert $alarmId has an empty payload. '
            'The alarm can run, but the medication screen will not open.',
      );
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

  /// Schedules an informational reminder before the medication due time.
  ///
  /// The caller passes the actual prior-reminder time, normally:
  ///
  /// `scheduledFor.subtract(const Duration(minutes: 10))`
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

  /// Starts a custom native alert.
  ///
  /// Scanner launch is restricted to medication_due alerts with a payload.
  /// This prevents prior reminders and caretaker SOS alerts from opening
  /// the medication screen accidentally.
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
    final normalizedMode = _normalizeAlertMode(
      alertMode,
    );

    final normalizedVibration = _normalizeVibrationMode(
      vibrationMode,
      normalizedMode,
    );

    final safePayload = payload.trim();

    final safeLaunchScanner =
        normalizedMode == _modeMedicationDue &&
            launchScanner &&
            safePayload.isNotEmpty;

    await _startConfiguredAlert(
      message: message.trim(),
      payload: safePayload,
      alertMode: normalizedMode,
      soundResource: _normalizeSoundResource(
        soundResource,
        normalizedMode,
      ),
      loopSound: normalizedMode == _modePriorReminder
          ? false
          : loopSound,
      launchScanner: safeLaunchScanner,
      vibrationMode: normalizedVibration,
      ttsRepeatCount: ttsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL SCHEDULED NATIVE ALARM
  // ══════════════════════════════════════════════════════════════

  Future<void> cancelAutoOpen(
      int alarmId,
      ) async {
    if (alarmId <= 0) {
      debugPrint(
        '⚠️ Native alarm cancellation ignored because '
            'the alarm ID was invalid: $alarmId',
      );
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'cancelAlarm',
        <String, dynamic>{
          'alarmId': alarmId,
        },
      );

      debugPrint(
        '🗑️ Native alert alarm cancelled: $alarmId',
      );
    } on MissingPluginException catch (error, stack) {
      debugPrint(
        '⚠️ Native medication alert channel is unavailable: '
            '$error',
      );
      debugPrint('$stack');
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
  Future<void> cancelPriorReminder(
      int alarmId,
      ) {
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
    final safeName = medicationName.trim().isEmpty
        ? 'your medication'
        : medicationName.trim();

    final safeDosage = dosageDisplay.trim();

    final safeMinutes = minutesBefore <= 0
        ? 10
        : minutesBefore;

    if (safeDosage.isEmpty) {
      return 'Medication reminder. $safeName is due in '
          '$safeMinutes minutes.';
    }

    return 'Medication reminder. $safeName, dosage '
        '$safeDosage, is due in $safeMinutes minutes.';
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

    final normalizedMode = _normalizeAlertMode(
      alertMode,
    );

    final normalizedSound = _normalizeSoundResource(
      soundResource,
      normalizedMode,
    );

    final normalizedVibration = _normalizeVibrationMode(
      vibrationMode,
      normalizedMode,
    );

    final safeLaunchScanner =
        normalizedMode == _modeMedicationDue &&
            launchScanner &&
            safePayload.isNotEmpty;

    final safeLoopSound =
    normalizedMode == _modePriorReminder
        ? false
        : loopSound;

    final safeRepeatCount =
    ttsRepeatCount.clamp(0, 10);

    if (safeMessage.isEmpty && safeRepeatCount > 0) {
      debugPrint(
        '⚠️ Native $normalizedMode alert has an empty '
            'TTS message; native sound fallback will be used',
      );
    }

    try {
      await _channel.invokeMethod<void>(
        'start',
        <String, dynamic>{
          'message': safeMessage,
          'payload': safePayload,
          'alertMode': normalizedMode,
          'soundResource': normalizedSound,
          'loopSound': safeLoopSound,
          'launchScanner': safeLaunchScanner,
          'vibrationMode': normalizedVibration,
          'ttsRepeatCount': safeRepeatCount,
        },
      );

      debugPrint(
        '🔊 Native alert started: '
            'mode=$normalizedMode, '
            'sound=$normalizedSound, '
            'loop=$safeLoopSound, '
            'scanner=$safeLaunchScanner, '
            'vibration=$normalizedVibration, '
            'tts=$safeRepeatCount',
      );
    } on MissingPluginException catch (error, stack) {
      debugPrint(
        '❌ Native medication alert channel is unavailable: '
            '$error',
      );
      debugPrint('$stack');
    } on PlatformException catch (error, stack) {
      debugPrint(
        '❌ Could not start native $normalizedMode alert: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '❌ Could not start native $normalizedMode alert: '
            '$error',
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
    if (alarmId <= 0) {
      debugPrint(
        '❌ Native alert was not scheduled because '
            'the alarm ID was invalid: $alarmId',
      );
      return;
    }

    if (!startAt.isAfter(DateTime.now())) {
      debugPrint(
        '⚠️ Native alert $alarmId was not scheduled because '
            '$startAt is not in the future.',
      );
      return;
    }

    final safePayload = payload.trim();

    final normalizedMode = _normalizeAlertMode(
      alertMode,
    );

    final normalizedSound = _normalizeSoundResource(
      soundResource,
      normalizedMode,
    );

    final normalizedVibration = _normalizeVibrationMode(
      vibrationMode,
      normalizedMode,
    );

    final safeLaunchScanner =
        normalizedMode == _modeMedicationDue &&
            launchScanner &&
            safePayload.isNotEmpty;

    final safeLoopSound =
    normalizedMode == _modePriorReminder
        ? false
        : loopSound;

    final safeRepeatCount =
    ttsRepeatCount.clamp(0, 10);

    try {
      await _channel.invokeMethod<void>(
        'scheduleStart',
        <String, dynamic>{
          'alarmId': alarmId,
          'startAtMillis':
          startAt.millisecondsSinceEpoch,
          'message': message.trim(),
          'payload': safePayload,
          'alertMode': normalizedMode,
          'soundResource': normalizedSound,
          'loopSound': safeLoopSound,
          'launchScanner': safeLaunchScanner,
          'vibrationMode': normalizedVibration,
          'ttsRepeatCount': safeRepeatCount,
        },
      );

      debugPrint(
        '⏰ Native alert scheduled: '
            'id=$alarmId, '
            'time=$startAt, '
            'mode=$normalizedMode, '
            'sound=$normalizedSound, '
            'scanner=$safeLaunchScanner',
      );
    } on MissingPluginException catch (error, stack) {
      debugPrint(
        '❌ Native medication alert channel is unavailable: '
            '$error',
      );
      debugPrint('$stack');
    } on PlatformException catch (error, stack) {
      debugPrint(
        '❌ Could not schedule native $normalizedMode alert: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '❌ Could not schedule native $normalizedMode alert: '
            '$error',
      );
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CONFIGURATION NORMALIZATION
  // ══════════════════════════════════════════════════════════════

  String _normalizeAlertMode(
      String mode,
      ) {
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

  String _normalizeVibrationMode(
      String mode,
      String alertMode,
      ) {
    switch (mode.trim().toLowerCase()) {
      case _vibrationContinuous:
        return _vibrationContinuous;

      case _vibrationFivePulses:
        return _vibrationFivePulses;

      case _vibrationNone:
        return _vibrationNone;

      default:
        return alertMode == _modePriorReminder
            ? _vibrationFivePulses
            : _vibrationContinuous;
    }
  }

  String _normalizeSoundResource(
      String soundResource,
      String alertMode,
      ) {
    final normalized = soundResource
        .trim()
        .toLowerCase()
        .replaceAll(
      '.mp3',
      '',
    )
        .replaceAll(
      RegExp(r'[^a-z0-9_]'),
      '_',
    );

    if (normalized.isNotEmpty) {
      return normalized;
    }

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