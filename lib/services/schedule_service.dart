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

  bool get isPast {
    return DateTime.now().isAfter(scheduledTime);
  }

  bool get isUpcoming {
    return scheduledTime.isAfter(DateTime.now());
  }

  bool get isDueSoon {
    final difference =
        scheduledTime.difference(DateTime.now()).inMinutes;

    return difference >= 0 && difference <= 30;
  }
}

class ScheduleService {
  ScheduleService._();

  static final ScheduleService instance =
  ScheduleService._();

  // ══════════════════════════════════════════════════════════════
  // CREATE SCHEDULE AND SET DEVICE ALARMS
  // ══════════════════════════════════════════════════════════════

  Future<MedicationSchedule> addSchedule({
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required String frequencyType,
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
    final userId =
        AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception(
        'You must be logged in to create a schedule',
      );
    }

    final safeMedicationId = medicationId.trim();
    final safeMedicationName = medicationName.trim();
    final safeDosageDisplay = dosageDisplay.trim();
    final safeFrequencyType =
    frequencyType.trim().toLowerCase();

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

    final resolvedPillImageUrl =
    await _resolvePillImageUrl(
      medicationId: safeMedicationId,
      patientId: userId,
      suppliedImageUrl: pillImageUrl,
    );

    final timesArray = scheduledTimes
        ?.map(
          (time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}:00',
    )
        .toList();

    final effectiveStartDate =
        startDate ?? DateTime.now();

    final nextScheduled = _computeNextScheduled(
      frequencyType: safeFrequencyType,
      scheduledTimes: scheduledTimes,
      intervalHours: intervalHours,
      startDate: effectiveStartDate,
    );

    try {
      final data = await supabase
          .from('medication_schedules')
          .insert(
        <String, dynamic>{
          'medication_id': safeMedicationId,
          'patient_id': userId,
          'frequency_type': safeFrequencyType,
          'interval_hours': intervalHours,
          'min_hours_between': minHoursBetween,
          'scheduled_times': timesArray,
          'scheduled_days': scheduledDays,
          'start_date': effectiveStartDate
              .toIso8601String()
              .split('T')
              .first,
          'end_date': endDate
              ?.toIso8601String()
              .split('T')
              .first,
          'next_scheduled_at':
          nextScheduled?.toIso8601String(),
          'escalation_enabled': escalationEnabled,
          'escalation_step1_mins': escalationStep1Mins,
          'escalation_step2_mins': escalationStep2Mins,
          'is_active': true,
        },
      ).select().single();

      final schedule =
      MedicationSchedule.fromJson(data);

      debugPrint(
        '✅ Supabase schedule saved: ${schedule.id}',
      );

      if (safeFrequencyType != 'as_needed' &&
          scheduledTimes != null &&
          scheduledTimes.isNotEmpty) {
        final futureTimes = _buildFutureDateTimes(
          scheduledTimes: scheduledTimes,
          startDate: effectiveStartDate,
          endDate: endDate,
          scheduledDays: scheduledDays,
        );

        var alarmCount = 0;

        for (final scheduledTime in futureTimes) {
          await LocalNotificationService.instance
              .scheduleForDose(
            patientId: userId,
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

        debugPrint(
          '🔔 Scheduled $alarmCount local alarms '
              'with pill image payload',
        );
      }

      return schedule;
    } catch (error, stack) {
      debugPrint('❌ Failed to save schedule: $error');
      debugPrint('$stack');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // UPDATE SCHEDULE AND RESET DEVICE ALARMS
  // ══════════════════════════════════════════════════════════════

  Future<MedicationSchedule> updateSchedule({
    required String id,
    required String medicationId,
    required String medicationName,
    required String dosageDisplay,
    required String frequencyType,
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
    final userId =
        AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception(
        'You must be logged in to update a schedule',
      );
    }

    final safeScheduleId = id.trim();
    final safeMedicationId = medicationId.trim();
    final safeMedicationName = medicationName.trim();
    final safeDosageDisplay = dosageDisplay.trim();
    final safeFrequencyType =
    frequencyType.trim().toLowerCase();

    if (safeScheduleId.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Schedule ID cannot be empty',
      );
    }

    final resolvedPillImageUrl =
    await _resolvePillImageUrl(
      medicationId: safeMedicationId,
      patientId: userId,
      suppliedImageUrl: pillImageUrl,
    );

    final timesArray = scheduledTimes
        ?.map(
          (time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}:00',
    )
        .toList();

    final effectiveStartDate =
        startDate ?? DateTime.now();

    final nextScheduled = _computeNextScheduled(
      frequencyType: safeFrequencyType,
      scheduledTimes: scheduledTimes,
      intervalHours: intervalHours,
      startDate: effectiveStartDate,
    );

    try {
      await LocalNotificationService.instance
          .cancelSchedule(safeScheduleId);

      debugPrint(
        '🔕 Cancelled old alarms for schedule '
            '$safeScheduleId',
      );

      final data = await supabase
          .from('medication_schedules')
          .update(
        <String, dynamic>{
          'medication_id': safeMedicationId,
          'frequency_type': safeFrequencyType,
          'interval_hours': intervalHours,
          'min_hours_between': minHoursBetween,
          'scheduled_times': timesArray,
          'scheduled_days': scheduledDays,
          'start_date': effectiveStartDate
              .toIso8601String()
              .split('T')
              .first,
          'end_date': endDate
              ?.toIso8601String()
              .split('T')
              .first,
          'next_scheduled_at':
          nextScheduled?.toIso8601String(),
          'escalation_enabled': escalationEnabled,
          'escalation_step1_mins': escalationStep1Mins,
          'escalation_step2_mins': escalationStep2Mins,
          'updated_at': DateTime.now().toIso8601String(),
        },
      )
          .eq('id', safeScheduleId)
          .eq('patient_id', userId)
          .select()
          .single();

      final schedule =
      MedicationSchedule.fromJson(data);

      debugPrint(
        '✅ Supabase schedule updated: ${schedule.id}',
      );

      if (safeFrequencyType != 'as_needed' &&
          scheduledTimes != null &&
          scheduledTimes.isNotEmpty) {
        final futureTimes = _buildFutureDateTimes(
          scheduledTimes: scheduledTimes,
          startDate: effectiveStartDate,
          endDate: endDate,
          scheduledDays: scheduledDays,
        );

        var alarmCount = 0;

        for (final scheduledTime in futureTimes) {
          await LocalNotificationService.instance
              .scheduleForDose(
            patientId: userId,
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

        debugPrint(
          '🔔 Re-scheduled $alarmCount alarms '
              'with pill image payload',
        );
      }

      return schedule;
    } catch (error, stack) {
      debugPrint('❌ Failed to update schedule: $error');
      debugPrint('$stack');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // READ SCHEDULES
  // ══════════════════════════════════════════════════════════════

  Future<List<MedicationSchedule>> getMySchedules() async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

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

  Future<List<MedicationSchedule>>
  getSchedulesForMedication(
      String medicationId,
      ) async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

    final data = await supabase
        .from('medication_schedules')
        .select()
        .eq('patient_id', userId)
        .eq('medication_id', medicationId)
        .eq('is_active', true);

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

  Future<void> deleteSchedule(String id) async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

    final scheduleId = id.trim();

    await supabase
        .from('medication_schedules')
        .update(
      <String, dynamic>{
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      },
    )
        .eq('id', scheduleId)
        .eq('patient_id', userId);

    await LocalNotificationService.instance
        .cancelSchedule(scheduleId);

    debugPrint('🗑️ Deleted schedule $scheduleId');
  }

  // ══════════════════════════════════════════════════════════════
  // GET DOSES FOR THE LOGGED-IN PATIENT
  // ══════════════════════════════════════════════════════════════

  Future<List<TodayDose>> getDosesForDate(
      DateTime date,
      ) async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

    return _buildDosesForDate(
      patientId: userId,
      date: date,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // GET DOSES FOR ONE PATIENT — CARETAKER VIEW
  //
  // Used by the caretaker medication-alert flow. Verifies the active
  // relationship and can_view_medications permission before loading.
  // ══════════════════════════════════════════════════════════════

  Future<List<TodayDose>> getDosesForPatient({
    required String patientId,
    required DateTime date,
  }) async {
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
        .select('can_view_medications, status')
        .eq('patient_id', safePatientId)
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .maybeSingle();

    if (relationship == null ||
        relationship['can_view_medications'] != true) {
      throw Exception(
        'You are not permitted to view this patient\'s '
            'medication schedule.',
      );
    }

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
    final dateString =
        date.toIso8601String().split('T').first;

    debugPrint(
      '📅 Loading doses for $dateString '
          '(patient: $patientId)',
    );

    try {
      final data = await supabase
          .from('medication_schedules')
          .select(
        '*, medications!inner(pill_image_url, *)',
      )
          .eq('patient_id', patientId)
          .eq('is_active', true)
          .lte('start_date', dateString);

      final doses = <TodayDose>[];

      /*
       * scheduled_days uses 0 = Sunday in this app.
       * Dart weekday gives Monday = 1 … Sunday = 7, so normalize
       * Sunday to 0 before comparing.
       */
      final weekdayIndex = date.weekday % 7;

      for (final rawRow in data as List) {
        final schedule = Map<String, dynamic>.from(
          rawRow as Map,
        );

        final medication = Map<String, dynamic>.from(
          schedule['medications'] as Map,
        );

        if (schedule['end_date'] != null) {
          final scheduleEndDate = DateTime.parse(
            schedule['end_date'].toString(),
          );

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

        final scheduledDays =
        schedule['scheduled_days'] as List?;

        if (scheduledDays != null &&
            scheduledDays.isNotEmpty &&
            !scheduledDays.contains(weekdayIndex)) {
          continue;
        }

        final scheduledTimes =
        schedule['scheduled_times'] as List?;

        if (scheduledTimes == null ||
            scheduledTimes.isEmpty) {
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
              medication['generic_name']
                  ?.toString()
                  .trim() ??
                  'Medication';

          final brandName =
          medication['brand_name']?.toString().trim();

          final medicationName = brandName != null &&
              brandName.isNotEmpty
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
              (medication['dosage_amount'] as num)
                  .toDouble(),
              dosageUnit:
              medication['dosage_unit'].toString(),
              pillColor:
              medication['pill_color']?.toString(),
              pillShape:
              medication['pill_shape']?.toString(),
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

      debugPrint(
        '✅ Loaded ${doses.length} doses for $dateString',
      );

      return doses;
    } catch (error, stack) {
      debugPrint('❌ Failed to load doses: $error');
      debugPrint('$stack');
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

    if (supplied != null) {
      return supplied;
    }

    try {
      final data = await supabase
          .from('medications')
          .select('pill_image_url')
          .eq('id', medicationId)
          .eq('patient_id', patientId)
          .maybeSingle();

      final imageUrl = _cleanOptionalString(
        data?['pill_image_url']?.toString(),
      );

      return imageUrl;
    } catch (error, stack) {
      debugPrint(
        '⚠️ Could not load pill image for alarm payload: '
            '$error',
      );
      debugPrint('$stack');
      return null;
    }
  }

  static String? _cleanOptionalString(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
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
        if (scheduledTimes == null ||
            scheduledTimes.isEmpty) {
          return null;
        }

        final orderedTimes =
        List<TimeOfDay>.from(scheduledTimes)
          ..sort(
                (first, second) {
              final firstMinutes =
                  first.hour * 60 + first.minute;
              final secondMinutes =
                  second.hour * 60 + second.minute;
              return firstMinutes.compareTo(secondMinutes);
            },
          );

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
        return null;

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

    final defaultLimit = now.add(Duration(days: daysAhead));

    final limit = endDate != null &&
        endDate.isBefore(defaultLimit)
        ? endDate
        : defaultLimit;

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

      cursor = cursor.add(const Duration(days: 1));
    }

    result.sort();

    return result;
  }
}