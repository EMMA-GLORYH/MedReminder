// lib/services/care_relationship_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/care_relationship.dart';
import 'auth_service.dart';

class CareRelationshipService {
  CareRelationshipService._();
  static final CareRelationshipService instance = CareRelationshipService._();

  // ══════════════════════════════════════════════════════════════
  // PATIENT SIDE — Send an invite to a caretaker by email
  // ══════════════════════════════════════════════════════════════
  Future<CareRelationship> inviteCaretaker({
    required String caretakerEmail,
    String? relationship,
    bool canEditMedications = false,
    int  alertThresholdMins = 30,
  }) async {
    final patientId = AuthService.instance.currentUser?.id;
    if (patientId == null) throw Exception('Not logged in');

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📨 INVITE CARETAKER START');
    debugPrint('   Patient ID : $patientId');
    debugPrint('   Email      : $caretakerEmail');

    // ── Step 1: Resolve email → UUID via RPC ──────────────────
    String caretakerId;
    try {
      caretakerId = await _getProfileIdByEmail(caretakerEmail);
      debugPrint('✅ Step 1 — Caretaker UUID: $caretakerId');
    } catch (e) {
      debugPrint('❌ Step 1 FAILED — RPC error: $e');
      throw Exception(
        'No MedReminder account found for $caretakerEmail.\n'
            'Ask them to sign up on MedReminder first.',
      );
    }

    // ── Step 2: Self-invite guard ──────────────────────────────
    if (caretakerId == patientId) {
      throw Exception('You cannot add yourself as a caretaker.');
    }

    // ── Step 3: Check for existing relationship ────────────────
    debugPrint('🔍 Step 3 — Checking existing relationship...');
    final existing = await supabase
        .from('care_relationships')
        .select('id, status')
        .eq('patient_id',   patientId)
        .eq('caregiver_id', caretakerId)
        .maybeSingle();

    debugPrint('   Existing row: $existing');

    if (existing != null) {
      final s = existing['status'] as String;
      debugPrint('   Existing status: $s');

      if (s == 'active') {
        throw Exception('This person is already your active caretaker.');
      }
      if (s == 'pending') {
        throw Exception('An invite is already pending for this person.');
      }
      if (s == 'revoked') {
        debugPrint(
          '🔄 Re-inviting previously revoked caretaker',
        );

        final now = DateTime.now().toUtc().toIso8601String();

        final updated = await supabase
            .from('care_relationships')
            .update({
          'status': 'pending',
          'relationship': relationship,

          // Restore the standard permissions for the new invitation.
          'can_view_logs': true,
          'can_view_medications': true,
          'can_receive_alerts': true,
          'can_edit_medications': canEditMedications,

          'alert_threshold_mins': alertThresholdMins,
          'invited_at': now,
          'accepted_at': null,
        })
            .eq('id', existing['id'] as String)
            .eq('patient_id', patientId)
            .eq('status', 'revoked')
            .select()
            .maybeSingle();

        if (updated == null) {
          throw Exception(
            'The caretaker could not be invited again. Please refresh and retry.',
          );
        }

        debugPrint(
          '✅ Revoked relationship restored to pending: ${updated['id']}',
        );

        await _sendInviteEmail(updated['id'] as String);

        return CareRelationship.fromJson(updated);
      }
    }

    // ── Step 4: Insert new pending invite ─────────────────────
    debugPrint('📝 Step 4 — Inserting new invite row...');
    debugPrint('   patient_id  : $patientId');
    debugPrint('   caregiver_id: $caretakerId');
    debugPrint('   relationship: $relationship');

    try {
      final data = await supabase
          .from('care_relationships')
          .insert({
        'patient_id':           patientId,
        'caregiver_id':         caretakerId,
        'relationship':         relationship,
        'can_view_logs':        true,
        'can_view_medications': true,
        'can_receive_alerts':   true,
        'can_edit_medications': canEditMedications,
        'alert_threshold_mins': alertThresholdMins,
        'status':               'pending',
      })
          .select()
          .single();

      debugPrint('✅ Step 4 — Row inserted: ${data['id']}');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Fire email notification via Edge Function (non-fatal)
      await _sendInviteEmail(data['id'] as String);

      return CareRelationship.fromJson(data);
    } catch (e) {
      debugPrint('❌ Step 4 FAILED — Insert error: $e');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // Give a clear message instead of raw Supabase error
      if (e.toString().contains('row-level security') ||
          e.toString().contains('RLS') ||
          e.toString().contains('permission')) {
        throw Exception(
          'Permission error. Please check your Supabase RLS policies '
              'for the care_relationships table.',
        );
      }
      rethrow;
    }
  }

