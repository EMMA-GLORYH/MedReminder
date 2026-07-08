// lib/services/schedule_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/medication_schedule.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';

/// Single source of truth for TodayDose - used by scanner and dashboard
class TodayDose {
  final String scheduleId;
  final String medicationId;
  final String medicationName;
  final String genericName;
  final double dosageAmount;
  final String dosageUnit;
  final String? pillColor;
  final String? pillShape;
  final String? pillImageUrl;           // Used by scanner screen
  final DateTime scheduledTime;
  final String? notes;

  TodayDose({
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
    final diff = scheduledTime.difference(DateTime.now()).inMinutes;
    return diff >= 0 && diff <= 30;
  }
}

class ScheduleService {
  ScheduleService._();
  static final ScheduleService instance = ScheduleService._();

  // ══════════════════════════════════════════════════════════════
  // CREATE SCHEDULE + SET DEVICE ALARMS
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
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('You must be logged in');

    debugPrint('📅 Adding schedule for: $medicationName');

    final timesArray = scheduledTimes
        ?.map((t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00')
        .toList();

    final nextScheduled = _computeNextScheduled(
      frequencyType: frequencyType,
      scheduledTimes: scheduledTimes,
      intervalHours: intervalHours,
      startDate: startDate ?? DateTime.now(),
    );

    try {
      final data = await supabase.from('medication_schedules').insert({
        'medication_id': medicationId,
        'patient_id': userId,
        'frequency_type': frequencyType,
        'interval_hours': intervalHours,
        'min_hours_between': minHoursBetween,
        'scheduled_times': timesArray,
        'scheduled_days': scheduledDays,
        'start_date': (startDate ?? DateTime.now()).toIso8601String().split('T').first,
        'end_date': endDate?.toIso8601String().split('T').first,
        'next_scheduled_at': nextScheduled?.toIso8601String(),
        'escalation_enabled': escalationEnabled,
        'escalation_step1_mins': escalationStep1Mins,
        'escalation_step2_mins': escalationStep2Mins,
        'is_active': true,
      }).select().single();

      final schedule = MedicationSchedule.fromJson(data);
      debugPrint('✅ Supabase schedule saved: ${schedule.id}');

      if (frequencyType != 'as_needed' &&
          scheduledTimes != null &&
          scheduledTimes.isNotEmpty) {
        final futureTimes = _buildFutureDateTimes(
          scheduledTimes: scheduledTimes,
          startDate: startDate ?? DateTime.now(),
          endDate: endDate,
          scheduledDays: scheduledDays,
        );

        int alarmCount = 0;
        for (final time in futureTimes) {
          await LocalNotificationService.instance.scheduleForDose(
            scheduleId: schedule.id,
            medicationId: medicationId,
            medicationName: medicationName,
            dosageDisplay: dosageDisplay,
            scheduledFor: time,
            escalationStep1Mins: escalationStep1Mins,
            escalationStep2Mins: escalationStep2Mins,
          );
          alarmCount++;
        }
        debugPrint('🔔 Scheduled $alarmCount local alarms');
      }

      return schedule;
    } catch (e) {
      debugPrint('❌ Failed to save schedule: $e');
      rethrow;
    }
  }

  Future<List<MedicationSchedule>> getMySchedules() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final data = await supabase
        .from('medication_schedules')
        .select()
        .eq('patient_id', userId)
        .eq('is_active', true)
        .order('next_scheduled_at', ascending: true);

    return (data as List)
        .map((json) => MedicationSchedule.fromJson(json))
        .toList();
  }

  Future<List<MedicationSchedule>> getSchedulesForMedication(String medicationId) async {
    final data = await supabase
        .from('medication_schedules')
        .select()
        .eq('medication_id', medicationId)
        .eq('is_active', true);

    return (data as List)
        .map((json) => MedicationSchedule.fromJson(json))
        .toList();
  }

  Future<void> deleteSchedule(String id) async {
    await supabase.from('medication_schedules').update({
      'is_active': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);

    await LocalNotificationService.instance.cancelSchedule(id);
    debugPrint('🗑️ Deleted schedule $id');
  }

  Future<List<TodayDose>> getDosesForDate(DateTime date) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final dateStr = date.toIso8601String().split('T').first;
    debugPrint('📅 Loading doses for $dateStr');

    try {
      final data = await supabase
          .from('medication_schedules')
          .select('*, medications!inner(pill_image_url, *)')
          .eq('patient_id', userId)
          .eq('is_active', true)
          .lte('start_date', dateStr);

      final doses = <TodayDose>[];
      final weekday = date.weekday;

      for (final row in data as List) {
        final schedule = row as Map<String, dynamic>;
        final medication = schedule['medications'] as Map<String, dynamic>;

        if (schedule['end_date'] != null) {
          final endDate = DateTime.parse(schedule['end_date'] as String);
          if (date.isAfter(endDate)) continue;
        }

        if (schedule['frequency_type'] == 'as_needed') continue;

        final scheduledDays = schedule['scheduled_days'] as List?;
        if (scheduledDays != null &&
            scheduledDays.isNotEmpty &&
            !scheduledDays.contains(weekday)) continue;

        final timesRaw = schedule['scheduled_times'] as List?;
        if (timesRaw == null || timesRaw.isEmpty) continue;

        for (final timeStr in timesRaw) {
          final parts = (timeStr as String).split(':');
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);

          final doseTime = DateTime(
            date.year,
            date.month,
            date.day,
            hour,
            minute,
          );

          doses.add(TodayDose(
            scheduleId: schedule['id'] as String,
            medicationId: medication['id'] as String,
            medicationName: (medication['brand_name'] as String?) ??
                medication['generic_name'] as String,
            genericName: medication['generic_name'] as String,
            dosageAmount: (medication['dosage_amount'] as num).toDouble(),
            dosageUnit: medication['dosage_unit'] as String,
            pillColor: medication['pill_color'] as String?,
            pillShape: medication['pill_shape'] as String?,
            pillImageUrl: medication['pill_image_url'] as String?,
            scheduledTime: doseTime,
            notes: medication['notes'] as String?,
          ));
        }
      }

      doses.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      debugPrint('✅ Loaded ${doses.length} doses for today');
      return doses;
    } catch (e, st) {
      debugPrint('❌ Failed to load doses: $e');
      debugPrint('$st');
      rethrow;
    }
  }

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
        if (scheduledTimes == null || scheduledTimes.isEmpty) return null;
        for (final time in scheduledTimes) {
          final candidate = DateTime(
            now.year,
            now.month,
            now.day,
            time.hour,
            time.minute,
          );
          if (candidate.isAfter(now)) return candidate;
        }
        final first = scheduledTimes.first;
        return DateTime(
          now.year,
          now.month,
          now.day + 1,
          first.hour,
          first.minute,
        );

      case 'every_x_hours':
        if (intervalHours == null) return null;
        return now.add(Duration(minutes: (intervalHours * 60).round()));

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
    final limit = endDate ?? now.add(Duration(days: daysAhead));

    DateTime cursor = DateTime(startDate.year, startDate.month, startDate.day);

    while (!cursor.isAfter(limit)) {
      final weekday = cursor.weekday;
      final dayAllowed = scheduledDays == null ||
          scheduledDays.isEmpty ||
          scheduledDays.contains(weekday);

      if (dayAllowed) {
        for (final t in scheduledTimes) {
          final dt = DateTime(
            cursor.year,
            cursor.month,
            cursor.day,
            t.hour,
            t.minute,
          );
          if (dt.isAfter(now)) result.add(dt);
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }
}