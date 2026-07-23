// lib/services/schedule_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/medication_schedule.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';

/// Single source of truth for a scheduled dose.
class TodayDose {
  final String? patientId;
  final String scheduleId;
  final String medicationId;
  final String medicationName;
  final String genericName;
  final double dosageAmount;
  final String dosageUnit;
  final String? pillColor;
  final String? pillShape;
  final String? pillImageUrl;
  final DateTime scheduledTime;
  final String? notes;
  final bool isPending;

  const TodayDose({
    this.patientId,
    required this.scheduleId,
    required this.medicationId,
    required this.medicationName,
    required this.genericName,
    required this.dosageAmount,
    required this.dosageUnit,
    this.pillColor,
    this.pillShape,
    this.pillImageUrl,
    required this.scheduledTime,
    this.notes,
    this.isPending = false,
  });

  String get dosageDisplay {
    final amount = dosageAmount % 1 == 0
        ? dosageAmount.toInt().toString()
        : dosageAmount.toString();

    return '$amount $dosageUnit';
  }

  bool get isPast => DateTime.now().isAfter(scheduledTime);

  bool get isUpcoming => scheduledTime.isAfter(DateTime.now());

  bool get isDueSoon {
    final difference = scheduledTime.difference(DateTime.now()).inMinutes;
    return difference >= 0 && difference <= 30;
  }
}

class ScheduleService {
  ScheduleService._();

  static final ScheduleService instance = ScheduleService._();

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  String _requireActorId() {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Not logged in');
    }

