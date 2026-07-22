// lib/services/caretaker_medication_monitor_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/care_relationship.dart';
import 'auth_service.dart';
import 'caretaker_medication_alert_service.dart';
import 'schedule_service.dart';

/// Monitors linked patients' medication schedules and triggers
/// caretaker alerts.
///
/// For each active care relationship where `can_view_medications` is true:
/// - Schedules a "due" alert at each dose time
/// - Schedules a "not taken" alert 10 minutes after each dose time
/// - Cancels alerts when the patient marks the dose as taken
///
/// Alert behavior (handled natively):
/// - TTS announcement
/// - Continuous vibration
/// - Flashlight strobe
/// - High-priority notification
/// - NO MP3, NO scanner
class CaretakerMedicationMonitorService {
  CaretakerMedicationMonitorService._();

  static final CaretakerMedicationMonitorService instance =
  CaretakerMedicationMonitorService._();

  final _supabase = Supabase.instance.client;
  final _alertService = CaretakerMedicationAlertService.instance;

  /// Tracks which dose alerts have already been scheduled.
  /// Key format: "patientId_scheduleId_scheduledForMillis"
  final Set<String> _scheduledAlertKeys = {};

  /// Realtime subscription for medication_logs (to detect "taken").
  RealtimeChannel? _logsChannel;

  /// Periodic timer to refresh schedules.
  Timer? _refreshTimer;

  bool _isRunning = false;
  String? _caregiverId;

  /// How often to re-scan patient schedules.
  static const Duration _refreshInterval = Duration(minutes: 15);

  /// Delay after dose time for the "not taken" alert.
  static const Duration _notTakenDelay = Duration(minutes: 10);

  /// How many days ahead to schedule (today + tomorrow).
  static const int _daysAhead = 2;

  // ══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════

