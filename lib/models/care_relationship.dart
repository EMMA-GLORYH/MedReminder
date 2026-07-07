// lib/models/care_relationship.dart

class CareRelationship {
  final String id;
  final String patientId;
  final String caretakerId;
  final int alertThresholdMins;
  final String status; // 'pending', 'active', 'revoked'
  final DateTime invitedAt;
  final DateTime? acceptedAt;

  CareRelationship({
    required this.id,
    required this.patientId,
    required this.caretakerId,
    required this.alertThresholdMins,
    required this.status,
    required this.invitedAt,
    this.acceptedAt,
  });

  factory CareRelationship.fromJson(Map<String, dynamic> json) {
    return CareRelationship(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      caretakerId: json['caretaker_id'] as String,
      alertThresholdMins: json['alert_threshold_mins'] as int,
      status: json['status'] as String,
      invitedAt: DateTime.parse(json['invited_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'patient_id': patientId,
      'caretaker_id': caretakerId,
      'alert_threshold_mins': alertThresholdMins,
      'status': status,
    };
  }

  /// Status helpers
  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';

  /// Accept the invitation
  CareRelationship accept() {
    return CareRelationship(
      id: id,
      patientId: patientId,
      caretakerId: caretakerId,
      alertThresholdMins: alertThresholdMins,
      status: 'active',
      invitedAt: invitedAt,
      acceptedAt: DateTime.now(),
    );
  }

  /// Revoke the relationship
  CareRelationship revoke() {
    return CareRelationship(
      id: id,
      patientId: patientId,
      caretakerId: caretakerId,
      alertThresholdMins: alertThresholdMins,
      status: 'revoked',
      invitedAt: invitedAt,
      acceptedAt: acceptedAt,
    );
  }
}