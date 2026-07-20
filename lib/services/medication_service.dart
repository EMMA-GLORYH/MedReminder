// lib/services/medication_service.dart

import 'package:flutter/foundation.dart';
import '../main.dart';
import '../models/medication.dart';
import 'auth_service.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class MedicationService {
  MedicationService._();
  static final MedicationService instance = MedicationService._();

  /// Add a new medication for the current patient
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
    String? notes,
  }) async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('You must be logged in to add medications');
    }

    debugPrint('💊 Adding medication for user: $userId');
    debugPrint('   Name: $genericName');
    debugPrint('   Dosage: $dosageAmount $dosageUnit');
    debugPrint('   Type: $medicationType');

    try {
      final data = await supabase
          .from('medications')
          .insert({
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
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'is_active': true,
      })
          .select()
          .single();

      debugPrint('✅ Medication saved with ID: ${data['id']}');
      return Medication.fromJson(data);
    } catch (e) {
      debugPrint('❌ Failed to save medication: $e');
      rethrow;
    }
  }

  Future<String> uploadMedicationImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final cleanedName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final ext = cleanedName.contains('.')
        ? cleanedName.split('.').last.toLowerCase()
        : 'jpg';

    final path =
        '$userId/${DateTime.now().millisecondsSinceEpoch}_$cleanedName';

    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };

    await supabase.storage.from('medication-images').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: false,
      ),
    );

    return supabase.storage.from('medication-images').getPublicUrl(path);
  }

  /// Fetch ALL active medications for the current patient in one shot.
  /// Kept unchanged for any existing callers that rely on a complete list
  /// (e.g. dashboards). For the medications list screen itself, prefer
  /// [getMyMedicationsPage] so the UI never has to render an unbounded
  /// number of cards at once.
  Future<List<Medication>> getMyMedications() async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

    debugPrint('📋 Fetching medications for user: $userId');

    try {
      final data = await supabase
          .from('medications')
          .select()
          .eq('patient_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      debugPrint('✅ Loaded ${data.length} medications');

      return (data as List)
          .map((json) => Medication.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch medications: $e');
      rethrow;
    }
  }

  /// Fetch one indexed page of active medications, most recently added
  /// first — e.g. offset: 0, limit: 12 gets items 0..11; offset: 12,
  /// limit: 12 gets items 12..23. Backed by Postgres `.range()`, so only
  /// the requested rows are ever transferred or rendered.
  Future<List<Medication>> getMyMedicationsPage({
    required int offset,
    required int limit,
  }) async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

    debugPrint('📋 Fetching medications page (offset=$offset, limit=$limit)');

    try {
      final data = await supabase
          .from('medications')
          .select()
          .eq('patient_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (data as List)
          .map((json) => Medication.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch medications page: $e');
      rethrow;
    }
  }

  /// Lightweight count of the patient's active medications, without
  /// transferring any row data — used to show an accurate "N medications"
  /// total in the header even though the list itself is paginated.
  Future<int> getMedicationsCount() async {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw Exception('Not logged in');
    }

    try {
      final response = await supabase
          .from('medications')
          .select('id')
          .eq('patient_id', userId)
          .eq('is_active', true)
          .count(CountOption.exact);

      return response.count;
    } catch (e) {
      debugPrint('❌ Failed to count medications: $e');
      rethrow;
    }
  }

  /// Fetch a single medication by ID
  Future<Medication?> getMedicationById(String id) async {
    try {
      final data = await supabase
          .from('medications')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (data == null) return null;
      return Medication.fromJson(data);
    } catch (e) {
      debugPrint('❌ Failed to fetch medication $id: $e');
      rethrow;
    }
  }

  /// Update an existing medication
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

    if (genericName != null) updates['generic_name'] = genericName.trim();
    if (brandName != null) updates['brand_name'] = brandName.trim();
    if (dosageAmount != null) updates['dosage_amount'] = dosageAmount;
    if (dosageUnit != null) updates['dosage_unit'] = dosageUnit;
    if (medicationType != null) updates['medication_type'] = medicationType;
    if (currentQuantity != null) updates['current_quantity'] = currentQuantity;
    if (refillAlertAt != null) updates['refill_alert_at'] = refillAlertAt;
    if (pillColor != null) updates['pill_color'] = pillColor;
    if (pillShape != null) updates['pill_shape'] = pillShape;
    if (notes != null) updates['notes'] = notes.trim();

    try {
      final data = await supabase
          .from('medications')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      debugPrint('✅ Medication updated: $id');
      return Medication.fromJson(data);
    } catch (e) {
      debugPrint('❌ Failed to update medication: $e');
      rethrow;
    }
  }

  /// Soft delete — mark as inactive (never hard delete medical records)
  Future<void> deleteMedication(String id) async {
    try {
      await supabase
          .from('medications')
          .update({
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', id);

      debugPrint('✅ Medication deactivated: $id');
    } catch (e) {
      debugPrint('❌ Failed to delete medication: $e');
      rethrow;
    }
  }

  /// Restore a soft-deleted medication
  Future<void> restoreMedication(String id) async {
    await supabase
        .from('medications')
        .update({
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    })
        .eq('id', id);
  }

  /// Delete a medication AND all its schedules (soft delete both)
  Future<void> deleteMedicationWithSchedules(String medicationId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    debugPrint('🗑️ Cascade deleting medication: $medicationId');

    try {
      final now = DateTime.now().toIso8601String();

      // Deactivate all schedules first
      await supabase
          .from('medication_schedules')
          .update({
        'is_active': false,
        'updated_at': now,
      })
          .eq('medication_id', medicationId);

      // Then deactivate the medication
      await supabase
          .from('medications')
          .update({
        'is_active': false,
        'updated_at': now,
      })
          .eq('id', medicationId);

      debugPrint('✅ Medication and schedules deactivated');
    } catch (e) {
      debugPrint('❌ Cascade delete failed: $e');
      rethrow;
    }
  }

  /// Toggle a medication's active status
  Future<Medication> toggleActive(String medicationId, bool isActive) async {
    final now = DateTime.now().toIso8601String();

    // Also deactivate schedules if turning off
    if (!isActive) {
      await supabase
          .from('medication_schedules')
          .update({'is_active': false, 'updated_at': now})
          .eq('medication_id', medicationId);
    }

    final data = await supabase
        .from('medications')
        .update({
      'is_active': isActive,
      'updated_at': now,
    })
        .eq('id', medicationId)
        .select()
        .single();

    return Medication.fromJson(data);
  }

  Future<List<Medication>> getMedicationsForPatient(
      String patientId,
      ) async {
    final caregiverId =
        AuthService.instance.currentUser?.id;

    if (caregiverId == null) {
      throw Exception('Not logged in');
    }

    final relationship = await supabase
        .from('care_relationships')
        .select('can_view_medications, status')
        .eq('patient_id', patientId)
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .maybeSingle();

    if (relationship == null ||
        relationship['can_view_medications'] != true) {
      throw Exception(
        'You are not permitted to view this patient’s medications.',
      );
    }

    final data = await supabase
        .from('medications')
        .select()
        .eq('patient_id', patientId)
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
}