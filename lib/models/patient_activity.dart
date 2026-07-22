// lib/models/patient_activity.dart

import 'package:flutter/foundation.dart';

@immutable
class PatientActivity {
  final String id;
  final String patientId;
  final String patientName;
  final String? patientAvatar;
  final String medicationId;
  final String scheduleId;
  final String genericName;
  final String? brandName;
  final String dosageAmount;
  final String dosageUnit;
  final String? pillColor;
  final String? pillImageUrl;
  final DateTime scheduledFor;
  final DateTime? loggedAt;
  final String status;
  final int? deviationMinutes;
  final String? notes;
  final bool markedAsMissed;
  final String? relationship;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PatientActivity({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.patientAvatar,
    required this.medicationId,
    required this.scheduleId,
    required this.genericName,
    this.brandName,
    required this.dosageAmount,
    required this.dosageUnit,
    this.pillColor,
    this.pillImageUrl,
    required this.scheduledFor,
    this.loggedAt,
    required this.status,
    this.deviationMinutes,
    this.notes,
    required this.markedAsMissed,
    this.relationship,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PatientActivity.fromJson(Map<String, dynamic> json) {
    return PatientActivity(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      patientName: json['patient_name'] as String? ?? 'Unknown Patient',
      patientAvatar: json['patient_avatar'] as String?,
      medicationId: json['medication_id'] as String,
      scheduleId: json['schedule_id'] as String,
      genericName: json['generic_name'] as String,
      brandName: json['brand_name'] as String?,
      dosageAmount: json['dosage_amount'] as String,
      dosageUnit: json['dosage_unit'] as String,
      pillColor: json['pill_color'] as String?,
      pillImageUrl: json['pill_image_url'] as String?,
      scheduledFor: DateTime.parse(json['scheduled_for'] as String),
      loggedAt: json['logged_at'] != null
          ? DateTime.parse(json['logged_at'] as String)
          : null,
      status: json['status'] as String,
      deviationMinutes: json['deviation_minutes'] as int?,
      notes: json['notes'] as String?,
      markedAsMissed: json['marked_as_missed'] as bool? ?? false,
      relationship: json['relationship'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get displayMedicationName {
    if (brandName != null && brandName!.isNotEmpty) {
      return '$brandName ($genericName)';
    }
    return genericName;
  }

  String get displayDosage => '$dosageAmount $dosageUnit';

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'taken':
        return 'Taken';
      case 'missed':
        return markedAsMissed ? 'Auto-missed' : 'Missed';
      case 'pending':
        return 'Pending';
      case 'skipped':
        return 'Skipped';
      default:
        return status;
    }
  }

  bool get isTaken => status.toLowerCase() == 'taken';
  bool get isMissed => status.toLowerCase() == 'missed';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isSkipped => status.toLowerCase() == 'skipped';

  String get patientInitial {
    return patientName.isNotEmpty ? patientName[0].toUpperCase() : '?';
  }
}