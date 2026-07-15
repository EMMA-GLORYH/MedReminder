// lib/services/sos_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sos_location_service.dart';

import '../main.dart';
import 'auth_service.dart';

class SosCaretakerContact {
  final String id;
  final String name;
  final String? phoneNumber;

  const SosCaretakerContact({
    required this.id,
    required this.name,
    this.phoneNumber,
  });

  bool get hasPhoneNumber {
    final phone = phoneNumber;
    return phone != null && phone.trim().isNotEmpty;
  }
}

class SosDispatchResult {
  final List<String> alertIds;
  final List<SosCaretakerContact> caretakers;

  const SosDispatchResult({
    required this.alertIds,
    required this.caretakers,
  });

  int get caretakerCount => caretakers.length;

  SosCaretakerContact? get firstCallableCaretaker {
    for (final caretaker in caretakers) {
      if (caretaker.hasPhoneNumber) return caretaker;
    }

    return null;
  }
}

class SosDispatchException implements Exception {
  final String message;

  const SosDispatchException(this.message);

  @override
  String toString() => message;
}

class SosService {
  SosService._();

  static final SosService instance = SosService._();

  String _requireCurrentUserId() {
    final userId = AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw const SosDispatchException(
        'You must be signed in before sending an SOS.',
      );
    }

