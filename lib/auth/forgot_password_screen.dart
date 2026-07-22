// lib/screens/auth/forgot_password_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isSending = false;
  bool _emailSent = false;

  // Resend cooldown
  int _resendCooldown = 0;
  Timer? _resendTimer;

  // Entrance animation
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _resendTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  // SEND RESET EMAIL
  // ══════════════════════════════════════════════════════════

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSending || _resendCooldown > 0) return;

    setState(() => _isSending = true);

    try {
      await AuthService.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _isSending = false;
        _emailSent = true;
      });

      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSending = false);

      _showError(_friendlyError(e.toString()));
    }
  }

  Future<void> _resendEmail() async {
    if (_resendCooldown > 0 || _isSending) return;

    setState(() => _isSending = true);

    try {
      await AuthService.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      setState(() => _isSending = false);

      _startResendCooldown();

      _showSuccess('Reset link resent to ${_emailController.text.trim()}');
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSending = false);

      _showError(_friendlyError(e.toString()));
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();

    setState(() => _resendCooldown = 60);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _resendCooldown--);

      if (_resendCooldown <= 0) {
        timer.cancel();
      }
    });
  }

  String _friendlyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('user not found') || lower.contains('invalid')) {
      return 'No account found with that email address.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'No internet connection. Please check your network.';
    }
    if (lower.contains('rate') || lower.contains('too many')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    return 'Could not send the reset link. Please try again.';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _emailSent
                    ? _SuccessView(
                  key: const ValueKey('success'),
                  email: _emailController.text.trim(),
                  isSending: _isSending,
                  resendCooldown: _resendCooldown,
                  onResend: _resendEmail,
                  onBackToLogin: () => Navigator.pop(context),
                )
                    : _RequestView(
                  key: const ValueKey('request'),
                  formKey: _formKey,
                  emailController: _emailController,
                  isSending: _isSending,
                  onSend: _sendResetEmail,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// REQUEST VIEW — email input + send button
// ══════════════════════════════════════════════════════════════
class _RequestView extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final bool isSending;
  final VoidCallback onSend;

  const _RequestView({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        // ── Logo ─────────────────────────────────────────────
        Center(
          child: SvgPicture.asset(
            'assets/images/MedReminder_Logo.svg',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => const Icon(
              Icons.medication_rounded,
              size: 80,
              color: AppColors.secondary,
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── Icon ─────────────────────────────────────────────
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              size: 36,
              color: AppColors.primary,
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── Title ────────────────────────────────────────────
        Text(
          'Forgot Password?',
          style: AppTextStyles.h1.copyWith(
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 10),

        Text(
          'No worries! Enter your email address below '
              'and we\'ll send you a link to reset your password.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 36),

        // ── Email Form ───────────────────────────────────────
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Label
              Text(
                'Email Address',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Input
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    hintText: 'your@email.com',
                    hintStyle: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    errorStyle: TextStyle(
                      color: AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
              ),

              const SizedBox(height: 28),

              // Send button
              _SendButton(
                isSending: isSending,
                onPressed: onSend,
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // ── Info card ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.15),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'The reset link expires in 24 hours. '
                      'Check your spam folder if you don\'t see it in your inbox.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SUCCESS VIEW — shown after email is sent
// ══════════════════════════════════════════════════════════════
class _SuccessView extends StatelessWidget {
  final String email;
  final bool isSending;
  final int resendCooldown;
  final VoidCallback onResend;
  final VoidCallback onBackToLogin;

  const _SuccessView({
    super.key,
    required this.email,
    required this.isSending,
    required this.resendCooldown,
    required this.onResend,
    required this.onBackToLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),

        // ── Logo ─────────────────────────────────────────────
        Center(
          child: SvgPicture.asset(
            'assets/images/MedReminder_Logo.svg',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => const Icon(
              Icons.medication_rounded,
              size: 80,
              color: AppColors.secondary,
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── Success animation circle ──────────────────────────
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_read_rounded,
              size: 44,
              color: AppColors.primary,
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── Title ────────────────────────────────────────────
        Text(
          'Check your inbox!',
          style: AppTextStyles.h1.copyWith(
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        // ── Email sent to ────────────────────────────────────
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            children: [
              const TextSpan(text: 'We sent a password reset link to\n'),
              TextSpan(
                text: email,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // ── Steps ────────────────────────────────────────────
        _StepCard(
          step: '1',
          title: 'Open your email app',
          description: 'Check your inbox or spam folder.',
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 12),
        _StepCard(
          step: '2',
          title: 'Click the reset link',
          description: 'Tap the link in the email we sent you.',
          icon: Icons.touch_app_rounded,
        ),
        const SizedBox(height: 12),
        _StepCard(
          step: '3',
          title: 'Create a new password',
          description: 'Choose a strong password for your account.',
          icon: Icons.lock_rounded,
        ),

        const SizedBox(height: 36),

        // ── Back to login button ──────────────────────────────
        GestureDetector(
          onTap: onBackToLogin,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'Back to Login',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Resend section ────────────────────────────────────
        Center(
          child: Column(
            children: [
              Text(
                'Didn\'t receive the email?',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: (resendCooldown > 0 || isSending) ? null : onResend,
                child: AnimatedOpacity(
                  opacity: (resendCooldown > 0 || isSending) ? 0.5 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: resendCooldown > 0
                            ? AppColors.border
                            : AppColors.primary.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSending)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        else
                          Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: resendCooldown > 0
                                ? AppColors.textSecondary
                                : AppColors.primary,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          isSending
                              ? 'Sending...'
                              : resendCooldown > 0
                              ? 'Resend in ${resendCooldown}s'
                              : 'Resend email',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: resendCooldown > 0
                                ? AppColors.textSecondary
                                : AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STEP CARD
// ══════════════════════════════════════════════════════════════
class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final String description;
  final IconData icon;

  const _StepCard({
    required this.step,
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Step number circle
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              step,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Step content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Icon
          Icon(
            icon,
            size: 20,
            color: AppColors.secondary,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SEND BUTTON
// ══════════════════════════════════════════════════════════════
class _SendButton extends StatelessWidget {
  final bool isSending;
  final VoidCallback onPressed;

  const _SendButton({
    required this.isSending,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSending ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: isSending
              ? const LinearGradient(
            colors: [Color(0xFF888888), Color(0xFF666666)],
          )
              : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
          ),
          boxShadow: isSending
              ? []
              : [
            BoxShadow(
              color: const Color(0xFF4CAF50).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isSending
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.send_rounded,
              color: Colors.white,
              size: 18,
            ),
            SizedBox(width: 10),
            Text(
              'Send Reset Link',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}