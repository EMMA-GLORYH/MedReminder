// lib/models/medication.dart

class Medication {
  final String id;
  final String patientId;
  final String? brandName;
  final String genericName;
  final double dosageAmount;
  final String dosageUnit;
  final int? currentQuantity;
  final int refillAlertAt;
  final String? pillColor;
  final String? pillShape;
  final String? pillImageUrl;
  final String medicationType; // 'scheduled' or 'prn'
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Medication({
    required this.id,
    required this.patientId,
    this.brandName,
    required this.genericName,
    required this.dosageAmount,
    required this.dosageUnit,
    this.currentQuantity,
    required this.refillAlertAt,
    this.pillColor,
    this.pillShape,
    this.pillImageUrl,
    required this.medicationType,
    this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      brandName: json['brand_name'] as String?,
      genericName: json['generic_name'] as String,
      dosageAmount: (json['dosage_amount'] as num).toDouble(),
      dosageUnit: json['dosage_unit'] as String,
      currentQuantity: json['current_quantity'] as int?,
      refillAlertAt: json['refill_alert_at'] as int,
      pillColor: json['pill_color'] as String?,
      pillShape: json['pill_shape'] as String?,
      pillImageUrl: json['pill_image_url'] as String?,
      medicationType: json['medication_type'] as String,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'patient_id': patientId,
      'brand_name': brandName,
      'generic_name': genericName,
      'dosage_amount': dosageAmount,
      'dosage_unit': dosageUnit,
      'current_quantity': currentQuantity,
      'refill_alert_at': refillAlertAt,
      'pill_color': pillColor,
      'pill_shape': pillShape,
      'pill_image_url': pillImageUrl,
      'medication_type': medicationType,
      'notes': notes,
      'is_active': isActive,
    };
  }

  /// Display helpers
  String get displayDosage => '$dosageAmount$dosageUnit';

  String get displayName => brandName != null
      ? '$brandName ($genericName)'
      : genericName;

  bool get isScheduled => medicationType == 'scheduled';
  bool get isPrn => medicationType == 'prn';

  bool get needsRefill =>
      currentQuantity != null && currentQuantity! <= refillAlertAt;

  Medication copyWith({
    String? brandName,
    String? genericName,
    double? dosageAmount,
    String? dosageUnit,
    int? currentQuantity,
    int? refillAlertAt,
    String? pillColor,
    String? pillShape,
    String? pillImageUrl,
    String? medicationType,
    String? notes,
    bool? isActive,
  }) {
    return Medication(
      id: id,
      patientId: patientId,
      brandName: brandName ?? this.brandName,
      genericName: genericName ?? this.genericName,
      dosageAmount: dosageAmount ?? this.dosageAmount,
      dosageUnit: dosageUnit ?? this.dosageUnit,
      currentQuantity: currentQuantity ?? this.currentQuantity,
      refillAlertAt: refillAlertAt ?? this.refillAlertAt,
      pillColor: pillColor ?? this.pillColor,
      pillShape: pillShape ?? this.pillShape,
      pillImageUrl: pillImageUrl ?? this.pillImageUrl,
      medicationType: medicationType ?? this.medicationType,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}