// lib/models/profile.dart

class Profile {
  final String id;
  final String fullName;
  final String? phoneNumber;
  final String? avatarUrl;
  final String? role;
  final String timezone;
  final String? signupMethod;
  final bool onboardingCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    required this.fullName,
    this.phoneNumber,
    this.avatarUrl,
    this.role,
    required this.timezone,
    this.signupMethod,
    required this.onboardingCompleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? 'User',
      phoneNumber: json['phone_number']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      role: json['role']?.toString(),
      timezone: json['timezone']?.toString() ?? 'UTC',
      signupMethod: json['signup_method']?.toString(),
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'avatar_url': avatarUrl,
      'role': role,
      'timezone': timezone,
      'signup_method': signupMethod,
      'onboarding_completed': onboardingCompleted,
    };
  }

  /// Getters & Helpers
  String get firstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'User';
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : trimmed;
  }

  bool get isPatient => role == 'patient';
  bool get isCaretaker => role == 'caretaker';
  bool get needsOnboarding => !onboardingCompleted || role == null;
  bool get signedUpWithGoogle => signupMethod == 'google';
  bool get signedUpWithEmail => signupMethod == 'email';

  Profile copyWith({
    String? fullName,
    String? phoneNumber,
    String? avatarUrl,
    String? role,
    String? timezone,
    bool? onboardingCompleted,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      timezone: timezone ?? this.timezone,
      signupMethod: signupMethod,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}