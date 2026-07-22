// lib/services/local_cache_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication.dart';
import '../models/medication_schedule.dart';

class LocalCacheService {
  LocalCacheService._();

  static final LocalCacheService instance = LocalCacheService._();

  static const String _medicationsKey = 'cached_medications';
  static const String _schedulesKey = 'cached_schedules';
  static const String _pendingMedicationsKey = 'pending_medications';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    debugPrint('✅ Local cache initialized');
  }

  // ═════════════════════════════════════════════════════════════
  // MEDICATION CACHE
  // ══════════════════════════════════════════════════════════════

  Future<void> cacheMedication(Medication medication) async {
    try {
      final medications = await getCachedMedications();
      medications.removeWhere((m) => m.id == medication.id);
      medications.insert(0, medication);

      await _prefs?.setString(
        _medicationsKey,
        jsonEncode(medications.map((m) => m.toJson()).toList()),
      );

      debugPrint('💾 Cached medication: ${medication.genericName}');
    } catch (e) {
      debugPrint('❌ Failed to cache medication: $e');
    }
  }

  Future<List<Medication>> getCachedMedications() async {
    try {
      final jsonString = _prefs?.getString(_medicationsKey);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => Medication.fromJson(json)).toList();
    } catch (e) {
      debugPrint('❌ Failed to load cached medications: $e');
      return [];
    }
  }

  Future<Medication?> getCachedMedication(String id) async {
    final medications = await getCachedMedications();
    return medications.where((m) => m.id == id).firstOrNull;
  }

  Future<void> clearMedicationCache() async {
    await _prefs?.remove(_medicationsKey);
  }

  // ══════════════════════════════════════════════════════════════
  // PENDING MEDICATIONS (not yet saved to DB)
  // ══════════════════════════════════════════════════════════════

  Future<void> savePendingMedication({
    required String tempId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final pending = await getPendingMedications();
      pending[tempId] = data;

      await _prefs?.setString(
        _pendingMedicationsKey,
        jsonEncode(pending),
      );

      debugPrint('💾 Saved pending medication: $tempId');
    } catch (e) {
      debugPrint('❌ Failed to save pending medication: $e');
    }
  }

  Future<Map<String, dynamic>?> getPendingMedication(String tempId) async {
    final pending = await getPendingMedications();
    return pending[tempId];
  }

  Future<Map<String, Map<String, dynamic>>> getPendingMedications() async {
    try {
      final jsonString = _prefs?.getString(_pendingMedicationsKey);
      if (jsonString == null) return {};

      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return jsonMap.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)));
    } catch (e) {
      debugPrint('❌ Failed to load pending medications: $e');
      return {};
    }
  }

  Future<void> removePendingMedication(String tempId) async {
    try {
      final pending = await getPendingMedications();
      pending.remove(tempId);

      await _prefs?.setString(
        _pendingMedicationsKey,
        jsonEncode(pending),
      );
    } catch (e) {
      debugPrint('❌ Failed to remove pending medication: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SCHEDULE CACHE
  // ══════════════════════════════════════════════════════════════

  Future<void> cacheSchedule(MedicationSchedule schedule) async {
    try {
      final schedules = await getCachedSchedules();
      schedules.removeWhere((s) => s.id == schedule.id);
      schedules.insert(0, schedule);

      await _prefs?.setString(
        _schedulesKey,
        jsonEncode(schedules.map((s) => s.toJson()).toList()),
      );

      debugPrint('💾 Cached schedule for: ${schedule.medicationId}');
    } catch (e) {
      debugPrint(' Failed to cache schedule: $e');
    }
  }

  Future<List<MedicationSchedule>> getCachedSchedules() async {
    try {
      final jsonString = _prefs?.getString(_schedulesKey);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => MedicationSchedule.fromJson(json)).toList();
    } catch (e) {
      debugPrint('❌ Failed to load cached schedules: $e');
      return [];
    }
  }

  Future<List<MedicationSchedule>> getCachedSchedulesForMedication(
      String medicationId,
      ) async {
    final schedules = await getCachedSchedules();
    return schedules.where((s) => s.medicationId == medicationId).toList();
  }

  Future<void> clearScheduleCache() async {
    await _prefs?.remove(_schedulesKey);
  }
}