  // ── Send invite email via Edge Function ────────────────────
  Future<void> _sendInviteEmail(String relationshipId) async {
    try {
      debugPrint('📧 Triggering invite email for: $relationshipId');
      final response = await supabase.functions.invoke(
        'send-caretaker-invite',
        body: {'relationship_id': relationshipId},
      );
      debugPrint('📧 Email function response: ${response.data}');
    } catch (e) {
      // Email failure must NOT block the invite — row is already saved
      debugPrint('⚠️ Email send failed (non-fatal): $e');
    }
  }

  // ── Resend invite email for an existing pending row ────────
  Future<void> resendInviteEmail(String relationshipId) async {
    final patientId = AuthService.instance.currentUser?.id;
    if (patientId == null) throw Exception('Not logged in');

    // Confirm the row is still pending and belongs to this patient
    final row = await supabase
        .from('care_relationships')
        .select('id, status')
        .eq('id',         relationshipId)
        .eq('patient_id', patientId)
        .eq('status',     'pending')
        .maybeSingle();

    if (row == null) {
      throw Exception('Invite not found or no longer pending.');
    }

    await _sendInviteEmail(relationshipId);
    debugPrint('📧 Invite email resent for: $relationshipId');
  }

  // ══════════════════════════════════════════════════════════════
  // PATIENT SIDE — Manage caretakers
  // ══════════════════════════════════════════════════════════════

