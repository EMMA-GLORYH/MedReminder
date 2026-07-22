// lib/services/caretaker_medication_alert_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handles medication reminder speech for a caretaker.
///
/// The native Android implementation receives these commands and
/// schedules/plays TTS with vibration and flashlight:
///
/// - No MP3 sound
/// - ✅ Vibration enabled (continuous pattern)
/// - ✅ Flashlight enabled (strobe pattern)
/// - No patient scanner screen
///
/// The native channel name must match MainActivity.kt.
class CaretakerMedicationAlertService {
  CaretakerMedicationAlertService._();

  static final CaretakerMedicationAlertService instance =
  CaretakerMedicationAlertService._();

  static const MethodChannel _channel = MethodChannel(
    'caretaker_medication_alerts',
  );

  static const String _alertTypeDue =
      'caretaker_medication_due';

  static const String _alertTypeNotTaken =
      'caretaker_medication_not_taken';

  static const int _defaultTtsRepeatCount = 1;

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE DUE-TIME CARETAKER MESSAGE
  // ══════════════════════════════════════════════════════════════

  /// Schedules the caretaker message for the patient's dose time.
  ///
  /// Message:
  ///
  /// "It is time for Elijah Emmanuel Hienwo to take the medication.
  /// Kindly monitor them."
  Future<void> scheduleDueAlert({
    required String alertId,
    required String patientId,
    required String patientName,
    required String scheduleId,
    required String medicationId,
    required DateTime scheduledFor,
    int ttsRepeatCount = _defaultTtsRepeatCount,
  }) async {
    final safeAlertId = alertId.trim();
    final safePatientId = patientId.trim();
    final safePatientName = _safePatientName(patientName);
    final safeScheduleId = scheduleId.trim();
    final safeMedicationId = medicationId.trim();

    if (safeAlertId.isEmpty ||
        safePatientId.isEmpty ||
        safeScheduleId.isEmpty ||
        safeMedicationId.isEmpty) {
      debugPrint(
        '⚠️ Caretaker due alert was not scheduled because '
            'required identifiers are missing',
      );
      return;
    }

    final message = buildDueMessage(
      patientName: safePatientName,
    );

    await _scheduleNativeAlert(
      alertId: safeAlertId,
      patientId: safePatientId,
      patientName: safePatientName,
      scheduleId: safeScheduleId,
      medicationId: safeMedicationId,
      scheduledFor: scheduledFor,
      message: message,
      alertType: _alertTypeDue,
      ttsRepeatCount: ttsRepeatCount,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE TEN-MINUTE NOT-TAKEN MESSAGE
  // ══════════════════════════════════════════════════════════════

  /// Schedules the caretaker warning ten minutes after a dose was due.
  ///
  /// Message:
  ///
  /// "The medication for Elijah Emmanuel Hienwo scheduled at 8:00 AM
  /// has not been taken. Please check on them."
  Future<void> scheduleNotTakenAlert({
    required String alertId,
    required String patientId,
    required String patientName,
    required String scheduleId,
    required String medicationId,
    required DateTime scheduledFor,
    int ttsRepeatCount = _defaultTtsRepeatCount,
  }) async {
    final safeAlertId = alertId.trim();
    final safePatientId = patientId.trim();
    final safePatientName = _safePatientName(patientName);
    final safeScheduleId = scheduleId.trim();
    final safeMedicationId = medicationId.trim();

    if (safeAlertId.isEmpty ||
        safePatientId.isEmpty ||
        safeScheduleId.isEmpty ||
        safeMedicationId.isEmpty) {
      debugPrint(
        '⚠️ Caretaker not-taken alert was not scheduled because '
            'required identifiers are missing',
      );
      return;
    }

    final retryTime = DateTime.now().add(
      const Duration(minutes: 10),
    );

    final message = buildNotTakenMessage(
      patientName: safePatientName,
      scheduledFor: scheduledFor,
    );

    await _scheduleNativeAlert(
      alertId: safeAlertId,
      patientId: safePatientId,
      patientName: safePatientName,
      scheduleId: safeScheduleId,
      medicationId: safeMedicationId,
      scheduledFor: retryTime,
      originalScheduledFor: scheduledFor,
      message: message,
      alertType: _alertTypeNotTaken,
      ttsRepeatCount: ttsRepeatCount,
    );

    debugPrint(
      '🔁 Caretaker not-taken TTS scheduled for $retryTime',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CANCEL ONE CARETAKER ALERT
  // ══════════════════════════════════════════════════════════════

  /// Cancels the caretaker alert/retry for a specific dose.
  ///
  /// This should be called as soon as the patient marks the dose as taken.
  Future<void> cancelDoseAlert({
    required String alertId,
    required String patientId,
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    final safeAlertId = alertId.trim();
    final safePatientId = patientId.trim();
    final safeScheduleId = scheduleId.trim();

    if (safeAlertId.isEmpty ||
        safePatientId.isEmpty ||
        safeScheduleId.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'cancelCaretakerMedicationAlert',
        <String, dynamic>{
          'alertId': safeAlertId,
          'patientId': safePatientId,
          'scheduleId': safeScheduleId,
          'scheduledForMillis':
          scheduledFor.millisecondsSinceEpoch,
        },
      );

      debugPrint(
        '🗑️ Cancelled caretaker medication alert: '
            '$safeAlertId',
      );
    } on MissingPluginException {
      debugPrint(
        '⚠️ Caretaker medication native channel is not '
            'implemented yet',
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '⚠️ Could not cancel caretaker medication alert: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '⚠️ Unexpected caretaker alert cancellation error: '
            '$error',
      );
      debugPrint('$stack');
    }
  }

  /// Cancels all caretaker medication alerts for one patient.
  Future<void> cancelPatientAlerts({
    required String patientId,
  }) async {
    final safePatientId = patientId.trim();

    if (safePatientId.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'cancelCaretakerPatientAlerts',
        <String, dynamic>{
          'patientId': safePatientId,
        },
      );
    } on MissingPluginException {
      debugPrint(
        '⚠️ Caretaker medication native channel is not '
            'implemented yet',
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '⚠️ Could not cancel patient caretaker alerts: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '⚠️ Unexpected patient alert cancellation error: '
            '$error',
      );
      debugPrint('$stack');
    }
  }

  /// Stops any currently speaking caretaker medication message.
  Future<void> stopCurrentAlert() async {
    try {
      await _channel.invokeMethod<void>(
        'stopCaretakerMedicationAlert',
      );
    } on MissingPluginException {
      debugPrint(
        '⚠️ Caretaker medication native channel is not '
            'implemented yet',
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '⚠️ Could not stop caretaker medication alert: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '⚠️ Unexpected caretaker alert stop error: '
            '$error',
      );
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // MESSAGE BUILDERS
  // ══════════════════════════════════════════════════════════════

  String buildDueMessage({
    required String patientName,
  }) {
    final safeName = _safePatientName(patientName);

    return 'It is time for $safeName to take the medication. '
        'Kindly monitor them.';
  }

  String buildNotTakenMessage({
    required String patientName,
    required DateTime scheduledFor,
  }) {
    final safeName = _safePatientName(patientName);
    final time = _formatTime(scheduledFor);

    return 'The medication for $safeName scheduled at $time '
        'has not been taken. Please check on them.';
  }

  // ══════════════════════════════════════════════════════════════
  // NATIVE METHOD-CHANNEL HELPER
  // ══════════════════════════════════════════════════════════════

  Future<void> _scheduleNativeAlert({
    required String alertId,
    required String patientId,
    required String patientName,
    required String scheduleId,
    required String medicationId,
    required DateTime scheduledFor,
    required String message,
    required String alertType,
    required int ttsRepeatCount,
    DateTime? originalScheduledFor,
  }) async {
    final safeRepeatCount = ttsRepeatCount.clamp(1, 3);

    try {
      await _channel.invokeMethod<void>(
        'scheduleCaretakerMedicationAlert',
        <String, dynamic>{
          'alertId': alertId,
          'patientId': patientId,
          'patientName': patientName,
          'scheduleId': scheduleId,
          'medicationId': medicationId,
          'scheduledForMillis':
          scheduledFor.millisecondsSinceEpoch,
          'originalScheduledForMillis':
          originalScheduledFor?.millisecondsSinceEpoch,
          'message': message,
          'alertType': alertType,
          'ttsRepeatCount': safeRepeatCount,
        },
      );

      debugPrint(
        '🗣️ Caretaker medication TTS scheduled: '
            'type=$alertType, '
            'patient=$patientName, '
            'time=$scheduledFor',
      );
    } on MissingPluginException {
      debugPrint(
        '⚠️ Caretaker medication native channel is not '
            'implemented yet',
      );
    } on PlatformException catch (error, stack) {
      debugPrint(
        '⚠️ Could not schedule caretaker medication TTS: '
            '${error.message}',
      );
      debugPrint('$stack');
    } catch (error, stack) {
      debugPrint(
        '⚠️ Unexpected caretaker medication scheduling error: '
            '$error',
      );
      debugPrint('$stack');
    }
  }

  String _safePatientName(String value) {
    final cleaned = value
        .replaceAll('|', ' ')
        .replaceAll('\n', ' ')
        .trim();

    return cleaned.isEmpty ? 'the patient' : cleaned;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute =
    dateTime.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour =
    hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;

    return '$displayHour:$minute $period';
  }
}