// lib/services/patient_activity_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Get activity statistics for dashboard
  Future<Map<String, int>> getActivityStats({
    required String caregiverId,
    String? patientId,
  }) async {
    try {
      debugPrint(
        '📊 Fetching stats: caregiver=$caregiverId, patient=$patientId',
      );

      final response = await _supabase.rpc(
        'get_caretaker_activity_stats',
        params: {
          'p_caregiver_id': caregiverId,
          'p_patient_id': patientId,
        },
      );

      debugPrint('✅ Stats response: $response');

      // Response is a list with a single row
      if (response is List && response.isNotEmpty) {
        final row = response[0] as Map<String, dynamic>;

        return {
          'total': (row['total'] as num?)?.toInt() ?? 0,
          'taken': (row['taken'] as num?)?.toInt() ?? 0,
          'missed': (row['missed'] as num?)?.toInt() ?? 0,
          'pending': (row['pending'] as num?)?.toInt() ?? 0,
          'skipped': (row['skipped'] as num?)?.toInt() ?? 0,
        };
      }

      return {
        'total': 0,
        'taken': 0,
        'missed': 0,
        'pending': 0,
        'skipped': 0,
      };
    } on PostgrestException catch (error) {
      debugPrint('❌ Stats Postgrest error: ${error.message}');
      return {
        'total': 0,
        'taken': 0,
        'missed': 0,
        'pending': 0,
        'skipped': 0,
      };
    } catch (error, stack) {
      debugPrint('❌ Failed to load activity stats: $error');
      debugPrint('$stack');
      return {
        'total': 0,
        'taken': 0,
        'missed': 0,
        'pending': 0,
        'skipped': 0,
      };
    }
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