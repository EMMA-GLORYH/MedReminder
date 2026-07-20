// lib/services/sos_service.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'auth_service.dart';
import 'sos_location_service.dart';

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

    return phone != null &&
        phone.trim().isNotEmpty;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
    };
  }

  factory SosCaretakerContact.fromJson(
      Map<String, dynamic> json,
      ) {
    return SosCaretakerContact(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Caretaker',
      phoneNumber: json['phoneNumber']?.toString(),
    );
  }
}

class SosDispatchResult {
  final List<String> alertIds;
  final List<SosCaretakerContact> caretakers;
  final String requestKey;
  final bool deliveredBySms;

  const SosDispatchResult({
    required this.alertIds,
    required this.caretakers,
    required this.requestKey,
    this.deliveredBySms = false,
  });

  int get caretakerCount => caretakers.length;

  SosCaretakerContact? get firstCallableCaretaker {
    for (final caretaker in caretakers) {
      if (caretaker.hasPhoneNumber) {
        return caretaker;
      }
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

  static final SosService instance =
  SosService._();

  static const MethodChannel _smsChannel =
  MethodChannel('sos_sms_fallback');

  static const String _cachedCaretakersKey =
      'cached_sos_caretaker_contacts_v1';

  String _requireCurrentUserId() {
    final userId =
        AuthService.instance.currentUser?.id;

    if (userId == null) {
      throw const SosDispatchException(
        'You must be signed in before sending an SOS.',
      );
    }

    return userId;
  }

  // ══════════════════════════════════════════════════════════════
  // SEND SOS
  // ══════════════════════════════════════════════════════════════

  Future<SosDispatchResult> sendSos({
    String message =
    'Patient requested urgent assistance',
  }) async {
    final patientId = _requireCurrentUserId();

    final requestKey =
        '${patientId}_'
        '${DateTime.now().toUtc().microsecondsSinceEpoch}';

    /*
     * First try to use the current online caretaker relationships.
     * This also refreshes the locally cached phone numbers.
     */
    List<SosCaretakerContact> cachedContacts =
    await _readCachedCaretakers();

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

      final relationships =
      List<Map<String, dynamic>>.from(
        rawRelationships as List,
      );

      final eligible = relationships.where(
            (relationship) {
          final status =
          relationship['status']?.toString();

          final canReceiveAlerts =
              relationship['can_receive_alerts'] != false;

          return status == 'active' &&
              canReceiveAlerts;
        },
      ).toList();

      if (eligible.isEmpty) {
        throw _relationshipError(relationships);
      }

      final location =
      await SosLocationService.instance
          .getCurrentLocation();

      final response = await supabase.rpc(
        'create_sos_alerts',
        params: <String, dynamic>{
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
          'The SOS could not be delivered to your '
              'active caretaker.',
        );
      }

      final alertIds = <String>[];
      final contacts =
      <String, SosCaretakerContact>{};

      for (final row in rows) {
        final alertId =
        row['alert_id']?.toString();

        final caregiverId =
        row['caregiver_id']?.toString();

        if (alertId != null &&
            alertId.isNotEmpty) {
          alertIds.add(alertId);
        }

        if (caregiverId == null ||
            caregiverId.isEmpty) {
          continue;
        }

        contacts[caregiverId] =
            SosCaretakerContact(
              id: caregiverId,
              name: row['caregiver_name']
                  ?.toString() ??
                  'Caretaker',
              phoneNumber:
              row['caregiver_phone']?.toString(),
            );
      }

      if (contacts.isEmpty) {
        throw const SosDispatchException(
          'The SOS was created, but caretaker '
              'contact details were unavailable.',
        );
      }

      final currentContacts =
      contacts.values.toList();

      /*
       * Cache numbers while online. These are used if a later SOS occurs
       * when the patient has no internet connection.
       */
      await _writeCachedCaretakers(
        currentContacts,
      );

      debugPrint(
        '✅ SOS delivered online to '
            '${currentContacts.length} caretaker(s)',
      );

      return SosDispatchResult(
        alertIds: alertIds,
        caretakers: currentContacts,
        requestKey: requestKey,
        deliveredBySms: false,
      );
    } catch (error, stack) {
      debugPrint(
        '⚠️ Online SOS dispatch failed: $error',
      );
      debugPrint('$stack');

      /*
       * Do not use SMS for authentication/relationship errors when we know
       * the patient has no eligible caretaker. For network/RPC failures,
       * use previously cached caretaker contacts.
       */
      if (error is SosDispatchException &&
          _isRelationshipError(error)) {
        rethrow;
      }

      cachedContacts = cachedContacts
          .where((caretaker) => caretaker.hasPhoneNumber)
          .toList();

      if (cachedContacts.isEmpty) {
        throw const SosDispatchException(
          'SOS could not be sent online, and no cached '
              'caretaker phone numbers are available for SMS.',
        );
      }

      final location =
      await SosLocationService.instance
          .getCurrentLocation();

      final smsBody = _buildSmsBody(
        requestKey: requestKey,
        patientName: await _patientName(),
        location: location,
      );

      try {
        final sentCount =
        await _sendSmsFallback(
          caretakers: cachedContacts,
          body: smsBody,
        );

        if (sentCount <= 0) {
          throw const SosDispatchException(
            'SMS fallback could not be sent to any caretaker.',
          );
        }

        debugPrint(
          '✅ SOS SMS fallback sent to '
              '$sentCount caretaker(s)',
        );

        return SosDispatchResult(
          alertIds: const <String>[],
          caretakers: cachedContacts,
          requestKey: requestKey,
          deliveredBySms: true,
        );
      } catch (smsError, smsStack) {
        debugPrint(
          '❌ SOS SMS fallback failed: $smsError',
        );
        debugPrint('$smsStack');

        throw SosDispatchException(
          'Could not send the SOS online or by SMS. '
              'Please call your caretaker directly.',
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SMS FALLBACK
  // ══════════════════════════════════════════════════════════════

  Future<int> _sendSmsFallback({
    required List<SosCaretakerContact> caretakers,
    required String body,
  }) async {
    final recipients = caretakers
        .where((caretaker) => caretaker.hasPhoneNumber)
        .map((caretaker) => caretaker.phoneNumber!.trim())
        .toSet()
        .toList();

    if (recipients.isEmpty) {
      return 0;
    }

    final result =
    await _smsChannel.invokeMethod<int>(
      'sendSosSms',
      <String, dynamic>{
        'recipients': recipients,
        'message': body,
      },
    );

    return result ?? 0;
  }

  String _buildSmsBody({
    required String requestKey,
    required String patientName,
    required SosLocation? location,
  }) {
    final safeName = patientName
        .replaceAll('|', ' ')
        .replaceAll('\n', ' ')
        .trim();

    final coordinates =
    location == null
        ? ''
        : ' | g:${location.latitude},'
        '${location.longitude}';

    return 'MAR-SOS k:$requestKey | '
        'n:${safeName.isEmpty ? 'A patient' : safeName}'
        '$coordinates';
  }

  Future<String> _patientName() async {
    try {
      final profile =
      await AuthService.instance.getCurrentProfile();

      final name = profile?.fullName.trim();

      if (name != null && name.isNotEmpty) {
        return name;
      }
    } catch (_) {}

    return 'A patient';
  }

  // ══════════════════════════════════════════════════════════════
  // CARETAKER CACHE
  // ══════════════════════════════════════════════════════════════

  Future<void> _writeCachedCaretakers(
      List<SosCaretakerContact> contacts,
      ) async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      await preferences.setString(
        _cachedCaretakersKey,
        jsonEncode(
          contacts.map((contact) => contact.toJson()).toList(),
        ),
      );
    } catch (error) {
      debugPrint(
        '⚠️ Could not cache caretaker contacts: $error',
      );
    }
  }

  Future<List<SosCaretakerContact>>
  _readCachedCaretakers() async {
    try {
      final preferences =
      await SharedPreferences.getInstance();

      final raw = preferences.getString(
        _cachedCaretakersKey,
      );

      if (raw == null || raw.trim().isEmpty) {
        return <SosCaretakerContact>[];
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <SosCaretakerContact>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => SosCaretakerContact.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
          .where(
            (contact) => contact.id.isNotEmpty,
      )
          .toList();
    } catch (error) {
      debugPrint(
        '⚠️ Could not read cached caretaker contacts: $error',
      );

      return <SosCaretakerContact>[];
    }
  }

  bool _isRelationshipError(
      SosDispatchException error,
      ) {
    return error.message.contains(
      'invitation is still pending',
    ) ||
        error.message.contains(
          'connection was revoked',
        ) ||
        error.message.contains(
          'alerts are disabled',
        ) ||
        error.message.contains(
          'No active caretaker',
        );
  }

  SosDispatchException _relationshipError(
      List<Map<String, dynamic>> relationships,
      ) {
    final hasPending = relationships.any(
          (relationship) =>
      relationship['status']?.toString() ==
          'pending',
    );

    final hasRevoked = relationships.any(
          (relationship) =>
      relationship['status']?.toString() ==
          'revoked',
    );

    final hasDisabled = relationships.any(
          (relationship) =>
      relationship['status']?.toString() ==
          'active' &&
          relationship['can_receive_alerts'] ==
              false,
    );

    if (hasPending) {
      return const SosDispatchException(
        'Your caretaker invitation is still pending. '
            'The caretaker must accept it before receiving SOS alerts.',
      );
    }

    if (hasRevoked) {
      return const SosDispatchException(
        'Your previous caretaker connection was revoked. '
            'Invite the caretaker again and wait for acceptance.',
      );
    }

    if (hasDisabled) {
      return const SosDispatchException(
        'Your caretaker is connected, but SOS alerts are disabled.',
      );
    }

    return const SosDispatchException(
      'No active caretaker is currently available to receive SOS alerts.',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EXISTING CARETAKER METHODS
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getCaretakerAlerts({
    String? patientId,
  }) async {
    final caregiverId = _requireCurrentUserId();

    var query = supabase
        .from('sos_alerts')
        .select('''
        id,
        relationship_id,
        patient_id,
        caregiver_id,
        request_key,
        patient_name,
        message,
        status,
        latitude,
        longitude,
        location_accuracy_m,
        location_captured_at,
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
      ''')
        .eq('caregiver_id', caregiverId);

    final selectedPatientId = patientId?.trim();

    if (selectedPatientId != null &&
        selectedPatientId.isNotEmpty) {
      query = query.eq(
        'patient_id',
        selectedPatientId,
      );
    }

    final data = await query
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

  Future<void> acknowledgeAlert(
      String alertId,
      ) async {
    final caregiverId = _requireCurrentUserId();
    final now = DateTime.now()
        .toUtc()
        .toIso8601String();

    final updated = await supabase
        .from('sos_alerts')
        .update(<String, dynamic>{
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

  Future<void> resolveAlert(
      String alertId,
      ) async {
    final caregiverId = _requireCurrentUserId();
    final now = DateTime.now()
        .toUtc()
        .toIso8601String();

    final updated = await supabase
        .from('sos_alerts')
        .update(<String, dynamic>{
      'status': 'resolved',
      'resolved_at': now,
      'updated_at': now,
    })
        .eq('id', alertId)
        .eq('caregiver_id', caregiverId)
        .inFilter(
      'status',
      const <String>[
        'sent',
        'acknowledged',
      ],
    )
        .select('id');

    if ((updated as List).isEmpty) {
      throw const SosDispatchException(
        'Alert was not found or has already been resolved.',
      );
    }
  }

  Future<void> cancelPatientAlert(
      String alertId,
      ) async {
    final patientId = _requireCurrentUserId();
    final now = DateTime.now()
        .toUtc()
        .toIso8601String();

    await supabase
        .from('sos_alerts')
        .update(<String, dynamic>{
      'status': 'cancelled',
      'updated_at': now,
    })
        .eq('id', alertId)
        .eq('patient_id', patientId)
        .eq('status', 'sent');
  }
}