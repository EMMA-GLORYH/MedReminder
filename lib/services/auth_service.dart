// lib/services/auth_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mar/main.dart';
import 'package:mar/models/profile.dart';
import 'package:mar/services/dose_log_service.dart';

class AuthService {
  AuthService._internal();

  static final AuthService _instance =
  AuthService._internal();

  static AuthService get instance => _instance;

  StreamSubscription<AuthState>? _authSubscription;
  bool _authSyncListenerStarted = false;

  // ══════════════════════════════════════════════════════════════
  // CURRENT SESSION
  // ══════════════════════════════════════════════════════════════

  /// Returns the current Supabase user.
  ///
  /// This returns null instead of throwing when Supabase failed to
  /// initialize. That allows an alarm-opened medication screen to keep
  /// working independently of backend startup.
  User? get currentUser {
    try {
      return supabase.auth.currentUser;
    } catch (error) {
      debugPrint(
        '⚠️ Could not read the current Supabase user: '
            '$error',
      );

      return null;
    }
  }

  /// Returns the current Supabase session, or null if unavailable.
  Session? get currentSession {
    try {
      return supabase.auth.currentSession;
    } catch (error) {
      debugPrint(
        '⚠️ Could not read the current Supabase session: '
            '$error',
      );

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
  // PENDING DOSE SYNCHRONIZATION
  // ══════════════════════════════════════════════════════════════

  /// Starts one listener that retries locally queued dose logs whenever
  /// Supabase reports an authenticated session.
  ///
  /// It is safe to call this method more than once.
  void initializePendingDoseSync() {
    _ensurePendingDoseSyncListener();

    if (currentSession != null) {
      _schedulePendingDoseSync(
        reason: 'existing session',
      );
    }
  }

  void _ensurePendingDoseSyncListener() {
    if (_authSyncListenerStarted) {
      return;
    }

    try {
      _authSyncListenerStarted = true;

      _authSubscription =
          supabase.auth.onAuthStateChange.listen(
                (AuthState authState) {
              final session = authState.session;

              debugPrint(
                '🔐 Supabase auth event: '
                    '${authState.event.name}',
              );

              if (session != null) {
                _schedulePendingDoseSync(
                  reason: authState.event.name,
                );
              }
            },
            onError: (Object error, StackTrace stack) {
              debugPrint(
                '⚠️ Authentication state listener failed: '
                    '$error',
              );
              debugPrint('$stack');
            },
          );

      debugPrint(
        '✅ Pending dose synchronization listener started',
      );
    } catch (error, stack) {
      /*
       * Supabase may not yet be initialized. Allow a later call to retry
       * installing the listener.
       */
      _authSyncListenerStarted = false;

      debugPrint(
        '⚠️ Could not start authentication listener: '
            '$error',
      );
      debugPrint('$stack');
    }
  }

  void _schedulePendingDoseSync({
    required String reason,
  }) {
    debugPrint(
      '🔄 Scheduling pending dose synchronization: '
          '$reason',
    );

    unawaited(
      _synchronizePendingDoseLogs(),
    );
  }

  Future<void> _synchronizePendingDoseLogs() async {
    try {
      await DoseLogService.instance
          .syncPendingDoseLogs();
    } catch (error, stack) {
      /*
       * Pending logs remain stored locally and can be retried after the
       * next authentication or app-start event.
       */
      debugPrint(
        '⚠️ Pending dose synchronization failed: '
            '$error',
      );
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
        'phone_number':
        _cleanOptionalString(phoneNumber),
        'timezone': timezone.trim().isEmpty
            ? 'UTC'
            : timezone.trim(),
      },
    );

    if (response.user == null) {
      throw const AuthException(
        'Signup failed. Please try again.',
      );
    }

    /*
     * Some Supabase projects require email verification and therefore do
     * not create a session immediately. Only synchronize when a session
     * exists.
     */
    if (response.session != null) {
      _schedulePendingDoseSync(
        reason: 'email signup',
      );
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

    final response =
    await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    if (response.user == null) {
      throw const AuthException(
        'Login failed. Check your credentials.',
      );
    }

    _schedulePendingDoseSync(
      reason: 'email login',
    );

    return response;
  }

  // ══════════════════════════════════════════════════════════════
  // GOOGLE SIGN IN
  // ══════════════════════════════════════════════════════════════

  Future<bool> signInWithGoogle() async {
    /*
     * OAuth completes after the application returns through its deep link.
     * Install the auth listener before opening the browser so the resulting
     * signed-in event triggers pending-dose synchronization.
     */
    _ensurePendingDoseSyncListener();

    return supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo:
      'io.supabase.medreminder://login-callback/',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SIGN OUT
  // ══════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    await supabase.auth.signOut();

    debugPrint(
      '✅ User signed out',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PASSWORD RESET
  // ══════════════════════════════════════════════════════════════

  Future<void> resetPassword(
      String email,
      ) async {
    final safeEmail = email.trim();

    if (safeEmail.isEmpty) {
      throw const AuthException(
        'An email address is required.',
      );
    }

    await supabase.auth.resetPasswordForEmail(
      safeEmail,
    );
  }

  // ── ADD THIS BELOW ──────────────────────────────────────────

  Future<void> sendPasswordResetEmail({
    required String email,
  }) async {
    final safeEmail = email.trim();

    if (safeEmail.isEmpty) {
      throw const AuthException(
        'An email address is required.',
      );
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

    if (user == null) {
      return null;
    }

    /*
     * This covers application startup with an already-restored session,
     * even if no new signed-in event is emitted.
     */
    _schedulePendingDoseSync(
      reason: 'profile/session restoration',
    );

    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) {
      return null;
    }

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
      throw const AuthException(
        'Not logged in',
      );
    }

    final safeRole = role.trim();

    if (safeRole.isEmpty) {
      throw const AuthException(
        'A user role is required.',
      );
    }

    final updated = await supabase
        .from('profiles')
        .update(
      <String, dynamic>{
        'role': safeRole,
        'phone_number':
        _cleanOptionalString(phoneNumber),
        'timezone':
        _cleanOptionalString(timezone) ?? 'UTC',
        'onboarding_completed': true,
        'updated_at':
        DateTime.now().toIso8601String(),
      },
    )
        .eq('id', user.id)
        .select()
        .single();

    _schedulePendingDoseSync(
      reason: 'onboarding completed',
    );

    return Profile.fromJson(updated);
  }

  // ══════════════════════════════════════════════════════════════
  // CLEANUP
  // ══════════════════════════════════════════════════════════════

  /// Normally the singleton remains active for the life of the app.
  /// This method is provided for tests or explicit application cleanup.
  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    _authSyncListenerStarted = false;
  }

  String? _cleanOptionalString(
      String? value,
      ) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }
}