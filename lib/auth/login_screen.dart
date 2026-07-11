// lib/screens/auth/login_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_router.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/buttons/app_button.dart';
import '../widgets/inputs/app_text_field.dart';
import '../widgets/snackbar/app_snackbar.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailLogin() async {
    // ── Step 1: Validate form ──
    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ Form validation failed');
      return;
    }

    debugPrint('🚀 Login started for: ${_emailController.text.trim()}');
    setState(() => _isLoading = true);

    try {
      // ── Step 2: Authenticate with Supabase ──
      debugPrint('🔐 Calling Supabase signInWithEmail...');
      final response = await AuthService.instance.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      debugPrint('✅ Supabase login successful');
      debugPrint('   User ID: ${response.user?.id}');

      if (!mounted) {
        debugPrint('❌ Widget unmounted after login');
        return;
      }

      // ── Step 3: Show success feedback so user knows something happened ──
      AppSnackbar.success(context, 'Signed in! Loading your dashboard...');

      // ── Step 4: Route based on role ──
      debugPrint('🚀 Calling AuthRouter.routeAfterAuth...');
      await AuthRouter.routeAfterAuth(context);
    } on AuthException catch (e) {
      // Supabase-specific error (wrong password, etc.)
      debugPrint('❌ AuthException: ${e.message}');
      if (mounted) {
        AppSnackbar.error(context, _friendlyError(e.message));
        setState(() => _isLoading = false);
      }
    } catch (e, stack) {
      // Unexpected error
      debugPrint('❌ Unexpected error: $e');
      debugPrint('❌ Stack: $stack');
      if (mounted) {
        AppSnackbar.error(
          context,
          'Login succeeded but something went wrong loading your account. '
              'Please try again.',
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);

    try {
      await AuthService.instance.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Google sign-in failed. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  String _friendlyError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid') || lower.contains('credentials')) {
      return 'Wrong email or password. Please try again.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'No internet connection. Check your network.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medication_rounded,
                      size: 48,
                      color: AppColors.secondary,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                Text(
                  'Welcome',
                  style: AppTextStyles.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue your care journey',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                AppTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'name@example.com',
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
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Enter your password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: 'Forgot Password?',
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.small,
                    fullWidth: false,
                    onPressed: () {},
                  ),
                ),

                const SizedBox(height: 16),

                AppButton(
                  label: 'Sign In',
                  isLoading: _isLoading,
                  onPressed: _handleEmailLogin,
                ),

                const SizedBox(height: 24),

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

                const SizedBox(height: 24),

                AppButton(
                  label: 'Continue with Google',
                  icon: Icons.g_mobiledata,
                  variant: AppButtonVariant.outline,
                  onPressed: _isLoading ? null : _handleGoogleLogin,
                ),

                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: AppTextStyles.bodyMedium,
                    ),
                    AppButton(
                      label: 'Sign Up',
                      variant: AppButtonVariant.text,
                      size: AppButtonSize.small,
                      fullWidth: false,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignupScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}