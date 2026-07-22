// lib/services/dose_log_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';
import 'medication_tts_service.dart';

class DoseLogService {
  DoseLogService._();

  static final DoseLogService instance = DoseLogService._();

  static const String _pendingLogsPreferenceKey =
      'pending_dose_logs_v1';

  bool _isSynchronizing = false;

  // ══════════════════════════════════════════════════════════════
  // MARK AS TAKEN
  // ══════════════════════════════════════════════════════════════

  Future<void> markAsTaken({
    required String scheduleId,
    required String medicationId,
    required DateTime scheduledFor,
    String? patientId,
  }) async {
    final safeScheduleId = scheduleId.trim();
    final safeMedicationId = medicationId.trim();

    if (safeScheduleId.isEmpty) {
      throw ArgumentError.value(
        scheduleId,
        'scheduleId',
        'Schedule ID cannot be empty',
      );
    }

    if (safeMedicationId.isEmpty) {
      throw ArgumentError.value(
        medicationId,
        'medicationId',
        'Medication ID cannot be empty',
      );
    }

    final currentUserId =
        AuthService.instance.currentUser?.id;

    final expectedPatientId =
        _cleanOptionalString(patientId) ??
            currentUserId;

    final now = DateTime.now();
    final deviationMinutes =
        now.difference(scheduledFor).inMinutes;

    final status = deviationMinutes.abs() > 30
        ? 'late'
        : 'taken';

    final pendingLog = _PendingDoseLog(
      scheduleId: safeScheduleId,
      medicationId: safeMedicationId,
      patientId: expectedPatientId,
      scheduledFor: scheduledFor,
      loggedAt: now,
      status: status,
    );

    await _storePendingLog(pendingLog);

    debugPrint(
      '✅ Dose acknowledgement saved locally: '
          '${pendingLog.uniqueKey}',
    );

    await MedicationTtsService.instance.stop();

    try {
      await LocalNotificationService.instance.cancelDose(
        scheduleId: safeScheduleId,
        scheduledFor: scheduledFor,
      );

      debugPrint(
        '✅ Device alerts cancelled for the confirmed dose',
      );
    } catch (error, stack) {
      debugPrint(
        '⚠️ Dose saved locally, but its alarms could not '
            'all be cancelled: $error',
      );
      debugPrint('$stack');
    }

    if (currentUserId != null &&
        (expectedPatientId == null ||
            expectedPatientId == currentUserId)) {
      unawaited(syncPendingDoseLogs());
    }
  }

  // ══════════════════════════════════════════════════════════════
  // MARK AS SKIPPED
  // ══════════════════════════════════════════════════════════════

