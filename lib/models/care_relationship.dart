// lib/models/care_relationship.dart
//
// profiles.full_name is `NOT NULL DEFAULT ''` — an empty string is a
// legitimate stored value, not a missing one. `json['full_name'] ?? 'x'`
// would NOT catch that (?? only substitutes on null), which is why a
// caretaker/patient card could end up rendering with a blank name. Every
// getter below explicitly checks for '' as well as null before falling
// back to a friendly placeholder.

class CareRelationship {
  final String id;
  final String patientId;
  final String caregiverId;
  final String? relationship;
  final bool canViewLogs;
  final bool canViewMedications;
  final bool canReceiveAlerts;
  final bool canEditMedications;
  final int alertThresholdMins;
  final String status; // 'pending' | 'active' | 'revoked'
  final DateTime invitedAt;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  // The joined profiles row for "the other party" relative to how this
  // object was loaded — see fromJson vs fromJsonAsCaretaker below.
  final String? otherPartyFullName;
  final String? otherPartyPhone;
  final String? otherPartyAvatarUrl;
  final String? otherPartyRole; // profiles.role: patient | caretaker | caregiver

  const CareRelationship({
    required this.id,
    required this.patientId,
    required this.caregiverId,
    this.relationship,
    required this.canViewLogs,
    required this.canViewMedications,
    required this.canReceiveAlerts,
    required this.canEditMedications,
    required this.alertThresholdMins,
    required this.status,
    required this.invitedAt,
    this.acceptedAt,
    required this.createdAt,
    this.otherPartyFullName,
    this.otherPartyPhone,
    this.otherPartyAvatarUrl,
    this.otherPartyRole,
  });

  bool get isPending => status == 'pending';
  bool get isActive  => status == 'active';
  bool get isRevoked => status == 'revoked';

  // ── Joined-profile parsing helpers ──────────────────────────────
  static Map<String, dynamic>? _profileMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    // Supabase can return a to-one embed as a single-item list depending
    // on the FK relationship's inferred cardinality — handle both shapes.
    if (raw is List && raw.isNotEmpty) return raw.first as Map<String, dynamic>;
    return null;
  }

  /// Trims and treats '' the same as null — the actual fix for
  /// `full_name`'s `NOT NULL DEFAULT ''`.
  static String? _cleanString(Map<String, dynamic>? profile, String key) {
    final value = profile?[key] as String?;
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ── Loaders ──────────────────────────────────────────────────────

  /// Use when the CURRENT USER is the patient, looking at their
  /// caretaker. Expects Supabase's embed key `profiles` to be the
  /// caregiver's profile — matches
  /// `profiles!care_relationships_caregiver_id_fkey(full_name, phone_number, avatar_url)`
  /// used in CareRelationshipService.getMyCaretakers.
  factory CareRelationship.fromJson(Map<String, dynamic> json) {
    final profile = _profileMap(json['profiles']);
    return CareRelationship(
      id:                  json['id'] as String,
      patientId:           json['patient_id'] as String,
      caregiverId:         json['caregiver_id'] as String,
      relationship:        json['relationship'] as String?,
      canViewLogs:         json['can_view_logs'] as bool? ?? false,
      canViewMedications:  json['can_view_medications'] as bool? ?? false,
      canReceiveAlerts:    json['can_receive_alerts'] as bool? ?? false,
      canEditMedications:  json['can_edit_medications'] as bool? ?? false,
      alertThresholdMins:  json['alert_threshold_mins'] as int? ?? 30,
      status:              json['status'] as String? ?? 'pending',
      invitedAt:           DateTime.parse(json['invited_at'] as String),
      acceptedAt:          json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      createdAt:           DateTime.parse(json['created_at'] as String),
      otherPartyFullName:  _cleanString(profile, 'full_name'),
      otherPartyPhone:     _cleanString(profile, 'phone_number'),
      otherPartyAvatarUrl: _cleanString(profile, 'avatar_url'),
      otherPartyRole:      _cleanString(profile, 'role'),
    );
  }

  /// Use when the CURRENT USER is the caretaker, looking at a patient.
  /// CareRelationshipService manually copies the joined patient profile
  /// into `_patient_profile` before calling this (see getPendingInvites,
  /// getPendingInvitesPage, getPatientsIMonitor) — matches
  /// `profiles!care_relationships_patient_id_fkey(full_name, phone_number, avatar_url)`.
  factory CareRelationship.fromJsonAsCaretaker(Map<String, dynamic> json) {
    final profile = _profileMap(json['_patient_profile']);
    return CareRelationship(
      id:                  json['id'] as String,
      patientId:           json['patient_id'] as String,
      caregiverId:         json['caregiver_id'] as String,
      relationship:        json['relationship'] as String?,
      canViewLogs:         json['can_view_logs'] as bool? ?? false,
      canViewMedications:  json['can_view_medications'] as bool? ?? false,
      canReceiveAlerts:    json['can_receive_alerts'] as bool? ?? false,
      canEditMedications:  json['can_edit_medications'] as bool? ?? false,
      alertThresholdMins:  json['alert_threshold_mins'] as int? ?? 30,
      status:              json['status'] as String? ?? 'pending',
      invitedAt:           DateTime.parse(json['invited_at'] as String),
      acceptedAt:          json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      createdAt:           DateTime.parse(json['created_at'] as String),
      otherPartyFullName:  _cleanString(profile, 'full_name'),
      otherPartyPhone:     _cleanString(profile, 'phone_number'),
      otherPartyAvatarUrl: _cleanString(profile, 'avatar_url'),
      otherPartyRole:      _cleanString(profile, 'role'),
    );
  }

  // ── Display getters used by manage_caretakers_screen.dart and
  //    pending_invites_screen.dart ──────────────────────────────────

  /// Never blank: falls back to a status-aware placeholder instead of an
  /// empty string when full_name is null OR ''.
  String get displayName =>
      otherPartyFullName ?? (isPending ? 'Invited user' : 'Unnamed user');

  String get displayPhone => otherPartyPhone ?? '';
  String get displayAvatar => otherPartyAvatarUrl ?? '';

  // Aliases used by manage_caretakers_screen.dart's _CaretakerCard/_Avatar
  String get profilePhone => otherPartyPhone ?? '';
  String? get profileAvatarUrl => otherPartyAvatarUrl;

  // ── Caretaker-view specific aliases (used by caretaker_profile_tab.dart) ──

  /// The patient's full name. Falls back to 'Patient' if not available.
  String get patientName => otherPartyFullName ?? 'Patient';

  /// The patient's phone number.
  String? get patientPhone => otherPartyPhone;

  /// The patient's avatar URL.
  String? get patientAvatarUrl => otherPartyAvatarUrl;

  /// Human label for the joined profile's account role, for anywhere the
  /// UI wants to confirm "this person signed up as a Caretaker" etc.
  String get otherPartyRoleLabel {
    switch (otherPartyRole) {
      case 'patient':   return 'Patient';
      case 'caretaker': return 'Caretaker';
      case 'caregiver': return 'Caregiver';
      default:          return '';
    }
  }

  /// Label for care_relationships.relationship (family/doctor/etc) — a
  /// distinct concept from profiles.role above.
  String get relationshipLabel {
    switch (relationship) {
      case 'family':    return 'Family';
      case 'doctor':    return 'Doctor';
      case 'nurse':     return 'Nurse';
      case 'caregiver': return 'Caregiver';
      case 'caretaker': return 'Caretaker';
      default:          return 'Not specified';
    }
  }
}