    return userId;
  }

  Future<SosDispatchResult> sendSos({
    String message = 'Patient requested urgent assistance',
  }) async {
    final patientId = _requireCurrentUserId();

    final requestKey =
        '${patientId}_${DateTime.now().toUtc().microsecondsSinceEpoch}';

    try {
      final rawRelationships = await supabase
          .from('care_relationships')
          .select(
        '''
            id,
            patient_id,
            caregiver_id,
            status,
            can_receive_alerts
            ''',
      )
          .eq('patient_id', patientId);

      final relationships = List<Map<String, dynamic>>.from(
        rawRelationships as List,
      );

      debugPrint(
        '🔍 SOS relationships for patient $patientId: $relationships',
      );

      final eligible = relationships.where((relationship) {
        final status = relationship['status']?.toString();
        final canReceiveAlerts =
            relationship['can_receive_alerts'] != false;

        return status == 'active' && canReceiveAlerts;
      }).toList();

      if (eligible.isEmpty) {
        final hasPending = relationships.any(
              (relationship) =>
          relationship['status']?.toString() == 'pending',
        );

        final hasRevoked = relationships.any(
              (relationship) =>
          relationship['status']?.toString() == 'revoked',
        );

        final hasActiveWithAlertsDisabled = relationships.any(
              (relationship) =>
          relationship['status']?.toString() == 'active' &&
              relationship['can_receive_alerts'] == false,
        );

        if (hasPending) {
          throw const SosDispatchException(
            'Your caretaker invitation is still pending. '
                'The caretaker must accept it before receiving SOS alerts.',
          );
        }

        if (hasRevoked) {
          throw const SosDispatchException(
            'Your previous caretaker connection was revoked. '
                'Invite the caretaker again and wait for acceptance.',
          );
        }

        if (hasActiveWithAlertsDisabled) {
          throw const SosDispatchException(
            'Your caretaker is connected, but SOS alerts are disabled. '
                'Enable alerts in the caretaker permissions.',
          );
        }

        throw const SosDispatchException(
          'No active caretaker is currently available to receive SOS alerts.',
        );
      }

      final location =
      await SosLocationService.instance.getCurrentLocation();

      debugPrint(
        location == null
            ? '⚠️ SOS will be sent without location'
            : '📍 SOS location: '
            '${location.latitude}, ${location.longitude} '
            '±${location.accuracy.toStringAsFixed(0)}m',
      );

      final response = await supabase.rpc(
        'create_sos_alerts',
        params: {
          'p_request_key': requestKey,
          'p_message': message,
          'p_latitude': location?.latitude,
          'p_longitude': location?.longitude,
          'p_accuracy_m': location?.accuracy,
        },
      );

      final rows = response is List
          ? List<Map<String, dynamic>>.from(response)
          : <Map<String, dynamic>>[];

      if (rows.isEmpty) {
        throw const SosDispatchException(
          'The SOS could not be delivered to your active caretaker.',
        );
      }

      final alertIds = <String>[];
      final contacts = <String, SosCaretakerContact>{};

      for (final row in rows) {
        final alertId = row['alert_id']?.toString();
        final caregiverId = row['caregiver_id']?.toString();

        if (alertId != null && alertId.isNotEmpty) {
          alertIds.add(alertId);
        }

        if (caregiverId == null || caregiverId.isEmpty) continue;

        contacts[caregiverId] = SosCaretakerContact(
          id: caregiverId,
          name: row['caregiver_name']?.toString() ?? 'Caretaker',
          phoneNumber: row['caregiver_phone']?.toString(),
        );
      }

      if (contacts.isEmpty) {
        throw const SosDispatchException(
          'The SOS was created, but caretaker contact details were unavailable.',
        );
      }

      debugPrint(
        '✅ SOS delivered to ${contacts.length} caretaker(s)',
      );

      return SosDispatchResult(
        alertIds: alertIds,
        caretakers: contacts.values.toList(),
      );
    } on SosDispatchException {
      rethrow;
    } catch (error, stack) {
      debugPrint('❌ SOS dispatch error: $error');
      debugPrint('$stack');

      throw const SosDispatchException(
        'Could not send the SOS. Please try again or call for help.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getCaretakerAlerts() async {
    final caregiverId = _requireCurrentUserId();

    final data = await supabase
        .from('sos_alerts')
        .select(
      '''
          id,
          relationship_id,
          patient_id,
          caregiver_id,
          request_key,
          message,
          status,
          acknowledged_at,
          resolved_at,
          created_at,
          updated_at,
          patient:profiles!sos_alerts_patient_id_fkey(
            id,
            full_name,
            phone_number,
            avatar_url
          )
          patient_name,
          latitude,
          longitude,
          location_accuracy_m,
          location_captured_at,
          ''',
    )
        .eq('caregiver_id', caregiverId)
        .order('created_at', ascending: false)
        .limit(100);

    return List<Map<String, dynamic>>.from(data);
  }

  RealtimeChannel subscribeToCaretakerAlerts(
      void Function(PostgresChangePayload payload) onChanged,
      ) {
    final caregiverId = _requireCurrentUserId();

    final channel = supabase.channel(
      'sos_alerts_$caregiverId',
    );

    channel
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'sos_alerts',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'caregiver_id',
        value: caregiverId,
      ),
      callback: onChanged,
    )
        .subscribe();

    return channel;
  }

  Future<void> acknowledgeAlert(String alertId) async {
    final caregiverId = _requireCurrentUserId();
    final now = DateTime.now().toUtc().toIso8601String();

    final updated = await supabase
        .from('sos_alerts')
        .update({
      'status': 'acknowledged',
      'acknowledged_at': now,
      'updated_at': now,
    })
        .eq('id', alertId)
        .eq('caregiver_id', caregiverId)
        .eq('status', 'sent')
        .select('id');

    if ((updated as List).isEmpty) {
      throw const SosDispatchException(
        'Alert was not found or is no longer awaiting acknowledgement.',
      );
    }
  }

  Future<void> resolveAlert(String alertId) async {
    final caregiverId = _requireCurrentUserId();
    final now = DateTime.now().toUtc().toIso8601String();

    final updated = await supabase
        .from('sos_alerts')
        .update({
      'status': 'resolved',
      'resolved_at': now,
      'updated_at': now,
    })
        .eq('id', alertId)
        .eq('caregiver_id', caregiverId)
        .inFilter('status', ['sent', 'acknowledged'])
        .select('id');

    if ((updated as List).isEmpty) {
      throw const SosDispatchException(
        'Alert was not found or has already been resolved.',
      );
    }
  }

  Future<void> cancelPatientAlert(String alertId) async {
    final patientId = _requireCurrentUserId();
    final now = DateTime.now().toUtc().toIso8601String();

    await supabase
        .from('sos_alerts')
        .update({
      'status': 'cancelled',
      'updated_at': now,
    })
        .eq('id', alertId)
        .eq('patient_id', patientId)
        .eq('status', 'sent');
  }
}