  Future<List<CareRelationship>> getMyCaretakers() async {
    final patientId = AuthService.instance.currentUser?.id;
    if (patientId == null) throw Exception('Not logged in');

    final data = await supabase
        .from('care_relationships')
        .select('''
          *,
          profiles!care_relationships_caregiver_id_fkey(
            full_name, phone_number, avatar_url
          )
        ''')
        .eq('patient_id', patientId)
        .neq('status', 'revoked')
        .order('created_at', ascending: false);

    return (data as List)
        .map((j) => CareRelationship.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeCaretaker(String relationshipId) async {
    final patientId = AuthService.instance.currentUser?.id;
    if (patientId == null) throw Exception('Not logged in');

    await supabase
        .from('care_relationships')
        .update({'status': 'revoked'})
        .eq('id',         relationshipId)
        .eq('patient_id', patientId);

    debugPrint('🗑️ Caretaker revoked: $relationshipId');
  }

  Future<CareRelationship> updatePermissions({
    required String relationshipId,
    bool? canViewLogs,
    bool? canViewMedications,
    bool? canReceiveAlerts,
    bool? canEditMedications,
    int?  alertThresholdMins,
  }) async {
    final updates = <String, dynamic>{};
    if (canViewLogs        != null) updates['can_view_logs']        = canViewLogs;
    if (canViewMedications != null) updates['can_view_medications'] = canViewMedications;
    if (canReceiveAlerts   != null) updates['can_receive_alerts']   = canReceiveAlerts;
    if (canEditMedications != null) updates['can_edit_medications'] = canEditMedications;
    if (alertThresholdMins != null) updates['alert_threshold_mins'] = alertThresholdMins;

    final data = await supabase
        .from('care_relationships')
        .update(updates)
        .eq('id', relationshipId)
        .select()
        .single();

    return CareRelationship.fromJson(data);
  }

  // ══════════════════════════════════════════════════════════════
  // CARETAKER SIDE — Pending invites inbox
  // ══════════════════════════════════════════════════════════════

  /// Fetch ALL pending invites for the current caretaker in one shot.
  /// Kept unchanged for any existing callers that need a complete list.
  /// For the Pending Invites screen itself, prefer [getPendingInvitesPage]
  /// so the UI never has to render an unbounded number of cards at once.
  Future<List<CareRelationship>> getPendingInvites() async {
    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) throw Exception('Not logged in');

    final data = await supabase
        .from('care_relationships')
        .select('''
          *,
          profiles!care_relationships_patient_id_fkey(
            full_name, phone_number, avatar_url
          )
        ''')
        .eq('caregiver_id', caregiverId)
        .eq('status', 'pending')
        .order('invited_at', ascending: false);

    return (data as List).map((j) {
      final map = Map<String, dynamic>.from(j as Map<String, dynamic>);
      map['_patient_profile'] = map['profiles'];
      return CareRelationship.fromJsonAsCaretaker(map);
    }).toList();
  }

  /// Fetch one indexed page of pending invites, most recently invited
  /// first. Backed by Postgres `.range()`, so only the requested rows are
  /// ever transferred or rendered — e.g. offset: 0, limit: 10 gets
  /// invites 0..9; offset: 10, limit: 10 gets invites 10..19.
  Future<List<CareRelationship>> getPendingInvitesPage({
    required int offset,
    required int limit,
  }) async {
    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) throw Exception('Not logged in');

    debugPrint('📋 Fetching pending invites page (offset=$offset, limit=$limit)');

    final data = await supabase
        .from('care_relationships')
        .select('''
          *,
          profiles!care_relationships_patient_id_fkey(
            full_name, phone_number, avatar_url
          )
        ''')
        .eq('caregiver_id', caregiverId)
        .eq('status', 'pending')
        .order('invited_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((j) {
      final map = Map<String, dynamic>.from(j as Map<String, dynamic>);
      map['_patient_profile'] = map['profiles'];
      return CareRelationship.fromJsonAsCaretaker(map);
    }).toList();
  }

  /// Lightweight count of pending invites, without transferring any row
  /// data — used for the badge count in the AppBar / dashboard even
  /// though the list itself is paginated.
  Future<int> getPendingInviteCount() async {
    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) return 0;
    try {
      final response = await supabase
          .from('care_relationships')
          .select('id')
          .eq('caregiver_id', caregiverId)
          .eq('status', 'pending')
          .count(CountOption.exact);
      return response.count;
    } catch (_) {
      return 0;
    }
  }

  /// Accept — updates status to 'active' and stamps accepted_at
  Future<CareRelationship> acceptInvite(
      String relationshipId,
      ) async {
    final caregiverId =
        AuthService.instance.currentUser?.id;

    if (caregiverId == null) {
      throw Exception('Not logged in');
    }

    debugPrint('✅ Accepting invite: $relationshipId');

    final now = DateTime.now().toUtc().toIso8601String();

    final data = await supabase
        .from('care_relationships')
        .update({
      'status': 'active',
      'accepted_at': now,

      // Every newly accepted invitation can receive SOS alerts.
      'can_receive_alerts': true,
    })
        .eq('id', relationshipId)
        .eq('caregiver_id', caregiverId)
        .eq('status', 'pending')
        .select()
        .maybeSingle();

    if (data == null) {
      throw Exception(
        'This invite is no longer pending or does not belong to you.',
      );
    }

    debugPrint(
      '✅ Invite accepted: ${data['id']}, status: ${data['status']}',
    );

    return CareRelationship.fromJson(data);
  }

  /// Decline — sets status to 'revoked'
  Future<void> declineInvite(String relationshipId) async {
    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) throw Exception('Not logged in');

    await supabase
        .from('care_relationships')
        .update({'status': 'revoked'})
        .eq('id',           relationshipId)
        .eq('caregiver_id', caregiverId)
        .eq('status',       'pending');

    debugPrint('❌ Invite declined: $relationshipId');
  }

  Future<List<CareRelationship>> getPatientsIMonitor() async {
    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) throw Exception('Not logged in');

    final data = await supabase
        .from('care_relationships')
        .select('''
          *,
          profiles!care_relationships_patient_id_fkey(
            full_name, phone_number, avatar_url
          )
        ''')
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .order('accepted_at', ascending: false);

    return (data as List).map((j) {
      final map = Map<String, dynamic>.from(j as Map<String, dynamic>);
      map['_patient_profile'] = map['profiles'];
      return CareRelationship.fromJsonAsCaretaker(map);
    }).toList();
  }

  /// Fetch one indexed page of active patients this caretaker monitors,
  /// most recently accepted first. Backed by Postgres `.range()`, so only
  /// the requested rows are ever transferred or rendered.
  Future<List<CareRelationship>> getPatientsIMonitorPage({
    required int offset,
    required int limit,
  }) async {
    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) throw Exception('Not logged in');

    debugPrint('📋 Fetching monitored patients page (offset=$offset, limit=$limit)');

    final data = await supabase
        .from('care_relationships')
        .select('''
          *,
          profiles!care_relationships_patient_id_fkey(
            full_name, phone_number, avatar_url
          )
        ''')
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .order('accepted_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((j) {
      final map = Map<String, dynamic>.from(j as Map<String, dynamic>);
      map['_patient_profile'] = map['profiles'];
      return CareRelationship.fromJsonAsCaretaker(map);
    }).toList();
  }

  /// Lightweight count of active patients, without transferring any row
  /// data — used to show an accurate total even though the list itself
  /// is paginated.
  Future<int> getActivePatientCount() async {
    final caregiverId = AuthService.instance.currentUser?.id;
    if (caregiverId == null) return 0;
    try {
      final response = await supabase
          .from('care_relationships')
          .select('id')
          .eq('caregiver_id', caregiverId)
          .eq('status', 'active')
          .count(CountOption.exact);
      return response.count;
    } catch (_) {
      return 0;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // REALTIME — live invite updates for caretaker
  // ══════════════════════════════════════════════════════════════
  RealtimeChannel subscribeToMyInvites(
      void Function() onChanged,
      ) {
    final caregiverId =
        AuthService.instance.currentUser?.id;

    final channel = supabase.channel(
      'care_invites_${caregiverId ?? 'anon'}',
    );

    if (caregiverId == null) {
      return channel;
    }

    channel
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'care_relationships',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'caregiver_id',
        value: caregiverId,
      ),
      callback: (_) => onChanged(),
    )
        .subscribe();

    return channel;
  }

  RealtimeChannel subscribeToMyCaretakers(
      void Function() onChanged,
      ) {
    final patientId =
        AuthService.instance.currentUser?.id;

    final channel = supabase.channel(
      'patient_caretakers_${patientId ?? 'anon'}',
    );

    if (patientId == null) {
      return channel;
    }

    channel
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'care_relationships',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'patient_id',
        value: patientId,
      ),
      callback: (_) => onChanged(),
    )
        .subscribe();

    return channel;
  }

