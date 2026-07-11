// lib/screens/auth/signup_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/buttons/app_button.dart';
import '../widgets/inputs/app_text_field.dart';
import '../widgets/snackbar/app_snackbar.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey          = GlobalKey<FormState>();
  final _nameController   = TextEditingController();
  final _emailController  = TextEditingController();
  final _phoneController  = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // Sign up — NO role passed here.
      // The DB trigger creates the profile with null role.
      // Role is collected on the OnboardingScreen after email verification.
      await AuthService.instance.signUpWithEmail(
        email:       _emailController.text.trim(),
        password:    _passwordController.text,
        fullName:    _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        role:        null,
      );

      if (!mounted) return;

      // Show email-verification notice instead of routing immediately
      _showVerificationDialog();
    } on AuthException catch (e) {
      if (mounted) {
        AppSnackbar.error(context, _friendlyError(e.message));
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Something went wrong. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignup() async {
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signInWithGoogle();
      // Google OAuth → redirect → SplashScreen → AuthRouter → OnboardingScreen
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Google sign-up failed. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  void _showVerificationDialog() {
    showDialog(
      context:             context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surface,
        icon: const Icon(Icons.mark_email_read_rounded,
            size: 52, color: AppColors.primary),
        title: const Text('Verify your email',
            textAlign: TextAlign.center),
        content: Text(
          'We sent a confirmation link to\n'
              '${_emailController.text.trim()}\n\n'
              'Click the link in your email, then come back and sign in.',
          textAlign:  TextAlign.center,
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(160, 48),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // back to LoginScreen
            },
            child: const Text('Go to Sign In'),
          ),
        ],
      ),
    );
  }

  String _friendlyError(String message) {
    final l = message.toLowerCase();
    if (l.contains('already registered') || l.contains('user already')) {
      return 'This email is already registered. Try signing in instead.';
    }
    if (l.contains('password')) return 'Password must be at least 6 characters.';
    if (l.contains('invalid') && l.contains('email')) {
      return 'Please enter a valid email address.';
    }
    if (l.contains('network')) return 'No internet connection.';
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation:       0,
        title: Text('Create Account', style: AppTextStyles.titleMedium),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Icon ──
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.medication_rounded,
                        size: 44, color: AppColors.primary),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Join MedReminder',
                  style:     AppTextStyles.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Create your account to get started',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // ── Fields ──
                AppTextField(
                  controller: _nameController,
                  label:      'Full Name',
                  hint:       'John Doe',
                  prefixIcon: Icons.person_outline,
                  validator:  (v) => v == null || v.trim().isEmpty
                      ? 'Name is required' : null,
                ),

                const SizedBox(height: 14),

                AppTextField(
                  controller:   _emailController,
                  label:        'Email',
                  hint:         'name@example.com',
                  prefixIcon:   Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                AppTextField(
                  controller:   _phoneController,
                  label:        'Phone Number',
                  hint:         '+233 XX XXX XXXX',
                  prefixIcon:   Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator:    (v) => v == null || v.trim().isEmpty
                      ? 'Phone is required for alerts' : null,
                ),

                const SizedBox(height: 14),

                AppTextField(
                  controller: _passwordController,
                  label:      'Password',
                  hint:       'Minimum 6 characters',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 6) return 'Minimum 6 characters';
                    return null;
                  },
                ),

                const SizedBox(height: 6),

                // Role hint — let user know role is chosen next
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color:        AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You\'ll choose your role (Patient / Caretaker) '
                              'after verifying your email.',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                AppButton(
                  label:     'Create Account',
                  isLoading: _isLoading,
                  onPressed: _handleSignup,
                ),

                const SizedBox(height: 20),

                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('OR', style: AppTextStyles.labelSmall),
                  ),
                  const Expanded(child: Divider()),
                ]),

                const SizedBox(height: 20),

                AppButton(
                  label:     'Sign up with Google',
                  icon:      Icons.g_mobiledata,
                  variant:   AppButtonVariant.outline,
                  onPressed: _isLoading ? null : _handleGoogleSignup,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}