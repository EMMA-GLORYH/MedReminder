// lib/services/patient_activity_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/patient_activity.dart';

class PatientActivityService {
  PatientActivityService._();

  static final PatientActivityService instance = PatientActivityService._();

  final _supabase = Supabase.instance.client;

  /// Subscribe to real-time patient activities for current caregiver
  RealtimeChannel subscribeToPatientActivities({
    required String caregiverId,
    required void Function(List<PatientActivity> activities) onData,
    required void Function(String error) onError,
  }) {
    debugPrint('🔔 Subscribing to patient activities for caregiver: $caregiverId');

    return _supabase
        .channel('caretaker_activities_$caregiverId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'dose_logs',
      callback: (payload) async {
        debugPrint('📬 Activity change detected: ${payload.eventType}');
        try {
          await _refreshActivities(
            caregiverId: caregiverId,
            onData: onData,
          );
        } catch (error, stack) {
          debugPrint('❌ Failed to refresh activities: $error');
          debugPrint('$stack');
          onError(error.toString());
        }
      },
    )
        .subscribe();
  }

  Future<void> _refreshActivities({
    required String caregiverId,
    required void Function(List<PatientActivity> activities) onData,
  }) async {
    final activities = await getRecentActivities(
      caregiverId: caregiverId,
      limit: 50,
    );
    onData(activities);
  }

