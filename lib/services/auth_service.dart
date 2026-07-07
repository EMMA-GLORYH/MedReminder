// lib/services/auth_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/profile.dart';

class AuthService {
  // ── Singleton Setup ──
  AuthService._internal();
  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;

  // ── Current Session Info ──
  User? get currentUser => supabase.auth.currentUser;
  Session? get currentSession => supabase.auth.currentSession;
  bool get isLoggedIn => currentSession != null;

  // ── Auth State Stream ──
  Stream<AuthState> get authStateChanges =>
      supabase.auth.onAuthStateChange;

  // ── EMAIL SIGN UP ──
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phoneNumber,
    String timezone = 'UTC',
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'role': role,
        'phone_number': phoneNumber,
        'timezone': timezone,
      },
    );

    if (response.user == null) {
      throw const AuthException('Signup failed. Please try again.');
    }

    return response;
  }

  // ── EMAIL SIGN IN ──
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('Login failed. Check your credentials.');
    }

    return response;
  }

  // ── GOOGLE SIGN IN ──
  Future<bool> signInWithGoogle() async {
    return await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.medreminder://login-callback/',
    );
  }

  // ── SIGN OUT ──
  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // ── PASSWORD RESET ──
  Future<void> resetPassword(String email) async {
    await supabase.auth.resetPasswordForEmail(email);
  }

  // ── FETCH CURRENT USER PROFILE ──
  Future<Profile?> getCurrentProfile() async {
    if (!isLoggedIn) return null;

    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', currentUser!.id)
        .maybeSingle();

    if (data == null) return null;
    return Profile.fromJson(data);
  }

  // ── COMPLETE ONBOARDING ──
  Future<Profile> completeOnboarding({
    required String role,
    String? phoneNumber,
    String? timezone,
  }) async {
    if (!isLoggedIn) {
      throw const AuthException('Not logged in');
    }

    final updated = await supabase
        .from('profiles')
        .update({
      'role': role,
      'phone_number': phoneNumber,
      'timezone': timezone ?? 'UTC',
      'onboarding_completed': true,
      'updated_at': DateTime.now().toIso8601String(),
    })
        .eq('id', currentUser!.id)
        .select()
        .single();

    return Profile.fromJson(updated);
  }
}