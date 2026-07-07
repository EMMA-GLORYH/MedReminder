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
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phoneNumber: json['phone_number'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String?,
      timezone: json['timezone'] as String,
      signupMethod: json['signup_method'] as String?,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
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

  /// Helpers
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