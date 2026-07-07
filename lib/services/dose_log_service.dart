// lib/services/dose_log_service.dart

import 'package:flutter/foundation.dart';
import '../main.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';
import 'medication_tts_service.dart';

class DoseLogService {
  DoseLogService._();
  static final DoseLogService instance = DoseLogService._();

  Future<void> markAsTaken({
    required String scheduleId,
    required String medicationId,
    required DateTime scheduledFor,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    debugPrint('✅ Marking dose as taken');

    final now = DateTime.now();
    final deviationMinutes = now.difference(scheduledFor).inMinutes;
    final status = deviationMinutes.abs() > 30 ? 'late' : 'taken';

    try {
      await supabase.from('dose_logs').upsert({
        'schedule_id': scheduleId,
        'medication_id': medicationId,
        'patient_id': userId,
        'scheduled_for': scheduledFor.toIso8601String(),
        'logged_at': now.toIso8601String(),
        'status': status,
        'confirmed_by': userId,
      }, onConflict: 'patient_id,schedule_id,scheduled_for');

      debugPrint('✅ Dose log saved to Supabase');

      // ✅ STOP SPEECH immediately
      await MedicationTtsService.instance.stop();

    } catch (e, st) {
      debugPrint('❌ CRITICAL: Failed to save dose log: $e');
      debugPrint('$st');
      rethrow;
    }

    try {
      await supabase.from('medication_schedules').update({
        'last_taken_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('id', scheduleId).eq('patient_id', userId);
      debugPrint('✅ Schedule last_taken_at updated');
    } catch (e, st) {
      debugPrint('⚠️ Dose logged, but failed to update schedule: $e');
      debugPrint('$st');
    }

    try {
      await _decrementQuantity(medicationId);
    } catch (e, st) {
      debugPrint('⚠️ Dose logged, but failed to decrement quantity: $e');
      debugPrint('$st');
    }

    try {
      // Cancels notifications AND (after we update it) cancels the Android TTS alarm too
      await LocalNotificationService.instance.cancelDose(
        scheduleId: scheduleId,
        scheduledFor: scheduledFor,
      );
      debugPrint('✅ Device alarms cancelled for this dose');
    } catch (e, st) {
      debugPrint('⚠️ Dose logged, but failed to cancel local alarms: $e');
      debugPrint('$st');
    }
  }

  Future<void> markAsSkipped({
    required String scheduleId,
    required String medicationId,
    required DateTime scheduledFor,
    String? reason,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final now = DateTime.now();

    try {
      await supabase.from('dose_logs').upsert({
        'schedule_id': scheduleId,
        'medication_id': medicationId,
        'patient_id': userId,
        'scheduled_for': scheduledFor.toIso8601String(),
        'logged_at': now.toIso8601String(),
        'status': 'skipped',
        'notes': reason,
        'confirmed_by': userId,
      }, onConflict: 'patient_id,schedule_id,scheduled_for');

      debugPrint('⏭️ Dose skipped in Supabase');

      // ✅ STOP SPEECH too
      await MedicationTtsService.instance.stop();

    } catch (e, st) {
      debugPrint('❌ Failed to skip dose: $e');
      debugPrint('$st');
      rethrow;
    }

    try {
      await LocalNotificationService.instance.cancelDose(
        scheduleId: scheduleId,
        scheduledFor: scheduledFor,
      );
      debugPrint('✅ Skipped dose alarms cancelled');
    } catch (e, st) {
      debugPrint('⚠️ Dose skipped, but failed to cancel local alarms: $e');
      debugPrint('$st');
    }
  }

  Future<bool> isDoseLogged({
    required String scheduleId,
    required DateTime scheduledFor,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return false;

    try {
      final data = await supabase
          .from('dose_logs')
          .select('id')
          .eq('patient_id', userId)
          .eq('schedule_id', scheduleId)
          .eq('scheduled_for', scheduledFor.toIso8601String())
          .limit(1);

      return (data as List).isNotEmpty;
    } catch (e) {
      debugPrint('❌ Failed to check logged dose: $e');
      return false;
    }
  }

  Future<Set<String>> getLoggedDoseKeys(DateTime date) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return {};

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final data = await supabase
          .from('dose_logs')
          .select('schedule_id, scheduled_for, status')
          .eq('patient_id', userId)
          .gte('scheduled_for', startOfDay.toIso8601String())
          .lt('scheduled_for', endOfDay.toIso8601String())
          .inFilter('status', ['taken', 'late']);

      final keys = <String>{};

      for (final row in data as List) {
        final scheduledFor = DateTime.parse(row['scheduled_for'] as String).toUtc();

        final formattedTime =
            '${scheduledFor.year}-'
            '${scheduledFor.month.toString().padLeft(2, '0')}-'
            '${scheduledFor.day.toString().padLeft(2, '0')}T'
            '${scheduledFor.hour.toString().padLeft(2, '0')}:'
            '${scheduledFor.minute.toString().padLeft(2, '0')}';

        keys.add('${row['schedule_id']}|$formattedTime');
      }

      return keys;
    } catch (e, st) {
      debugPrint('❌ Failed to fetch logged doses: $e');
      debugPrint('$st');
      return {};
    }
  }

  Future<void> _decrementQuantity(String medicationId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await supabase
          .from('medications')
          .select('current_quantity')
          .eq('id', medicationId)
          .maybeSingle();

      if (data == null || data['current_quantity'] == null) return;

      final current = (data['current_quantity'] as num).toInt();
      if (current <= 0) return;

      await supabase.from('medications').update({
        'current_quantity': current - 1,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', medicationId);
    } catch (e, st) {
      debugPrint('⚠️ Could not decrement quantity: $e');
      debugPrint('$st');
    }
  }
}