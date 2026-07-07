// lib/models/medication_schedule.dart

import 'package:flutter/material.dart';

class MedicationSchedule {
  final String id;
  final String medicationId;
  final String patientId;
  final String frequencyType;
  final double? intervalHours;
  final double? minHoursBetween;
  final List<TimeOfDay>? scheduledTimes;
  final List<int>? scheduledDays;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? lastTakenAt;
  final DateTime? nextScheduledAt;
  final bool escalationEnabled;
  final int escalationStep1Mins;
  final int escalationStep2Mins;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  MedicationSchedule({
    required this.id,
    required this.medicationId,
    required this.patientId,
    required this.frequencyType,
    this.intervalHours,
    this.minHoursBetween,
    this.scheduledTimes,
    this.scheduledDays,
    required this.startDate,
    this.endDate,
    this.lastTakenAt,
    this.nextScheduledAt,
    required this.escalationEnabled,
    required this.escalationStep1Mins,
    required this.escalationStep2Mins,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MedicationSchedule.fromJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      id: json['id'] as String,
      medicationId: json['medication_id'] as String,
      patientId: json['patient_id'] as String,
      frequencyType: json['frequency_type'] as String,
      intervalHours: json['interval_hours'] != null
          ? (json['interval_hours'] as num).toDouble()
          : null,
      minHoursBetween: json['min_hours_between'] != null
          ? (json['min_hours_between'] as num).toDouble()
          : null,
      scheduledTimes: _parseTimeArray(json['scheduled_times']),
      scheduledDays: json['scheduled_days'] != null
          ? List<int>.from(json['scheduled_days'] as List)
          : null,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      lastTakenAt: json['last_taken_at'] != null
          ? DateTime.parse(json['last_taken_at'] as String)
          : null,
      nextScheduledAt: json['next_scheduled_at'] != null
          ? DateTime.parse(json['next_scheduled_at'] as String)
          : null,
      escalationEnabled: json['escalation_enabled'] as bool,
      escalationStep1Mins: json['escalation_step1_mins'] as int,
      escalationStep2Mins: json['escalation_step2_mins'] as int,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'medication_id': medicationId,
      'patient_id': patientId,
      'frequency_type': frequencyType,
      'interval_hours': intervalHours,
      'min_hours_between': minHoursBetween,
      'scheduled_times': scheduledTimes
          ?.map((t) => '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}')
          .toList(),
      'scheduled_days': scheduledDays,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDate?.toIso8601String().split('T').first,
      'last_taken_at': lastTakenAt?.toIso8601String(),
      'next_scheduled_at': nextScheduledAt?.toIso8601String(),
      'escalation_enabled': escalationEnabled,
      'escalation_step1_mins': escalationStep1Mins,
      'escalation_step2_mins': escalationStep2Mins,
      'is_active': isActive,
    };
  }

  /// Parse Supabase TIME[] array into Flutter TimeOfDay list
  /// Supabase returns time arrays as: ["08:00:00", "20:00:00"]
  static List<TimeOfDay>? _parseTimeArray(dynamic raw) {
    if (raw == null) return null;

    final list = raw is List ? raw : [];

    return list.map((time) {
      final parts = (time as String).split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }).toList();
  }

  /// Helpers
  bool get isDaily => frequencyType == 'daily';
  bool get isMultipleDaily => frequencyType == 'multiple_daily';
  bool get isIntervalBased => frequencyType == 'every_x_hours';
  bool get isAsNeeded => frequencyType == 'as_needed';

  bool get isOngoing => endDate == null;
  bool get hasStarted => DateTime.now().isAfter(startDate);

  bool get isExpired =>
      endDate != null && DateTime.now().isAfter(endDate!);
}