  Future<void> markAsSkipped({
    required String scheduleId,
    required String medicationId,
    required DateTime scheduledFor,
    String? reason,
    String? patientId,
  }) async {
    final safeScheduleId = scheduleId.trim();
    final safeMedicationId = medicationId.trim();

    if (safeScheduleId.isEmpty) {
      throw ArgumentError.value(
        scheduleId,
        'scheduleId',
        'Schedule ID cannot be empty',
      );
    }

    if (safeMedicationId.isEmpty) {
      throw ArgumentError.value(
        medicationId,
        'medicationId',
        'Medication ID cannot be empty',
      );
    }

    final currentUserId =
        AuthService.instance.currentUser?.id;

    final expectedPatientId =
        _cleanOptionalString(patientId) ??
            currentUserId;

    final pendingLog = _PendingDoseLog(
      scheduleId: safeScheduleId,
      medicationId: safeMedicationId,
      patientId: expectedPatientId,
      scheduledFor: scheduledFor,
      loggedAt: DateTime.now(),
      status: 'skipped',
      notes: _cleanOptionalString(reason),
    );

    await _storePendingLog(pendingLog);

    debugPrint(
      '⏭️ Skipped dose saved locally: '
          '${pendingLog.uniqueKey}',
    );

    await MedicationTtsService.instance.stop();

    try {
      await LocalNotificationService.instance.cancelDose(
        scheduleId: safeScheduleId,
        scheduledFor: scheduledFor,
      );

      debugPrint(
        '✅ Device alerts cancelled for skipped dose',
      );
    } catch (error, stack) {
      debugPrint(
        '⚠️ Skipped dose saved locally, but its alarms '
            'could not all be cancelled: $error',
      );
      debugPrint('$stack');
    }

    if (currentUserId != null &&
        (expectedPatientId == null ||
            expectedPatientId == currentUserId)) {
      unawaited(syncPendingDoseLogs());
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SYNC PENDING
  // ══════════════════════════════════════════════════════════════

  Future<void> syncPendingDoseLogs() async {
    if (_isSynchronizing) return;

    final currentUserId =
        AuthService.instance.currentUser?.id;

    if (currentUserId == null) {
      debugPrint(
        'ℹ️ Pending dose logs were not synchronized '
            'because no user is logged in',
      );
      return;
    }

    _isSynchronizing = true;

    try {
      final pendingLogs = await _readPendingLogs();

      if (pendingLogs.isEmpty) return;

      debugPrint(
        '🔄 Synchronizing ${pendingLogs.length} '
            'pending dose log(s)',
      );

      for (final pendingLog in pendingLogs) {
        if (pendingLog.patientId != null &&
            pendingLog.patientId != currentUserId) {
          debugPrint(
            '⏭️ Pending dose belongs to another patient; '
                'leaving it queued: ${pendingLog.uniqueKey}',
          );
          continue;
        }

        try {
          if (pendingLog.patientId == null) {
            final belongsToCurrentUser =
            await _scheduleBelongsToPatient(
              scheduleId: pendingLog.scheduleId,
              patientId: currentUserId,
            );

            if (!belongsToCurrentUser) {
              debugPrint(
                '⏭️ Could not associate pending dose with '
                    'the current patient: ${pendingLog.uniqueKey}',
              );
              continue;
            }
          }

          await _uploadPendingLog(
            pendingLog: pendingLog,
            patientId: currentUserId,
          );

          await _removePendingLog(
            pendingLog.uniqueKey,
          );

          debugPrint(
            '✅ Pending dose synchronized: '
                '${pendingLog.uniqueKey}',
          );
        } catch (error, stack) {
          debugPrint(
            '⚠️ Pending dose remains queued: '
                '${pendingLog.uniqueKey}: $error',
          );
          debugPrint('$stack');
        }
      }
    } finally {
      _isSynchronizing = false;
    }
  }

  Future<bool> _scheduleBelongsToPatient({
    required String scheduleId,
    required String patientId,
  }) async {
    try {
      final data = await supabase
          .from('medication_schedules')
          .select('id')
          .eq('id', scheduleId)
          .eq('patient_id', patientId)
          .maybeSingle();

      return data != null;
    } catch (error) {
      debugPrint(
        '⚠️ Could not verify pending dose ownership: $error',
      );
      return false;
    }
  }

  Future<void> _uploadPendingLog({
    required _PendingDoseLog pendingLog,
    required String patientId,
  }) async {
    final existing = await supabase
        .from('dose_logs')
        .select('id, status')
        .eq('patient_id', patientId)
        .eq('schedule_id', pendingLog.scheduleId)
        .eq(
      'scheduled_for',
      pendingLog.scheduledFor.toIso8601String(),
    )
        .maybeSingle();

    final existingStatus =
    existing?['status']?.toString();

    await supabase.from('dose_logs').upsert(
      <String, dynamic>{
        'schedule_id': pendingLog.scheduleId,
        'medication_id': pendingLog.medicationId,
        'patient_id': patientId,
        'scheduled_for':
        pendingLog.scheduledFor.toIso8601String(),
        'logged_at':
        pendingLog.loggedAt.toIso8601String(),
        'status': pendingLog.status,
        'notes': pendingLog.notes,
        'confirmed_by': patientId,
      },
      onConflict:
      'patient_id,schedule_id,scheduled_for',
    );

    debugPrint('✅ Dose log saved to Supabase');

    if (pendingLog.status == 'taken' ||
        pendingLog.status == 'late') {
      try {
        await supabase
            .from('medication_schedules')
            .update(
          <String, dynamic>{
            'last_taken_at':
            pendingLog.loggedAt.toIso8601String(),
            'updated_at':
            DateTime.now().toIso8601String(),
          },
        )
            .eq('id', pendingLog.scheduleId)
            .eq('patient_id', patientId);

        debugPrint(
          '✅ Schedule last_taken_at updated',
        );
      } catch (error, stack) {
        debugPrint(
          '⚠️ Dose logged, but schedule metadata update '
              'failed: $error',
        );
        debugPrint('$stack');
      }

      final wasAlreadyTaken =
          existingStatus == 'taken' ||
              existingStatus == 'late';

      if (!wasAlreadyTaken) {
        try {
          await _decrementQuantity(
            medicationId: pendingLog.medicationId,
            patientId: patientId,
          );
        } catch (error, stack) {
          debugPrint(
            '⚠️ Dose logged, but quantity decrement '
                'failed: $error',
          );
          debugPrint('$stack');
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CHECK WHETHER A DOSE IS LOGGED (patient)
  // ══════════════════════════════════════════════════════════════

  Future<bool> isDoseLogged({
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    final pendingLogs = await _readPendingLogs();

    final locallyLogged = pendingLogs.any(
          (log) =>
      log.scheduleId == scheduleId &&
          log.scheduledFor.isAtSameMomentAs(
            scheduledFor,
          ) &&
          (log.status == 'taken' ||
              log.status == 'late'),
    );

    if (locallyLogged) return true;

    final userId =
        AuthService.instance.currentUser?.id;

    if (userId == null) return false;

    try {
      final data = await supabase
          .from('dose_logs')
          .select('id')
          .eq('patient_id', userId)
          .eq('schedule_id', scheduleId)
          .eq(
        'scheduled_for',
        scheduledFor.toIso8601String(),
      )
          .inFilter(
        'status',
        const <String>[
          'taken',
          'late',
        ],
      )
          .limit(1);

      return (data as List).isNotEmpty;
    } catch (error) {
      debugPrint('❌ Failed to check logged dose: $error');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CHECK WHETHER A PATIENT DOSE IS LOGGED (caretaker)
  // ══════════════════════════════════════════════════════════════

  Future<bool> isPatientDoseLogged({
    required String patientId,
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    final safePatientId = patientId.trim();
    final safeScheduleId = scheduleId.trim();

    if (safePatientId.isEmpty ||
        safeScheduleId.isEmpty) {
      return false;
    }

    try {
      final data = await supabase
          .from('dose_logs')
          .select('id')
          .eq('patient_id', safePatientId)
          .eq('schedule_id', safeScheduleId)
          .eq(
        'scheduled_for',
        scheduledFor.toIso8601String(),
      )
          .inFilter(
        'status',
        const <String>[
          'taken',
          'late',
        ],
      )
          .limit(1);

      return (data as List).isNotEmpty;
    } catch (error) {
      debugPrint(
        '❌ Failed to check patient dose log: $error',
      );
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // FETCH LOGGED DOSE KEYS FOR A DATE
  // ══════════════════════════════════════════════════════════════

  Future<Set<String>> getLoggedDoseKeys(
      DateTime date,
      ) async {
    final keys = <String>{};

    final startOfDay = DateTime(
      date.year,
      date.month,
      date.day,
    );

    final endOfDay = startOfDay.add(
      const Duration(days: 1),
    );

    try {
      final pendingLogs = await _readPendingLogs();

      for (final log in pendingLogs) {
        if (log.status != 'taken' &&
            log.status != 'late') {
          continue;
        }

        final localScheduled =
        log.scheduledFor.toLocal();

        if (!localScheduled.isBefore(startOfDay) &&
            localScheduled.isBefore(endOfDay)) {
          keys.add(
            _doseKey(
              scheduleId: log.scheduleId,
              scheduledFor: log.scheduledFor,
            ),
          );
        }
      }
    } catch (error) {
      debugPrint(
        '⚠️ Could not read local dose logs: $error',
      );
    }

    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) return keys;

    try {
      final data = await supabase
          .from('dose_logs')
          .select(
        'schedule_id, scheduled_for, status',
      )
          .eq('patient_id', userId)
          .gte(
        'scheduled_for',
        startOfDay.toIso8601String(),
      )
          .lt(
        'scheduled_for',
        endOfDay.toIso8601String(),
      )
          .inFilter(
        'status',
        const <String>[
          'taken',
          'late',
        ],
      );

      for (final row in data as List) {
        final scheduledFor = DateTime.parse(
          row['scheduled_for'] as String,
        );

        keys.add(
          _doseKey(
            scheduleId:
            row['schedule_id'].toString(),
            scheduledFor: scheduledFor,
          ),
        );
      }
    } catch (error, stack) {
      debugPrint('❌ Failed to fetch logged doses: $error');
      debugPrint('$stack');
    }

    return keys;
  }

  String _doseKey({
    required String scheduleId,
    required DateTime scheduledFor,
  }) {
    final utcTime = scheduledFor.toUtc();

    final formattedTime =
        '${utcTime.year}-'
        '${utcTime.month.toString().padLeft(2, '0')}-'
        '${utcTime.day.toString().padLeft(2, '0')}T'
        '${utcTime.hour.toString().padLeft(2, '0')}:'
        '${utcTime.minute.toString().padLeft(2, '0')}';

    return '$scheduleId|$formattedTime';
  }

  // ══════════════════════════════════════════════════════════════
  // MEDICATION QUANTITY
  // ══════════════════════════════════════════════════════════════

  Future<void> _decrementQuantity({
    required String medicationId,
    required String patientId,
  }) async {
    try {
      final data = await supabase
          .from('medications')
          .select('current_quantity')
          .eq('id', medicationId)
          .eq('patient_id', patientId)
          .maybeSingle();

      if (data == null ||
          data['current_quantity'] == null) {
        return;
      }

      final current =
      (data['current_quantity'] as num).toInt();

      if (current <= 0) return;

      await supabase
          .from('medications')
          .update(
        <String, dynamic>{
          'current_quantity': current - 1,
          'updated_at':
          DateTime.now().toIso8601String(),
        },
      )
          .eq('id', medicationId)
          .eq('patient_id', patientId);

      debugPrint(
        '✅ Medication quantity decremented',
      );
    } catch (error, stack) {
      debugPrint('⚠️ Could not decrement quantity: $error');
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // FETCH COMPLETE HISTORY
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>>
  getDoseHistory() async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

    await syncPendingDoseLogs();

    try {
      final data = await supabase
          .from('dose_history_view')
          .select()
          .eq('patient_id', userId)
          .order(
        'scheduled_for',
        ascending: false,
      );

      return List<Map<String, dynamic>>.from(data);
    } catch (error, stack) {
      debugPrint('❌ Failed to fetch dose history: $error');
      debugPrint('$stack');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>>
  getDoseHistoryForPatient(
      String patientId,
      ) async {
    final caregiverId =
        AuthService.instance.currentUser?.id;

    if (caregiverId == null) {
      throw Exception('Not logged in');
    }

    final safePatientId = patientId.trim();

    if (safePatientId.isEmpty) {
      throw ArgumentError.value(
        patientId,
        'patientId',
        'Patient ID cannot be empty',
      );
    }

    final relationship = await supabase
        .from('care_relationships')
        .select('can_view_logs, status')
        .eq('patient_id', safePatientId)
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .maybeSingle();

    if (relationship == null ||
        relationship['can_view_logs'] != true) {
      throw Exception(
        'You are not permitted to view this patient\'s dose logs.',
      );
    }

    try {
      final data = await supabase
          .from('dose_history_view')
          .select()
          .eq('patient_id', safePatientId)
          .order('scheduled_for', ascending: false);

      debugPrint(
        '✅ Loaded ${data.length} dose-history records '
            'for patient $safePatientId',
      );

      return List<Map<String, dynamic>>.from(data);
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to fetch dose history for patient '
            '$safePatientId: $error',
      );
      debugPrint('$stack');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LOCAL PENDING-LOG STORAGE
  // ══════════════════════════════════════════════════════════════

  Future<void> _storePendingLog(
      _PendingDoseLog newLog,
      ) async {
    final pendingLogs = await _readPendingLogs();

    pendingLogs.removeWhere(
          (existing) =>
      existing.uniqueKey == newLog.uniqueKey,
    );

    pendingLogs.add(newLog);

    await _writePendingLogs(pendingLogs);
  }

  Future<List<_PendingDoseLog>>
  _readPendingLogs() async {
    final preferences =
    await SharedPreferences.getInstance();

    final encoded = preferences.getString(
      _pendingLogsPreferenceKey,
    );

    if (encoded == null || encoded.trim().isEmpty) {
      return <_PendingDoseLog>[];
    }

    try {
      final decoded = jsonDecode(encoded);

      if (decoded is! List) {
        throw const FormatException(
          'Pending dose logs must be a JSON list',
        );
      }

      final logs = <_PendingDoseLog>[];

      for (final value in decoded) {
        if (value is! Map) continue;

        try {
          logs.add(
            _PendingDoseLog.fromJson(
              Map<String, dynamic>.from(value),
            ),
          );
        } catch (error) {
          debugPrint(
            '⚠️ Ignoring malformed pending dose log: $error',
          );
        }
      }

      return logs;
    } catch (error, stack) {
      debugPrint(
        '⚠️ Pending dose-log cache was malformed: $error',
      );
      debugPrint('$stack');

      await preferences.setString(
        '${_pendingLogsPreferenceKey}_corrupt',
        encoded,
      );

      await preferences.remove(
        _pendingLogsPreferenceKey,
      );

      return <_PendingDoseLog>[];
    }
  }

  Future<void> _writePendingLogs(
      List<_PendingDoseLog> logs,
      ) async {
    final preferences =
    await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      logs.map((log) => log.toJson()).toList(),
    );

    final saved = await preferences.setString(
      _pendingLogsPreferenceKey,
      encoded,
    );

    if (!saved) {
      throw StateError(
        'Could not persist the pending dose log',
      );
    }
  }

  Future<void> _removePendingLog(
      String uniqueKey,
      ) async {
    final logs = await _readPendingLogs();

    logs.removeWhere(
          (log) => log.uniqueKey == uniqueKey,
    );

    await _writePendingLogs(logs);
  }

  String? _cleanOptionalString(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }
}

// ══════════════════════════════════════════════════════════════
// LOCALLY PENDING DOSE LOG
// ══════════════════════════════════════════════════════════════

class _PendingDoseLog {
  final String scheduleId;
  final String medicationId;
  final String? patientId;
  final DateTime scheduledFor;
  final DateTime loggedAt;
  final String status;
  final String? notes;

  const _PendingDoseLog({
    required this.scheduleId,
    required this.medicationId,
    required this.patientId,
    required this.scheduledFor,
    required this.loggedAt,
    required this.status,
    this.notes,
  });

  String get uniqueKey {
    return '${patientId ?? "unassigned"}|'
        '$scheduleId|'
        '${scheduledFor.toUtc().toIso8601String()}';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'scheduleId': scheduleId,
      'medicationId': medicationId,
      'patientId': patientId,
      'scheduledFor': scheduledFor.toIso8601String(),
      'loggedAt': loggedAt.toIso8601String(),
      'status': status,
      'notes': notes,
    };
  }

  factory _PendingDoseLog.fromJson(
      Map<String, dynamic> json,
      ) {
    final scheduleId =
        json['scheduleId']?.toString().trim() ?? '';

    final medicationId =
        json['medicationId']?.toString().trim() ?? '';

    final rawScheduledFor =
    json['scheduledFor']?.toString();

    final rawLoggedAt = json['loggedAt']?.toString();

    final status =
        json['status']?.toString().trim() ?? '';

    if (scheduleId.isEmpty ||
        medicationId.isEmpty ||
        rawScheduledFor == null ||
        rawLoggedAt == null ||
        status.isEmpty) {
      throw const FormatException(
        'Pending dose log is incomplete',
      );
    }

    return _PendingDoseLog(
      scheduleId: scheduleId,
      medicationId: medicationId,
      patientId: _optionalStringFromJson(
        json['patientId'],
      ),
      scheduledFor: DateTime.parse(rawScheduledFor),
      loggedAt: DateTime.parse(rawLoggedAt),
      status: status,
      notes: _optionalStringFromJson(json['notes']),
    );
  }

  static String? _optionalStringFromJson(
      dynamic value,
      ) {
    final cleaned = value?.toString().trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }
}