// ══════════════════════════════════════════════════════════════
// SOS SUPPORT
// ══════════════════════════════════════════════════════════════

  /// Returns active caregivers who are allowed to receive SOS alerts.
  Future<List<Map<String, dynamic>>> getActiveAlertCaretakers() async {
    final patientId = AuthService.instance.currentUser?.id;

    if (patientId == null) {
      throw Exception('Not logged in');
    }

    final data = await supabase
        .from('care_relationships')
        .select('''
        id,
        caregiver_id,
        relationship,
        status,
        can_receive_alerts,
        profiles!care_relationships_caregiver_id_fkey(
          id,
          full_name,
          phone_number,
          avatar_url
        )
      ''')
        .eq('patient_id', patientId)
        .eq('status', 'active')
        .eq('can_receive_alerts', true)
        .order('accepted_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  /// Returns how many linked caregivers can currently receive an SOS.
  Future<int> getActiveAlertCaretakerCount() async {
    final patientId = AuthService.instance.currentUser?.id;

    if (patientId == null) return 0;

    try {
      final response = await supabase
          .from('care_relationships')
          .select('id')
          .eq('patient_id', patientId)
          .eq('status', 'active')
          .eq('can_receive_alerts', true)
          .count(CountOption.exact);

      return response.count;
    } catch (error) {
      debugPrint('❌ Failed to count alert caregivers: $error');
      return 0;
    }
  }

  /// WebSocket-backed stream of the caregiver's active patient count.
  Stream<int> watchActivePatientCount() {
    final caregiverId = AuthService.instance.currentUser?.id;

    if (caregiverId == null) {
      return Stream<int>.value(0);
    }

    return supabase
        .from('care_relationships')
        .stream(primaryKey: ['id'])
        .eq('caregiver_id', caregiverId)
        .map((rows) {
      return rows.where((row) {
        return row['status']?.toString() == 'active';
      }).length;
    });
  }

  /// Realtime relationship changes for patient or caregiver screens.
  RealtimeChannel subscribeToCareRelationships(
      void Function(PostgresChangePayload payload) onChanged,
      ) {
    final userId = AuthService.instance.currentUser?.id;

    final channel = supabase.channel(
      'care_relationships_realtime_${userId ?? 'anon'}',
    );

    channel
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'care_relationships',
      callback: onChanged,
    )
        .subscribe();

    return channel;
  }

  // ══════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════
  Future<String> _getProfileIdByEmail(String email) async {
    final result = await supabase
        .rpc('get_profile_id_by_email', params: {'p_email': email});

    if (result == null) {
      throw Exception('No MedReminder account found for $email.');
    }
    return result as String;
  }

  // ══════════════════════════════════════════════════════════════
  // CARETAKER PATIENT ACCESS
  // ══════════════════════════════════════════════════════════════

  Future<CareRelationship?> getPatientRelationship(
      String patientId,
      ) async {
    final caregiverId =
        AuthService.instance.currentUser?.id;

    if (caregiverId == null) {
      throw Exception('Not logged in');
    }

    final data = await supabase
        .from('care_relationships')
        .select()
        .eq('patient_id', patientId)
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return CareRelationship.fromJson(
      Map<String, dynamic>.from(data),
    );
  }

  Future<bool> canViewPatientLogs(
      String patientId,
      ) async {
    final relationship =
    await getPatientRelationship(patientId);

    return relationship?.canViewLogs == true;
  }

  Future<bool> canViewPatientMedications(
      String patientId,
      ) async {
    final relationship =
    await getPatientRelationship(patientId);

    return relationship?.canViewMedications == true;
  }

  Future<bool> canReceivePatientAlerts(
      String patientId,
      ) async {
    final relationship =
    await getPatientRelationship(patientId);

    return relationship?.canReceiveAlerts == true;
  }
}