  /// Starts monitoring. Call this when the caretaker home screen opens.
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('ℹ️ Caretaker medication monitor already running');
      return;
    }

    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) {
      debugPrint('⚠️ Cannot start monitor: no authenticated user');
      return;
    }

    _caregiverId = caregiverId;
    _isRunning = true;

    debugPrint('🚀 Starting caretaker medication monitor');
    debugPrint('   Caregiver ID: $caregiverId');

    // Initial scan
    await _scanAndScheduleAlerts();

    // Subscribe to medication logs to detect "taken" events
    _subscribeToMedicationLogs();

    // Periodic refresh
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      _scanAndScheduleAlerts();
    });

    debugPrint('✅ Caretaker medication monitor started');
  }

  /// Stops monitoring. Call this when the caretaker logs out.
  Future<void> stop() async {
    if (!_isRunning) return;

    debugPrint('🛑 Stopping caretaker medication monitor');

    _refreshTimer?.cancel();
    _refreshTimer = null;

    await _unsubscribeFromMedicationLogs();

    // Stop any currently playing alert
    await _alertService.stopCurrentAlert();

    _scheduledAlertKeys.clear();
    _isRunning = false;
    _caregiverId = null;

    debugPrint('✅ Caretaker medication monitor stopped');
  }

  /// Forces an immediate re-scan of all patient schedules.
  Future<void> refresh() async {
    if (!_isRunning) return;
    await _scanAndScheduleAlerts();
  }

  // ══════════════════════════════════════════════════════════════
  // SCANNING & SCHEDULING
  // ══════════════════════════════════════════════════════════════

  Future<void> _scanAndScheduleAlerts() async {
    final caregiverId = _caregiverId;
    if (caregiverId == null) return;

    try {
      debugPrint('🔍 Scanning patient schedules for caretaker alerts');

      // 1. Load all active care relationships where caretaker can view meds
      final relationships = await _loadMonitorableRelationships(caregiverId);

      if (relationships.isEmpty) {
        debugPrint('ℹ️ No monitorable patient relationships found');
        return;
      }

      debugPrint('   Found ${relationships.length} patient(s) to monitor');

      // 2. For each patient, load doses and schedule alerts
      for (final relationship in relationships) {
        await _processPatientDoses(relationship);
      }

      debugPrint('✅ Schedule scan complete');
    } catch (e, stack) {
      debugPrint('❌ Error scanning schedules: $e');
      debugPrint('$stack');
    }
  }

  Future<List<CareRelationship>> _loadMonitorableRelationships(
      String caregiverId,
      ) async {
    try {
      // Load active relationships with can_view_medications = true
      // Join the patient profile so we get the patient's name
      final response = await _supabase
          .from('care_relationships')
          .select(
        '*, '
            'profiles!care_relationships_patient_id_fkey'
            '(full_name, phone_number, avatar_url, role)',
      )
          .eq('caregiver_id', caregiverId)
          .eq('status', 'active')
          .eq('can_view_medications', true);

      final relationships = (response as List).map((json) {
        final map = Map<String, dynamic>.from(json as Map);

        // The join uses the `profiles` key. Copy it into
        // `_patient_profile` so fromJsonAsCaretaker can read it.
        map['_patient_profile'] = map['profiles'];

        return CareRelationship.fromJsonAsCaretaker(map);
      }).toList();

      return relationships;
    } catch (e, stack) {
      debugPrint('❌ Error loading relationships: $e');
      debugPrint('$stack');
      return [];
    }
  }

  Future<void> _processPatientDoses(
      CareRelationship relationship,
      ) async {
    final patientId = relationship.patientId;
    final patientName = _safePatientName(relationship);

    try {
      debugPrint('   Processing patient: $patientName ($patientId)');

      final now = DateTime.now();

      // Load doses for today and the next few days
      for (int dayOffset = 0; dayOffset < _daysAhead; dayOffset++) {
        final date = now.add(Duration(days: dayOffset));

        // ScheduleService.getDosesForPatient already verifies
        // can_view_medications permission internally.
        final doses = await ScheduleService.instance.getDosesForPatient(
          patientId: patientId,
          date: date,
        );

        if (doses.isEmpty) {
          continue;
        }

        debugPrint(
          '      Found ${doses.length} dose(s) for '
              '${date.toIso8601String().split('T').first}',
        );

        for (final dose in doses) {
          // Only schedule future doses
          if (dose.scheduledTime.isBefore(now)) {
            continue;
          }

          await _scheduleAlertsForDose(
            patientId: patientId,
            patientName: patientName,
            dose: dose,
          );
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Error processing patient $patientId: $e');
      debugPrint('$stack');
    }
  }

  Future<void> _scheduleAlertsForDose({
    required String patientId,
    required String patientName,
    required TodayDose dose,
  }) async {
    final scheduleId = dose.scheduleId;
    final medicationId = dose.medicationId;
    final doseTime = dose.scheduledTime;
    final doseMillis = doseTime.millisecondsSinceEpoch;

    // Deduplication key
    final alertKey = '${patientId}_${scheduleId}_$doseMillis';

    if (_scheduledAlertKeys.contains(alertKey)) {
      // Already scheduled this dose
      return;
    }

    // Check if the patient already logged this dose as taken/skipped
    final alreadyLogged = await _isPatientDoseLogged(
      patientId: patientId,
      scheduleId: scheduleId,
      doseTime: doseTime,
    );

    if (alreadyLogged) {
      debugPrint(
        '      ⏭️ Dose already logged, skipping: '
            '$scheduleId @ ${_formatTime(doseTime)}',
      );
      _scheduledAlertKeys.add(alertKey);
      return;
    }

    // Unique alert IDs for due and not-taken alerts
    final dueAlertId = 'due_$alertKey';
    final notTakenAlertId = 'nottaken_$alertKey';

    // 1. Schedule the "due" alert at dose time
    await _alertService.scheduleDueAlert(
      alertId: dueAlertId,
      patientId: patientId,
      patientName: patientName,
      scheduleId: scheduleId,
      medicationId: medicationId,
      scheduledFor: doseTime,
    );

    // 2. Schedule the "not taken" alert 10 minutes later
    final notTakenTime = doseTime.add(_notTakenDelay);
    await _alertService.scheduleNotTakenAlert(
      alertId: notTakenAlertId,
      patientId: patientId,
      patientName: patientName,
      scheduleId: scheduleId,
      medicationId: medicationId,
      scheduledFor: doseTime, // pass original dose time for the message
    );

    _scheduledAlertKeys.add(alertKey);

    debugPrint(
      '      ✅ Scheduled alerts for dose: '
          '$patientName @ ${_formatTime(doseTime)} '
          '(not-taken @ ${_formatTime(notTakenTime)})',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DOSE LOG CHECKING
  // ══════════════════════════════════════════════════════════════

  /// Checks if the patient has logged this dose as taken or skipped.
  Future<bool> _isPatientDoseLogged({
    required String patientId,
    required String scheduleId,
    required DateTime doseTime,
  }) async {
    try {
      // Look for a log entry near this dose time (within a window)
      final windowStart = doseTime.subtract(const Duration(hours: 1));
      final windowEnd = doseTime.add(const Duration(hours: 2));

      final response = await _supabase
          .from('medication_logs')
          .select('id, status')
          .eq('patient_id', patientId)
          .eq('schedule_id', scheduleId)
          .gte('scheduled_time', windowStart.toIso8601String())
          .lte('scheduled_time', windowEnd.toIso8601String())
          .inFilter('status', ['taken', 'skipped'])
          .limit(1);

      final logs = response as List;
      return logs.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ Error checking dose log: $e');
      // On error, assume not logged (safer to alert)
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // REALTIME: DETECT "TAKEN" EVENTS
  // ══════════════════════════════════════════════════════════════

  void _subscribeToMedicationLogs() {
    final caregiverId = _caregiverId;
    if (caregiverId == null || _logsChannel != null) return;

    try {
      debugPrint('🔌 Subscribing to medication_logs realtime');

      _logsChannel = _supabase
          .channel('caretaker_medication_logs_$caregiverId')
          .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'medication_logs',
        callback: _handleLogChange,
      )
          .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'medication_logs',
        callback: _handleLogChange,
      )
          .subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Subscribed to medication_logs');
        } else if (status ==
            RealtimeSubscribeStatus.channelError) {
          debugPrint('❌ medication_logs channel error: $error');
        }
      });
    } catch (e, stack) {
      debugPrint('❌ Error subscribing to logs: $e');
      debugPrint('$stack');
    }
  }

  void _handleLogChange(PostgresChangePayload payload) {
    _handleDoseTaken(payload.newRecord);
  }

  /// When a patient marks a dose as taken/skipped, cancel the alerts.
  Future<void> _handleDoseTaken(Map<String, dynamic> record) async {
    try {
      final status = record['status'] as String?;

      // Only act on "taken" or "skipped"
      if (status != 'taken' && status != 'skipped') {
        return;
      }

      final patientId = record['patient_id'] as String?;
      final scheduleId = record['schedule_id'] as String?;
      final scheduledTimeStr = record['scheduled_time'] as String?;

      if (patientId == null ||
          scheduleId == null ||
          scheduledTimeStr == null) {
        return;
      }

      final scheduledTime = DateTime.parse(scheduledTimeStr).toLocal();

      debugPrint(
        '📨 Dose $status detected: '
            'patient=$patientId, schedule=$scheduleId, '
            'time=${_formatTime(scheduledTime)}',
      );

      // Cancel the alerts for this dose
      await _cancelAlertsForDose(
        patientId: patientId,
        scheduleId: scheduleId,
        doseTime: scheduledTime,
      );
    } catch (e, stack) {
      debugPrint('❌ Error handling dose taken: $e');
      debugPrint('$stack');
    }
  }

  Future<void> _cancelAlertsForDose({
    required String patientId,
    required String scheduleId,
    required DateTime doseTime,
  }) async {
    final doseMillis = doseTime.millisecondsSinceEpoch;
    final alertKey = '${patientId}_${scheduleId}_$doseMillis';

    final dueAlertId = 'due_$alertKey';
    final notTakenAlertId = 'nottaken_$alertKey';

    // Cancel the due alert
    await _alertService.cancelDoseAlert(
      alertId: dueAlertId,
      patientId: patientId,
      scheduleId: scheduleId,
      scheduledFor: doseTime,
    );

    // Cancel the not-taken alert
    await _alertService.cancelDoseAlert(
      alertId: notTakenAlertId,
      patientId: patientId,
      scheduleId: scheduleId,
      scheduledFor: doseTime.add(_notTakenDelay),
    );

    // Stop any currently playing alert (in case it's ringing now)
    await _alertService.stopCurrentAlert();

    // Remove from tracking
    _scheduledAlertKeys.remove(alertKey);

    debugPrint(
      '🗑️ Cancelled caretaker alerts for logged dose: '
          '$scheduleId @ ${_formatTime(doseTime)}',
    );
  }

  Future<void> _unsubscribeFromMedicationLogs() async {
    if (_logsChannel != null) {
      debugPrint('🔌 Unsubscribing from medication_logs');
      await _supabase.removeChannel(_logsChannel!);
      _logsChannel = null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════

  /// Gets a clean patient name from the relationship.
  String _safePatientName(CareRelationship relationship) {
    final name = relationship.otherPartyFullName?.trim();
    if (name == null || name.isEmpty) {
      return 'the patient';
    }
    return name;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    return '$displayHour:$minute $period';
  }
}