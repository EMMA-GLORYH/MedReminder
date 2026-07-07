// lib/models/escalation_event.dart

class EscalationEvent {
  final String id;
  final String doseLogId;
  final String patientId;
  final int escalationStep;
  final String channel;
  final String? sentTo;
  final DateTime sentAt;
  final bool resolved;
  final DateTime? resolvedAt;
  final String? externalApiId;
  final String deliveryStatus;

  EscalationEvent({
    required this.id,
    required this.doseLogId,
    required this.patientId,
    required this.escalationStep,
    required this.channel,
    this.sentTo,
    required this.sentAt,
    required this.resolved,
    this.resolvedAt,
    this.externalApiId,
    required this.deliveryStatus,
  });

  factory EscalationEvent.fromJson(Map<String, dynamic> json) {
    return EscalationEvent(
      id: json['id'] as String,
      doseLogId: json['dose_log_id'] as String,
      patientId: json['patient_id'] as String,
      escalationStep: json['escalation_step'] as int,
      channel: json['channel'] as String,
      sentTo: json['sent_to'] as String?,
      sentAt: DateTime.parse(json['sent_at'] as String),
      resolved: json['resolved'] as bool,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      externalApiId: json['external_api_id'] as String?,
      deliveryStatus: json['delivery_status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dose_log_id': doseLogId,
      'patient_id': patientId,
      'escalation_step': escalationStep,
      'channel': channel,
      'sent_to': sentTo,
      'resolved': resolved,
      'resolved_at': resolvedAt?.toIso8601String(),
      'external_api_id': externalApiId,
      'delivery_status': deliveryStatus,
    };
  }

  /// Helpers
  bool get isPush => channel == 'push';
  bool get isAlarm => channel == 'alarm';
  bool get isSms => channel == 'sms';
  bool get isPhoneCall => channel == 'phone_call';

  bool get sentToPatient => sentTo == null;
  bool get sentToCaretaker => sentTo != null;

  bool get wasDelivered => deliveryStatus == 'delivered';
  bool get hasFailed => deliveryStatus == 'failed';
}