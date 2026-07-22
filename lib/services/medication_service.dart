// lib/services/medication_service.dart

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/medication.dart';
import 'auth_service.dart';

class MedicationService {
  MedicationService._();

  static final MedicationService instance =
  MedicationService._();

  String _requireUserId() {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Not logged in');
    }

    return userId;
  }

  // ══════════════════════════════════════════════════════════════
  // PATIENT MEDICATIONS
  // ══════════════════════════════════════════════════════════════

  Future<Medication> addMedication({
    required String genericName,
    String? brandName,
    required double dosageAmount,
    required String dosageUnit,
    required String medicationType,
    int? currentQuantity,
    int refillAlertAt = 7,
    String? pillColor,
    String? pillShape,
    String? pillImageUrl,
    String? notes, required String patientId,
  }) async {
    final userId = _requireUserId();

    try {
      final data = await supabase
          .from('medications')
          .insert(<String, dynamic>{
        'patient_id': userId,
        'generic_name': genericName.trim(),
        'brand_name': brandName?.trim().isEmpty == true
            ? null
            : brandName?.trim(),
        'dosage_amount': dosageAmount,
        'dosage_unit': dosageUnit,
        'medication_type': medicationType,
        'current_quantity': currentQuantity,
        'refill_alert_at': refillAlertAt,
        'pill_color': pillColor,
        'pill_shape': pillShape,
        'pill_image_url': pillImageUrl,
        'notes': notes?.trim().isEmpty == true
            ? null
            : notes?.trim(),
        'is_active': true,
      })
          .select()
          .single();

      debugPrint(
        '✅ Medication saved with ID: ${data['id']}',
      );

      return Medication.fromJson(data);
    } catch (error, stack) {
      debugPrint('❌ Failed to save medication: $error');
      debugPrint('$stack');
      rethrow;
    }
  }

  Future<String> uploadMedicationImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final userId = _requireUserId();

    final cleanedName = fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );

    final extension = cleanedName.contains('.')
        ? cleanedName.split('.').last.toLowerCase()
        : 'jpg';

    final path =
        '$userId/${DateTime.now().millisecondsSinceEpoch}_$cleanedName';

    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };

    await supabase.storage
        .from('medication-images')
        .uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: false,
      ),
    );

    return supabase.storage
        .from('medication-images')
        .getPublicUrl(path);
  }

  Future<List<Medication>> getMyMedications() async {
    final userId = _requireUserId();

    final data = await supabase
        .from('medications')
        .select()
        .eq('patient_id', userId)
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return (data as List)
        .map(
          (row) => Medication.fromJson(
        Map<String, dynamic>.from(row as Map),
      ),
    )
        .toList();
  }

  Future<List<Medication>> getMyMedicationsPage({
    required int offset,
    required int limit,
  }) async {
    final userId = _requireUserId();

    final data = await supabase
        .from('medications')
        .select()
        .eq('patient_id', userId)
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List)
        .map(
          (row) => Medication.fromJson(
        Map<String, dynamic>.from(row as Map),
      ),
    )
        .toList();
  }

  Future<int> getMedicationsCount() async {
    final userId = _requireUserId();

    final response = await supabase
        .from('medications')
        .select('id')
        .eq('patient_id', userId)
        .eq('is_active', true)
        .count(CountOption.exact);

    return response.count;
  }

  Future<Medication?> getMedicationById(
      String id,
      ) async {
    try {
      final data = await supabase
          .from('medications')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (data == null) return null;

      return Medication.fromJson(data);
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to fetch medication $id: $error',
      );
      debugPrint('$stack');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CARETAKER PATIENT MEDICATIONS
  // ══════════════════════════════════════════════════════════════

  /// Loads active medications belonging to one selected patient.
  ///
  /// The current user must be an active caretaker of [patientId] and the
  /// relationship must grant can_view_medications.
  Future<List<Medication>> getMedicationsForPatient(
      String patientId,
      ) async {
    final caregiverId = _requireUserId();
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
        .select(
      'can_view_medications, status',
    )
        .eq('patient_id', safePatientId)
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .maybeSingle();

    if (relationship == null ||
        relationship['can_view_medications'] != true) {
      throw Exception(
        'You are not permitted to view this patient\'s medications.',
      );
    }

    try {
      final data = await supabase
          .from('medications')
          .select()
          .eq('patient_id', safePatientId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      debugPrint(
        '✅ Loaded ${data.length} medications for patient '
            '$safePatientId',
      );

      return (data as List)
          .map(
            (row) => Medication.fromJson(
          Map<String, dynamic>.from(row as Map),
        ),
      )
          .toList();
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to load medications for patient '
            '$safePatientId: $error',
      );
      debugPrint('$stack');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // UPDATE AND DELETE
  // ══════════════════════════════════════════════════════════════

  Future<Medication> updateMedication({
    required String id,
    String? genericName,
    String? brandName,
    double? dosageAmount,
    String? dosageUnit,
    String? medicationType,
    int? currentQuantity,
    int? refillAlertAt,
    String? pillColor,
    String? pillShape,
    String? notes,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (genericName != null) {
      updates['generic_name'] = genericName.trim();
    }
    if (brandName != null) {
      updates['brand_name'] = brandName.trim();
    }
    if (dosageAmount != null) {
      updates['dosage_amount'] = dosageAmount;
    }
    if (dosageUnit != null) {
      updates['dosage_unit'] = dosageUnit;
    }
    if (medicationType != null) {
      updates['medication_type'] = medicationType;
    }
    if (currentQuantity != null) {
      updates['current_quantity'] = currentQuantity;
    }
    if (refillAlertAt != null) {
      updates['refill_alert_at'] = refillAlertAt;
    }
    if (pillColor != null) {
      updates['pill_color'] = pillColor;
    }
    if (pillShape != null) {
      updates['pill_shape'] = pillShape;
    }
    if (notes != null) {
      updates['notes'] = notes.trim();
    }

    final data = await supabase
        .from('medications')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    return Medication.fromJson(data);
  }

  Future<void> deleteMedication(
      String id,
      ) async {
    await supabase
        .from('medications')
        .update(<String, dynamic>{
      'is_active': false,
      'updated_at': DateTime.now().toIso8601String(),
    })
        .eq('id', id);
  }

  Future<void> restoreMedication(
      String id,
      ) async {
    await supabase
        .from('medications')
        .update(<String, dynamic>{
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    })
        .eq('id', id);
  }

  Future<void> deleteMedicationWithSchedules(
      String medicationId,
      ) async {
    _requireUserId();

    final now = DateTime.now().toIso8601String();

    await supabase
        .from('medication_schedules')
        .update(<String, dynamic>{
      'is_active': false,
      'updated_at': now,
    })
        .eq('medication_id', medicationId);

    await supabase
        .from('medications')
        .update(<String, dynamic>{
      'is_active': false,
      'updated_at': now,
    })
        .eq('id', medicationId);
  }

  Future<Medication> toggleActive(
      String medicationId,
      bool isActive,
      ) async {
    _requireUserId();

    final now = DateTime.now().toIso8601String();

    if (!isActive) {
      await supabase
          .from('medication_schedules')
          .update(<String, dynamic>{
        'is_active': false,
        'updated_at': now,
      })
          .eq('medication_id', medicationId);
    }

    final data = await supabase
        .from('medications')
        .update(<String, dynamic>{
      'is_active': isActive,
      'updated_at': now,
    })
        .eq('id', medicationId)
        .select()
        .single();

    return Medication.fromJson(data);
  }
}