  /// Get recent activities for all patients monitored by caregiver
  Future<List<PatientActivity>> getRecentActivities({
    required String caregiverId,
    String? patientId,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      debugPrint(
        '📊 Fetching activities: caregiver=$caregiverId, '
            'patient=$patientId, status=$status, limit=$limit',
      );

      final response = await _supabase.rpc(
        'get_caretaker_patient_activities',
        params: {
          'p_caregiver_id': caregiverId,
          'p_patient_id': patientId,
          'p_status': status,
          'p_limit': limit,
          'p_offset': offset,
        },
      );

      debugPrint('✅ Received ${(response as List).length} activities');

      return (response as List<dynamic>)
          .map((json) => PatientActivity.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      debugPrint('❌ Postgrest error: ${error.message}');
      debugPrint('   Code: ${error.code}');
      debugPrint('   Details: ${error.details}');
      debugPrint('   Hint: ${error.hint}');
      throw Exception('Database error: ${error.message}');
    } catch (error, stack) {
      debugPrint('❌ Failed to load patient activities: $error');
      debugPrint('$stack');
      throw Exception('Could not load patient activities');
    }
  }

  Future<Map<String, int>> getActivityStats({
    required String caregiverId,
    String? patientId,
  }) async {
    final safeCaregiverId = caregiverId.trim();
    final filteredPatientId = patientId?.trim();

    if (safeCaregiverId.isEmpty) {
      throw ArgumentError.value(
        caregiverId,
        'caregiverId',
        'Caregiver ID cannot be empty',
      );
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDayExclusive = startOfDay.add(const Duration(days: 1));
    final todayString = startOfDay.toIso8601String().split('T').first;
    final weekdayIndex = now.weekday % 7;

    try {
      final relationships = await supabase
          .from('care_relationships')
          .select('patient_id, can_view_logs, can_view_medications')
          .eq('caregiver_id', safeCaregiverId)
          .eq('status', 'active');

      final logPatientIds = <String>[];
      final schedulePatientIds = <String>[];

      for (final raw in relationships as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final relPatientId = row['patient_id']?.toString();

        if (relPatientId == null || relPatientId.trim().isEmpty) continue;
        if (filteredPatientId != null &&
            filteredPatientId.isNotEmpty &&
            relPatientId != filteredPatientId) {
          continue;
        }

        if (row['can_view_logs'] == true) {
          logPatientIds.add(relPatientId);
        }

        if (row['can_view_medications'] == true) {
          schedulePatientIds.add(relPatientId);
        }
      }

      final takenKeys = <String>{};
      final explicitMissedKeys = <String>{};
      final skippedKeys = <String>{};

      // ✅ Count completed/taken doses from actual logs
      if (logPatientIds.isNotEmpty) {
        final logRows = await supabase
            .from('dose_logs')
            .select('patient_id, medication_id, scheduled_for, status')
            .inFilter('patient_id', logPatientIds)
            .gte('scheduled_for', startOfDay.toIso8601String())
            .lt('scheduled_for', endOfDayExclusive.toIso8601String());

        for (final raw in logRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);

          final logPatientId = row['patient_id']?.toString();
          final medicationId = row['medication_id']?.toString();
          final scheduledForRaw = row['scheduled_for']?.toString();
          final status = row['status']?.toString().toLowerCase().trim() ?? '';

          if (logPatientId == null ||
              medicationId == null ||
              scheduledForRaw == null) {
            continue;
          }

          final scheduledFor = DateTime.tryParse(scheduledForRaw)?.toLocal();
          if (scheduledFor == null) continue;

          final key = _buildDoseKey(
            patientId: logPatientId,
            medicationId: medicationId,
            scheduledFor: scheduledFor,
          );

          if (status == 'taken' || status == 'late') {
            takenKeys.add(key);
          } else if (status == 'missed') {
            explicitMissedKeys.add(key);
          } else if (status == 'skipped') {
            skippedKeys.add(key);
          }
        }
      }

      int pendingCount = 0;
      int inferredMissedCount = 0;

      // ✅ Count pending + inferred missed from today's schedules
      if (schedulePatientIds.isNotEmpty) {
        final scheduleRows = await supabase
            .from('medication_schedules')
            .select('''
            id,
            patient_id,
            medication_id,
            frequency_type,
            scheduled_times,
            scheduled_days,
            start_date,
            end_date,
            is_active
          ''')
            .inFilter('patient_id', schedulePatientIds)
            .eq('is_active', true)
            .lte('start_date', todayString)
            .or('end_date.is.null,end_date.gte.$todayString');

        final expectedKeys = <String>{};

        for (final raw in scheduleRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);

          final schedulePatientId = row['patient_id']?.toString();
          final medicationId = row['medication_id']?.toString();
          final frequencyType =
              row['frequency_type']?.toString().toLowerCase().trim() ?? '';

          if (schedulePatientId == null || medicationId == null) continue;
          if (frequencyType == 'as_needed') continue;

          final scheduledDays = row['scheduled_days'] as List?;
          if (scheduledDays != null &&
              scheduledDays.isNotEmpty &&
              !scheduledDays.contains(weekdayIndex)) {
            continue;
          }

          final scheduledTimes = row['scheduled_times'] as List?;
          if (scheduledTimes == null || scheduledTimes.isEmpty) continue;

          for (final rawTime in scheduledTimes) {
            final time = rawTime.toString();
            final parts = time.split(':');
            if (parts.length < 2) continue;

            final hour = int.tryParse(parts[0]);
            final minute = int.tryParse(parts[1]);

            if (hour == null || minute == null) continue;

            final scheduledFor = DateTime(
              startOfDay.year,
              startOfDay.month,
              startOfDay.day,
              hour,
              minute,
            );

            final key = _buildDoseKey(
              patientId: schedulePatientId,
              medicationId: medicationId,
              scheduledFor: scheduledFor,
            );

            if (!expectedKeys.add(key)) continue;

            // Already completed
            if (takenKeys.contains(key)) continue;

            // Explicitly skipped should not be counted anymore
            if (skippedKeys.contains(key)) continue;

            // Explicitly missed from logs
            if (explicitMissedKeys.contains(key)) continue;

            if (scheduledFor.isBefore(now)) {
              inferredMissedCount++;
            } else {
              // ✅ upcoming dose counts as pending
              pendingCount++;
            }
          }
        }
      }

      return <String, int>{
        'taken': takenKeys.length,
        'missed': explicitMissedKeys.length + inferredMissedCount,
        'pending': pendingCount,
      };
    } catch (error, stack) {
      debugPrint('❌ Failed to compute activity stats: $error');
      debugPrint('$stack');
      rethrow;
    }
  }

  String _buildDoseKey({
    required String patientId,
    required String medicationId,
    required DateTime scheduledFor,
  }) {
    final local = scheduledFor.toLocal();

    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');

    return '$patientId|$medicationId|$y-$m-$d $h:$min';
  }

  /// Get unique patients with recent activity
  Future<List<Map<String, dynamic>>> getPatientsWithActivity({
    required String caregiverId,
  }) async {
    try {
      debugPrint('📊 Fetching patients with activity for: $caregiverId');

      final response = await _supabase.rpc(
        'get_patients_with_activity',
        params: {
          'p_caregiver_id': caregiverId,
        },
      );

      debugPrint('✅ Found ${(response as List).length} patients');

      return (response as List<dynamic>).map((row) {
        return {
          'id': row['patient_id'] as String,
          'name': row['patient_name'] as String? ?? 'Unknown',
          'avatar': row['patient_avatar'] as String?,
        };
      }).toList();
    } on PostgrestException catch (error) {
      debugPrint('❌ Patients Postgrest error: ${error.message}');
      return [];
    } catch (error, stack) {
      debugPrint('❌ Failed to load patients with activity: $error');
      debugPrint('$stack');
      return [];
    }
  }
}