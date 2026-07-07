// lib/screens/auth/signup_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_router.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedRole = 'patient';
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
    // ── Step 1: Validate form ──
    if (!_formKey.currentState!.validate()) return;

    // ── Step 2: Show loading on the button ──
    setState(() => _isLoading = true);

    try {
      // ── Step 3: Create account in Supabase ──
      // The database trigger auto-creates a profile row
      // with the role we selected here
      await AuthService.instance.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        role: _selectedRole,
        phoneNumber: _phoneController.text.trim(),
      );

      if (!mounted) return;

      // ── Step 4: Show success feedback ──
      AppSnackbar.success(context, 'Account created successfully!');

      // ── Step 5: Route to the right home based on selected role ──
      // Patient   → PatientHomeScreen
      // Caretaker → CaretakerHomeScreen
      await AuthRouter.routeAfterAuth(context);
    } on AuthException catch (e) {
      // ── Signup error (email taken, invalid, etc.) ──
      if (mounted) {
        AppSnackbar.error(context, _friendlyError(e.message));
        setState(() => _isLoading = false);
      }
    } catch (e) {
      // ── Network or unexpected error ──
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
      // Google OAuth handles routing via redirect
      // New Google users will land on OnboardingScreen to pick their role
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Google sign-up failed. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  /// Convert Supabase errors into friendly messages
  String _friendlyError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('already registered') ||
        lower.contains('user already')) {
      return 'This email is already registered. Try signing in instead.';
    }
    if (lower.contains('password')) {
      return 'Password must be at least 6 characters.';
    }
    if (lower.contains('invalid') && lower.contains('email')) {
      return 'Please enter a valid email address.';
    }
    if (lower.contains('network')) {
      return 'No internet connection.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                Text('I am a...', style: AppTextStyles.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RoleCard(
                        label: 'Patient',
                        icon: Icons.personal_injury_outlined,
                        selected: _selectedRole == 'patient',
                        onTap: () => setState(() => _selectedRole = 'patient'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleCard(
                        label: 'Caretaker',
                        icon: Icons.favorite_outline,
                        selected: _selectedRole == 'caretaker',
                        onTap: () =>
                            setState(() => _selectedRole = 'caretaker'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                AppTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'John Doe',
                  prefixIcon: Icons.person_outline,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Name is required'
                      : null,
                ),

                const SizedBox(height: 16),

                AppTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'name1@example.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                AppTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: '+1234567890',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Phone is required for alerts'
                      : null,
                ),

                const SizedBox(height: 16),

                AppTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Minimum 6 characters',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 6) return 'Minimum 6 characters';
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // ── Button shows loading state ──
                AppButton(
                  label: 'Create Account',
                  isLoading: _isLoading,
                  onPressed: _handleSignup,
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: AppTextStyles.labelSmall),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 16),

                AppButton(
                  label: 'Sign up with Google',
                  icon: Icons.g_mobiledata,
                  variant: AppButtonVariant.outline,
                  onPressed: _isLoading ? null : _handleGoogleSignup,
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Role Selection Card ──
class _RoleCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? AppColors.secondary : AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.titleSmall.copyWith(
                color: selected ? AppColors.secondary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}