    return userId;
  }

  String _normalizePatientId(String? patientId, String actorId) {
    final safe = patientId?.trim() ?? '';
    return safe.isEmpty ? actorId : safe;
  }

  Future<void> _assertCanViewPatientSchedules({
    required String actorId,
    required String patientId,
  }) async {
    if (actorId == patientId) return;

    final relationship = await supabase
        .from('care_relationships')
        .select('can_view_medications, status')
        .eq('patient_id', patientId)
        .eq('caregiver_id', actorId)
        .eq('status', 'active')
        .maybeSingle();

    if (relationship == null || relationship['can_view_medications'] != true) {
      throw Exception(
        'You are not permitted to view this patient\'s medication schedule.',
      );
    }
  }

  Future<void> _assertCanEditPatientSchedules({
    required String actorId,
    required String patientId,
  }) async {
    if (actorId == patientId) return;

    final relationship = await supabase
        .from('care_relationships')
        .select('can_edit_medications, status')
        .eq('patient_id', patientId)
        .eq('caregiver_id', actorId)
        .eq('status', 'active')
        .maybeSingle();

    if (relationship == null || relationship['can_edit_medications'] != true) {
      throw Exception(
        'You are not permitted to manage schedules for this patient.',
      );
    }
  }

  bool _shouldScheduleLocalNotifications({
    required String actorId,
    required String patientId,
  }) {
    // Only schedule local device notifications when the patient is
    // creating/updating their own schedule on their own device.
    return actorId == patientId;
  }

  // ══════════════════════════════════════════════════════════════
  // CREATE SCHEDULE AND SET DEVICE ALARMS
  // ══════════════════════════════════════════════════════════════

  Future<MedicationSchedule> addSchedule({
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required String frequencyType,
    String? patientId,
    double? intervalHours,
    double? minHoursBetween,
    List<TimeOfDay>? scheduledTimes,
    List<int>? scheduledDays,
    DateTime? startDate,
    DateTime? endDate,
    bool escalationEnabled = true,
    int escalationStep1Mins = 10,
    int escalationStep2Mins = 20,
    String? pillImageUrl,
  }) async {
    final actorId = _requireActorId();
    final targetPatientId = _normalizePatientId(patientId, actorId);

    await _assertCanEditPatientSchedules(
      actorId: actorId,
      patientId: targetPatientId,
    );

    final safeMedicationId = medicationId.trim();
    final safeMedicationName = medicationName.trim();
    final safeDosageDisplay = dosageDisplay.trim();
    final safeFrequencyType = frequencyType.trim().toLowerCase();

    if (safeMedicationId.isEmpty) {
      throw ArgumentError.value(
        medicationId,
        'medicationId',
        'Medication ID cannot be empty',
      );
    }

    if (safeMedicationName.isEmpty) {
      throw ArgumentError.value(
        medicationName,
        'medicationName',
        'Medication name cannot be empty',
      );
    }

    final effectiveScheduledTimes =
    safeFrequencyType == 'daily' || safeFrequencyType == 'multiple_daily'
        ? scheduledTimes
        : null;

    final effectiveIntervalHours =
    safeFrequencyType == 'every_x_hours' ? intervalHours : null;

    final resolvedPillImageUrl = await _resolvePillImageUrl(
      medicationId: safeMedicationId,
      patientId: targetPatientId,
      suppliedImageUrl: pillImageUrl,
    );

    final timesArray = effectiveScheduledTimes
        ?.map(
          (time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}:00',
    )
        .toList();

    final effectiveStartDate = startDate ?? DateTime.now();

    final nextScheduled = _computeNextScheduled(
      frequencyType: safeFrequencyType,
      scheduledTimes: effectiveScheduledTimes,
      intervalHours: effectiveIntervalHours,
      startDate: effectiveStartDate,
    );

    try {
      final data = await supabase
          .from('medication_schedules')
          .insert(
        <String, dynamic>{
          'medication_id': safeMedicationId,
          'patient_id': targetPatientId,
          'frequency_type': safeFrequencyType,
          'interval_hours': effectiveIntervalHours,
          'min_hours_between': minHoursBetween,
          'scheduled_times': timesArray,
          'scheduled_days': scheduledDays,
          'start_date':
          effectiveStartDate.toIso8601String().split('T').first,
          'end_date': endDate?.toIso8601String().split('T').first,
          'next_scheduled_at': nextScheduled?.toIso8601String(),
          'escalation_enabled': escalationEnabled,
          'escalation_step1_mins': escalationStep1Mins,
          'escalation_step2_mins': escalationStep2Mins,
          'is_active': true,
        },
      )
          .select()
          .single();

      final schedule = MedicationSchedule.fromJson(
        Map<String, dynamic>.from(data as Map),
      );

      _log(
        '✅ Supabase schedule saved: ${schedule.id} for patient: $targetPatientId',
      );

      final canScheduleLocalAlarms = _shouldScheduleLocalNotifications(
        actorId: actorId,
        patientId: targetPatientId,
      ) &&
          safeFrequencyType != 'as_needed' &&
          effectiveScheduledTimes != null &&
          effectiveScheduledTimes.isNotEmpty;

      if (canScheduleLocalAlarms) {
        final futureTimes = _buildFutureDateTimes(
          scheduledTimes: effectiveScheduledTimes,
          startDate: effectiveStartDate,
          endDate: endDate,
          scheduledDays: scheduledDays,
        );

        var alarmCount = 0;

        for (final scheduledTime in futureTimes) {
          await LocalNotificationService.instance.scheduleForDose(
            patientId: targetPatientId,
            scheduleId: schedule.id,
            medicationId: safeMedicationId,
            medicationName: safeMedicationName,
            dosageDisplay: safeDosageDisplay,
            scheduledFor: scheduledTime,
            pillImageUrl: resolvedPillImageUrl,
            escalationStep1Mins: escalationStep1Mins,
            escalationStep2Mins: escalationStep2Mins,
          );

          alarmCount++;
        }

        _log('🔔 Scheduled $alarmCount local alarms');
      } else {
        _log(
          'ℹ️ Skipping local device alarms because actor is not the patient '
              'or schedule has no fixed times.',
        );
      }

      return schedule;
    } catch (error, stack) {
      _log('❌ Failed to save schedule: $error');
      _log('$stack');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // UPDATE SCHEDULE AND SYNC DEVICE ALARMS
  // ══════════════════════════════════════════════════════════════

  Future<MedicationSchedule> updateSchedule({
    required String id,
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required String frequencyType,
    String? patientId,
    double? intervalHours,
    double? minHoursBetween,
    List<TimeOfDay>? scheduledTimes,
    List<int>? scheduledDays,
    DateTime? startDate,
    DateTime? endDate,
    bool escalationEnabled = true,
    int escalationStep1Mins = 10,
    int escalationStep2Mins = 20,
    String? pillImageUrl,
  }) async {
    final actorId = _requireActorId();
    final targetPatientId = _normalizePatientId(patientId, actorId);

    await _assertCanEditPatientSchedules(
      actorId: actorId,
      patientId: targetPatientId,
    );

    final safeScheduleId = id.trim();
    final safeMedicationId = medicationId.trim();
    final safeMedicationName = medicationName.trim();
    final safeDosageDisplay = dosageDisplay.trim();
    final safeFrequencyType = frequencyType.trim().toLowerCase();

    if (safeScheduleId.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
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

    if (safeMedicationName.isEmpty) {
      throw ArgumentError.value(
        medicationName,
        'medicationName',
        'Medication name cannot be empty',
      );
    }

    final existingSchedule = await _getActiveScheduleById(
      id: safeScheduleId,
      patientId: targetPatientId,
    );

    if (existingSchedule == null) {
      throw Exception('Schedule not found');
    }

    final effectiveScheduledTimes =
    safeFrequencyType == 'daily' || safeFrequencyType == 'multiple_daily'
        ? scheduledTimes
        : null;

    final effectiveIntervalHours =
    safeFrequencyType == 'every_x_hours' ? intervalHours : null;

    final effectiveMinHoursBetween =
        minHoursBetween ?? existingSchedule.minHoursBetween;

    // Preserve existing start/end dates when update callers do not provide them.
    // This prevents ordinary schedule edits from unintentionally resetting dates.
    final effectiveStartDate = startDate ?? existingSchedule.startDate;
    final effectiveEndDate = endDate ?? existingSchedule.endDate;

    final hasChanged = _hasScheduleChanged(
      existing: existingSchedule,
      medicationId: safeMedicationId,
      frequencyType: safeFrequencyType,
      intervalHours: effectiveIntervalHours,
      minHoursBetween: effectiveMinHoursBetween,
      scheduledTimes: effectiveScheduledTimes,
      scheduledDays: scheduledDays,
      startDate: effectiveStartDate,
      endDate: effectiveEndDate,
      escalationEnabled: escalationEnabled,
      escalationStep1Mins: escalationStep1Mins,
      escalationStep2Mins: escalationStep2Mins,
    );

    if (!hasChanged) {
      _log(
        'ℹ️ No schedule changes detected for $safeScheduleId. '
            'Skipping Supabase update and alarm reschedule.',
      );
      return existingSchedule;
    }

    final resolvedPillImageUrl = await _resolvePillImageUrl(
      medicationId: safeMedicationId,
      patientId: targetPatientId,
      suppliedImageUrl: pillImageUrl,
    );

    final timesArray = effectiveScheduledTimes
        ?.map(
          (time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}:00',
    )
        .toList();

    final nextScheduled = _computeNextScheduled(
      frequencyType: safeFrequencyType,
      scheduledTimes: effectiveScheduledTimes,
      intervalHours: effectiveIntervalHours,
      startDate: effectiveStartDate,
    );

    try {
      final data = await supabase
          .from('medication_schedules')
          .update(
        <String, dynamic>{
          'medication_id': safeMedicationId,
          'patient_id': targetPatientId,
          'frequency_type': safeFrequencyType,
          'interval_hours': effectiveIntervalHours,
          'min_hours_between': effectiveMinHoursBetween,
          'scheduled_times': timesArray,
          'scheduled_days': scheduledDays,
          'start_date':
          effectiveStartDate.toIso8601String().split('T').first,
          'end_date': effectiveEndDate?.toIso8601String().split('T').first,
          'next_scheduled_at': nextScheduled?.toIso8601String(),
          'escalation_enabled': escalationEnabled,
          'escalation_step1_mins': escalationStep1Mins,
          'escalation_step2_mins': escalationStep2Mins,
          'updated_at': DateTime.now().toIso8601String(),
        },
      )
          .eq('id', safeScheduleId)
          .eq('patient_id', targetPatientId)
          .select()
          .single();

      final updatedSchedule = MedicationSchedule.fromJson(
        Map<String, dynamic>.from(data as Map),
      );

      _log(
        '✅ Supabase schedule updated: ${updatedSchedule.id} '
            'for patient: $targetPatientId',
      );

      if (_shouldScheduleLocalNotifications(
        actorId: actorId,
        patientId: targetPatientId,
      )) {
        await _syncLocalNotificationsForUpdatedSchedule(
          oldSchedule: existingSchedule,
          newSchedule: updatedSchedule,
          medicationId: safeMedicationId,
          medicationName: safeMedicationName,
          dosageDisplay: safeDosageDisplay,
          pillImageUrl: resolvedPillImageUrl,
          escalationStep1Mins: escalationStep1Mins,
          escalationStep2Mins: escalationStep2Mins,
        );
      } else {
        _log(
          'ℹ️ Skipping local device alarms because actor is not the patient.',
        );
      }

      return updatedSchedule;
    } catch (error, stack) {
      _log('❌ Failed to update schedule: $error');
      _log('$stack');
      rethrow;
    }
  }

  Future<MedicationSchedule?> _getActiveScheduleById({
    required String id,
    required String patientId,
  }) async {
    final data = await supabase
        .from('medication_schedules')
        .select()
        .eq('id', id)
        .eq('patient_id', patientId)
        .eq('is_active', true)
        .maybeSingle();

    if (data == null) return null;

    return MedicationSchedule.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  bool _hasScheduleChanged({
    required MedicationSchedule existing,
    required String medicationId,
    required String frequencyType,
    required double? intervalHours,
    required double? minHoursBetween,
    required List<TimeOfDay>? scheduledTimes,
    required List<int>? scheduledDays,
    required DateTime startDate,
    required DateTime? endDate,
    required bool escalationEnabled,
    required int escalationStep1Mins,
    required int escalationStep2Mins,
  }) {
    if (existing.medicationId != medicationId) return true;
    if (existing.frequencyType != frequencyType) return true;

    if (!_sameNullableDouble(existing.intervalHours, intervalHours)) {
      return true;
    }

    if (!_sameNullableDouble(existing.minHoursBetween, minHoursBetween)) {
      return true;
    }

    if (!_sameTimeLists(existing.scheduledTimes, scheduledTimes)) {
      return true;
    }

    if (!_sameDayLists(existing.scheduledDays, scheduledDays)) {
      return true;
    }

    if (!_sameDateOnly(existing.startDate, startDate)) {
      return true;
    }

    if (!_sameNullableDateOnly(existing.endDate, endDate)) {
      return true;
    }

    if (existing.escalationEnabled != escalationEnabled) return true;
    if (existing.escalationStep1Mins != escalationStep1Mins) return true;
    if (existing.escalationStep2Mins != escalationStep2Mins) return true;

    return false;
  }

  Future<void> _syncLocalNotificationsForUpdatedSchedule({
    required MedicationSchedule oldSchedule,
    required MedicationSchedule newSchedule,
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required String? pillImageUrl,
    required int escalationStep1Mins,
    required int escalationStep2Mins,
  }) async {
    final oldFutureTimes = _buildFutureDateTimesForSchedule(oldSchedule);
    final newFutureTimes = _buildFutureDateTimesForSchedule(newSchedule);

    final oldMap = <int, DateTime>{
      for (final time in oldFutureTimes) time.millisecondsSinceEpoch: time,
    };

    final newMap = <int, DateTime>{
      for (final time in newFutureTimes) time.millisecondsSinceEpoch: time,
    };

    final oldKeys = oldMap.keys.toSet();
    final newKeys = newMap.keys.toSet();

    final removedKeys = oldKeys.difference(newKeys);
    final addedKeys = newKeys.difference(oldKeys);

    var cancelledCount = 0;
    var scheduledCount = 0;

    for (final key in removedKeys) {
      final scheduledFor = oldMap[key];
      if (scheduledFor == null) continue;

      await LocalNotificationService.instance.cancelDose(
        scheduleId: oldSchedule.id,
        scheduledFor: scheduledFor,
      );

      cancelledCount++;
    }

    for (final key in addedKeys) {
      final scheduledFor = newMap[key];
      if (scheduledFor == null) continue;

      await LocalNotificationService.instance.scheduleForDose(
        patientId: newSchedule.patientId,
        scheduleId: newSchedule.id,
        medicationId: medicationId,
        medicationName: medicationName,
        dosageDisplay: dosageDisplay,
        scheduledFor: scheduledFor,
        pillImageUrl: pillImageUrl,
        escalationStep1Mins: escalationStep1Mins,
        escalationStep2Mins: escalationStep2Mins,
      );

      scheduledCount++;
    }

    _log(
      '🔔 Local alarms synced for ${newSchedule.id}: '
          '$cancelledCount cancelled, $scheduledCount scheduled, '
          '${newKeys.intersection(oldKeys).length} unchanged',
    );
  }

  static List<DateTime> _buildFutureDateTimesForSchedule(
      MedicationSchedule schedule,
      ) {
    if (schedule.frequencyType == 'as_needed') {
      return <DateTime>[];
    }

    if (schedule.frequencyType != 'daily' &&
        schedule.frequencyType != 'multiple_daily') {
      return <DateTime>[];
    }

    final times = schedule.scheduledTimes;

    if (times == null || times.isEmpty) {
      return <DateTime>[];
    }

    return _buildFutureDateTimes(
      scheduledTimes: times,
      startDate: schedule.startDate,
      endDate: schedule.endDate,
      scheduledDays: schedule.scheduledDays,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // READ SCHEDULES
  // ══════════════════════════════════════════════════════════════

  Future<List<MedicationSchedule>> getMySchedules() async {
    final userId = _requireActorId();

    final data = await supabase
        .from('medication_schedules')
        .select()
        .eq('patient_id', userId)
        .eq('is_active', true)
        .order('next_scheduled_at', ascending: true);

    return (data as List)
        .map(
          (json) => MedicationSchedule.fromJson(
        Map<String, dynamic>.from(json as Map),
      ),
    )
        .toList();
  }

  Future<List<MedicationSchedule>> getSchedulesForMedication(
      String medicationId, {
        String? patientId,
      }) async {
    final actorId = _requireActorId();
    final targetPatientId = _normalizePatientId(patientId, actorId);
    final safeMedicationId = medicationId.trim();

    if (safeMedicationId.isEmpty) {
      throw ArgumentError.value(
        medicationId,
        'medicationId',
        'Medication ID cannot be empty',
      );
    }

    await _assertCanViewPatientSchedules(
      actorId: actorId,
      patientId: targetPatientId,
    );

    final data = await supabase
        .from('medication_schedules')
        .select()
        .eq('patient_id', targetPatientId)
        .eq('medication_id', safeMedicationId)
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return (data as List)
        .map(
          (json) => MedicationSchedule.fromJson(
        Map<String, dynamic>.from(json as Map),
      ),
    )
        .toList();
  }

  // ══════════════════════════════════════════════════════════════
  // DELETE SCHEDULE
  // ══════════════════════════════════════════════════════════════

  Future<void> deleteSchedule(
      String id, {
        String? patientId,
      }) async {
    final actorId = _requireActorId();
    final targetPatientId = _normalizePatientId(patientId, actorId);
    final scheduleId = id.trim();

    await _assertCanEditPatientSchedules(
      actorId: actorId,
      patientId: targetPatientId,
    );

    await supabase
        .from('medication_schedules')
        .update(
      <String, dynamic>{
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      },
    )
        .eq('id', scheduleId)
        .eq('patient_id', targetPatientId);

    if (_shouldScheduleLocalNotifications(
      actorId: actorId,
      patientId: targetPatientId,
    )) {
      await LocalNotificationService.instance.cancelSchedule(scheduleId);
    }

    _log('🗑️ Deleted schedule $scheduleId');
  }

  // ══════════════════════════════════════════════════════════════
  // GET DOSES FOR THE LOGGED-IN PATIENT
  // ══════════════════════════════════════════════════════════════

  Future<List<TodayDose>> getDosesForDate(DateTime date) async {
    final userId = _requireActorId();

    return _buildDosesForDate(
      patientId: userId,
      date: date,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // GET DOSES FOR ONE PATIENT — CARETAKER VIEW
  // ══════════════════════════════════════════════════════════════

  Future<List<TodayDose>> getDosesForPatient({
    required String patientId,
    required DateTime date,
  }) async {
    final actorId = _requireActorId();
    final safePatientId = patientId.trim();

    if (safePatientId.isEmpty) {
      throw ArgumentError.value(
        patientId,
        'patientId',
        'Patient ID cannot be empty',
      );
    }

    await _assertCanViewPatientSchedules(
      actorId: actorId,
      patientId: safePatientId,
    );

    return _buildDosesForDate(
      patientId: safePatientId,
      date: date,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SHARED DOSE BUILDER
  // ══════════════════════════════════════════════════════════════

  Future<List<TodayDose>> _buildDosesForDate({
    required String patientId,
    required DateTime date,
  }) async {
    final dateString = date.toIso8601String().split('T').first;

    _log('📅 Loading doses for $dateString (patient: $patientId)');

    try {
      final data = await supabase
          .from('medication_schedules')
          .select(
        '*, medications(id, brand_name, generic_name, dosage_amount, dosage_unit, pill_color, pill_shape, pill_image_url, notes)',
      )
          .eq('patient_id', patientId)
          .eq('is_active', true)
          .lte('start_date', dateString);

      final doses = <TodayDose>[];

      final weekdayIndex = date.weekday % 7;

      for (final rawRow in data as List) {
        final schedule = Map<String, dynamic>.from(rawRow as Map);

        Map<String, dynamic>? medication;
        final rawMedication = schedule['medications'];

        if (rawMedication is Map) {
          medication = Map<String, dynamic>.from(rawMedication);
        } else if (rawMedication is List &&
            rawMedication.isNotEmpty &&
            rawMedication.first is Map) {
          medication = Map<String, dynamic>.from(rawMedication.first as Map);
        }

        if (medication == null) {
          _log(
            '⚠️ Skipping schedule ${schedule['id']} because medication relation is missing.',
          );
          continue;
        }

        if (schedule['end_date'] != null) {
          final scheduleEndDate =
          DateTime.parse(schedule['end_date'].toString());

          final selectedDay = DateTime(
            date.year,
            date.month,
            date.day,
          );

          final normalizedEndDate = DateTime(
            scheduleEndDate.year,
            scheduleEndDate.month,
            scheduleEndDate.day,
          );

          if (selectedDay.isAfter(normalizedEndDate)) {
            continue;
          }
        }

        if (schedule['frequency_type'] == 'as_needed') {
          continue;
        }

        final scheduledDays = schedule['scheduled_days'] as List?;

        if (scheduledDays != null &&
            scheduledDays.isNotEmpty &&
            !scheduledDays.contains(weekdayIndex)) {
          continue;
        }

        final scheduledTimes = schedule['scheduled_times'] as List?;

        if (scheduledTimes == null || scheduledTimes.isEmpty) {
          continue;
        }

        for (final rawTime in scheduledTimes) {
          final parts = rawTime.toString().split(':');
          if (parts.length < 2) continue;

          final hour = int.tryParse(parts[0]);
          final minute = int.tryParse(parts[1]);

          if (hour == null || minute == null) continue;

          final doseTime = DateTime(
            date.year,
            date.month,
            date.day,
            hour,
            minute,
          );

          final genericName =
              medication['generic_name']?.toString().trim() ?? 'Medication';

          final brandName = medication['brand_name']?.toString().trim();

          final medicationName =
          brandName != null && brandName.isNotEmpty
              ? brandName
              : genericName;

          doses.add(
            TodayDose(
              patientId: patientId,
              scheduleId: schedule['id'].toString(),
              medicationId: medication['id'].toString(),
              medicationName: medicationName,
              genericName: genericName,
              dosageAmount:
              ((medication['dosage_amount'] as num?) ?? 0).toDouble(),
              dosageUnit: medication['dosage_unit']?.toString() ?? '',
              pillColor: medication['pill_color']?.toString(),
              pillShape: medication['pill_shape']?.toString(),
              pillImageUrl: _cleanOptionalString(
                medication['pill_image_url']?.toString(),
              ),
              scheduledTime: doseTime,
              notes: medication['notes']?.toString(),
            ),
          );
        }
      }

      doses.sort(
            (first, second) => first.scheduledTime.compareTo(
          second.scheduledTime,
        ),
      );

      _log('✅ Loaded ${doses.length} doses for $dateString');

      return doses;
    } catch (error, stack) {
      _log('❌ Failed to load doses: $error');
      _log('$stack');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PILL IMAGE LOOKUP
  // ══════════════════════════════════════════════════════════════

  Future<String?> _resolvePillImageUrl({
    required String medicationId,
    required String patientId,
    String? suppliedImageUrl,
  }) async {
    final supplied = _cleanOptionalString(suppliedImageUrl);
    if (supplied != null) return supplied;

    try {
      final data = await supabase
          .from('medications')
          .select('pill_image_url')
          .eq('id', medicationId)
          .eq('patient_id', patientId)
          .maybeSingle();

      return _cleanOptionalString(data?['pill_image_url']?.toString());
    } catch (error, stack) {
      _log('⚠️ Could not load pill image for alarm payload: $error');
      _log('$stack');
      return null;
    }
  }

  static String? _cleanOptionalString(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) return null;

    return cleaned;
  }

  // ══════════════════════════════════════════════════════════════
  // COMPARISON HELPERS
  // ══════════════════════════════════════════════════════════════

  static bool _sameNullableDouble(double? first, double? second) {
    if (first == null && second == null) return true;
    if (first == null || second == null) return false;

    return (first - second).abs() < 0.000001;
  }

  static bool _sameDateOnly(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  static bool _sameNullableDateOnly(DateTime? first, DateTime? second) {
    if (first == null && second == null) return true;
    if (first == null || second == null) return false;

    return _sameDateOnly(first, second);
  }

  static bool _sameTimeLists(
      List<TimeOfDay>? first,
      List<TimeOfDay>? second,
      ) {
    final a = _normalizedTimeMinutes(first);
    final b = _normalizedTimeMinutes(second);

    if (a.length != b.length) return false;

    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }

    return true;
  }

  static List<int> _normalizedTimeMinutes(List<TimeOfDay>? times) {
    final values = (times ?? <TimeOfDay>[])
        .map((time) => time.hour * 60 + time.minute)
        .toSet()
        .toList()
      ..sort();

    return values;
  }

  static bool _sameDayLists(
      List<int>? first,
      List<int>? second,
      ) {
    final a = _normalizedScheduledDays(first);
    final b = _normalizedScheduledDays(second);

    if (a.length != b.length) return false;

    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }

    return true;
  }

  static List<int> _normalizedScheduledDays(List<int>? days) {
    if (days == null || days.isEmpty) {
      return <int>[0, 1, 2, 3, 4, 5, 6];
    }

    final values = days
        .where((day) => day >= 0 && day <= 6)
        .toSet()
        .toList()
      ..sort();

    if (values.length == 7) {
      return <int>[0, 1, 2, 3, 4, 5, 6];
    }

    return values;
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULING HELPERS
  // ══════════════════════════════════════════════════════════════

  static DateTime? _computeNextScheduled({
    required String frequencyType,
    List<TimeOfDay>? scheduledTimes,
    double? intervalHours,
    required DateTime startDate,
  }) {
    final now = DateTime.now();

    switch (frequencyType) {
      case 'daily':
      case 'multiple_daily':
        if (scheduledTimes == null || scheduledTimes.isEmpty) {
          return null;
        }

        final orderedTimes = List<TimeOfDay>.from(scheduledTimes)
          ..sort((first, second) {
            final firstMinutes = first.hour * 60 + first.minute;
            final secondMinutes = second.hour * 60 + second.minute;
            return firstMinutes.compareTo(secondMinutes);
          });

        for (final time in orderedTimes) {
          final candidate = DateTime(
            now.year,
            now.month,
            now.day,
            time.hour,
            time.minute,
          );

          if (candidate.isAfter(now)) {
            return candidate;
          }
        }

        final first = orderedTimes.first;

        return DateTime(
          now.year,
          now.month,
          now.day + 1,
          first.hour,
          first.minute,
        );

      case 'every_x_hours':
        if (intervalHours == null || intervalHours <= 0) {
          return null;
        }

        return now.add(
          Duration(
            minutes: (intervalHours * 60).round(),
          ),
        );

      case 'as_needed':
      default:
        return null;
    }
  }

  static List<DateTime> _buildFutureDateTimes({
    required List<TimeOfDay> scheduledTimes,
    required DateTime startDate,
    DateTime? endDate,
    List<int>? scheduledDays,
    int daysAhead = 30,
  }) {
    final result = <DateTime>[];
    final now = DateTime.now();

    final defaultLimit = now.add(
      Duration(days: daysAhead),
    );

    final limit =
    endDate != null && endDate.isBefore(defaultLimit) ? endDate : defaultLimit;

    var cursor = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );

    final normalizedLimit = DateTime(
      limit.year,
      limit.month,
      limit.day,
      23,
      59,
      59,
    );

    while (!cursor.isAfter(normalizedLimit)) {
      final weekdayIndex = cursor.weekday % 7;

      final dayAllowed = scheduledDays == null ||
          scheduledDays.isEmpty ||
          scheduledDays.contains(weekdayIndex);

      if (dayAllowed) {
        for (final time in scheduledTimes) {
          final scheduledDateTime = DateTime(
            cursor.year,
            cursor.month,
            cursor.day,
            time.hour,
            time.minute,
          );

          if (scheduledDateTime.isAfter(now) &&
              !scheduledDateTime.isAfter(normalizedLimit)) {
            result.add(scheduledDateTime);
          }
        }
      }

      cursor = cursor.add(
        const Duration(days: 1),
      );
    }

    result.sort();

    return result;
  }
}