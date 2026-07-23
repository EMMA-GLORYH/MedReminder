// lib/services/auth_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mar/main.dart';
import 'package:mar/models/profile.dart';
import 'package:mar/services/dose_log_service.dart';

class AuthService {
  AuthService._internal();

  static final AuthService _instance = AuthService._internal();

  static AuthService get instance => _instance;

  StreamSubscription<AuthState>? _authSubscription;
  bool _authSyncListenerStarted = false;

  // ✅ NEW: Token refresh tracking
  DateTime? _lastTokenRefresh;
  static const Duration _tokenRefreshThreshold = Duration(minutes: 5);

  // ══════════════════════════════════════════════════════════════
  // CURRENT SESSION
  // ══════════════════════════════════════════════════════════════

  User? get currentUser {
    try {
      return supabase.auth.currentUser;
    } catch (error) {
      debugPrint('⚠️ Could not read the current Supabase user: $error');
      return null;
    }
  }

  Session? get currentSession {
    try {
      return supabase.auth.currentSession;
    } catch (error) {
      debugPrint('⚠️ Could not read the current Supabase session: $error');
      return null;
    }
  }

  bool get isLoggedIn => currentSession != null;

  // ══════════════════════════════════════════════════════════════
  // AUTH STATE STREAM
  // ══════════════════════════════════════════════════════════════

  Stream<AuthState> get authStateChanges {
    _ensurePendingDoseSyncListener();
    return supabase.auth.onAuthStateChange;
  }

  // ══════════════════════════════════════════════════════════════
  // ✅ NEW: TOKEN REFRESH METHODS
  // ══════════════════════════════════════════════════════════════

  /// Ensures we have a valid token. Refreshes if expiring soon.
  Future<bool> ensureValidToken() async {
    try {
      final session = currentSession;
      if (session == null) return false;

      final expiresAt = session.expiresAt;
      if (expiresAt == null) return true;

      final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      final timeUntilExpiry = expiryTime.difference(DateTime.now());

      if (timeUntilExpiry.inMinutes < 5) {
        debugPrint('🔄 Token expiring soon — refreshing...');
        final response = await supabase.auth.refreshSession();
        if (response.session != null) {
          _lastTokenRefresh = DateTime.now();
          debugPrint('✅ Token refreshed successfully');
          return true;
        }
      }
      return true;
    } catch (e) {
      debugPrint('❌ Token refresh failed: $e');
      return false;
    }
  }

  /// Gets a valid session (refreshes token if needed)
  Future<Session?> getValidSession() async {
    await ensureValidToken();
    return currentSession;
  }

  // ══════════════════════════════════════════════════════════════
  // PENDING DOSE SYNCHRONIZATION
  // ══════════════════════════════════════════════════════════════

  void initializePendingDoseSync() {
    _ensurePendingDoseSyncListener();

    if (currentSession != null) {
      _schedulePendingDoseSync(reason: 'existing session');
    }
  }

  void _ensurePendingDoseSyncListener() {
    if (_authSyncListenerStarted) return;

    try {
      _authSyncListenerStarted = true;

      _authSubscription = supabase.auth.onAuthStateChange.listen(
            (AuthState authState) {
          final session = authState.session;
          debugPrint('🔐 Supabase auth event: ${authState.event.name}');

          if (session != null) {
            _schedulePendingDoseSync(reason: authState.event.name);
          }
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('⚠️ Authentication state listener failed: $error');
          debugPrint('$stack');
        },
      );

      debugPrint('✅ Pending dose synchronization listener started');
    } catch (error, stack) {
      _authSyncListenerStarted = false;
      debugPrint('⚠️ Could not start authentication listener: $error');
      debugPrint('$stack');
    }
  }

  void _schedulePendingDoseSync({required String reason}) {
    debugPrint('🔄 Scheduling pending dose synchronization: $reason');
    unawaited(_synchronizePendingDoseLogs());
  }

  Future<void> _synchronizePendingDoseLogs() async {
    try {
      await DoseLogService.instance.syncPendingDoseLogs();
    } catch (error, stack) {
      debugPrint('⚠️ Pending dose synchronization failed: $error');
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // EMAIL SIGN UP
  // ══════════════════════════════════════════════════════════════

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? role,
    String? phoneNumber,
    String timezone = 'UTC',
  }) async {
    _ensurePendingDoseSyncListener();

    final response = await supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: <String, dynamic>{
        'full_name': fullName.trim(),
        'role': _cleanOptionalString(role),
        'phone_number': _cleanOptionalString(phoneNumber),
        'timezone': timezone.trim().isEmpty ? 'UTC' : timezone.trim(),
      },
    );

    if (response.user == null) {
      throw const AuthException('Signup failed. Please try again.');
    }

    if (response.session != null) {
      _schedulePendingDoseSync(reason: 'email signup');
    }

    return response;
  }

  // ══════════════════════════════════════════════════════════════
  // EMAIL SIGN IN
  // ══════════════════════════════════════════════════════════════

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _ensurePendingDoseSyncListener();

    final response = await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('Login failed. Check your credentials.');
    }

    _schedulePendingDoseSync(reason: 'email login');
    return response;
  }

  // ══════════════════════════════════════════════════════════════
  // GOOGLE SIGN IN
  // ══════════════════════════════════════════════════════════════

  Future<bool> signInWithGoogle() async {
    _ensurePendingDoseSyncListener();

    return supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.medreminder://login-callback/',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SIGN OUT
  // ══════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    await supabase.auth.signOut();
    debugPrint('✅ User signed out');
  }

  // ══════════════════════════════════════════════════════════════
  // PASSWORD RESET
  // ══════════════════════════════════════════════════════════════

  Future<void> resetPassword(String email) async {
    final safeEmail = email.trim();
    if (safeEmail.isEmpty) {
      throw const AuthException('An email address is required.');
    }
    await supabase.auth.resetPasswordForEmail(safeEmail);
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    final safeEmail = email.trim();
    if (safeEmail.isEmpty) {
      throw const AuthException('An email address is required.');
    }

    await supabase.auth.resetPasswordForEmail(
      safeEmail,
      redirectTo: 'io.supabase.medreminder://reset-password',
    );

    debugPrint('✅ Password reset email sent to $safeEmail');
  }

  // ══════════════════════════════════════════════════════════════
  // CURRENT USER PROFILE
  // ══════════════════════════════════════════════════════════════

  Future<Profile?> getCurrentProfile() async {
    _ensurePendingDoseSyncListener();

    final user = currentUser;
    if (user == null) return null;

    _schedulePendingDoseSync(reason: 'profile/session restoration');

    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) return null;
    return Profile.fromJson(data);
  }

  // ══════════════════════════════════════════════════════════════
  // COMPLETE ONBOARDING
  // ══════════════════════════════════════════════════════════════

  Future<Profile> completeOnboarding({
    required String role,
    String? phoneNumber,
    String? timezone,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException('Not logged in');
    }

    final safeRole = role.trim();
    if (safeRole.isEmpty) {
      throw const AuthException('A user role is required.');
    }

    final updated = await supabase.from('profiles').update(<String, dynamic>{
      'role': safeRole,
      'phone_number': _cleanOptionalString(phoneNumber),
      'timezone': _cleanOptionalString(timezone) ?? 'UTC',
      'onboarding_completed': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id).select().single();

    _schedulePendingDoseSync(reason: 'onboarding completed');
    return Profile.fromJson(updated);
  }

  // ══════════════════════════════════════════════════════════════
  // CLEANUP
  // ══════════════════════════════════════════════════════════════

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    _authSyncListenerStarted = false;
  }

  String? _cleanOptionalString(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }
}