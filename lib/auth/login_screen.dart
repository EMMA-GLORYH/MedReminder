// lib/screens/auth/login_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_router.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
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
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await AuthService.instance.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      AppSnackbar.success(context, 'Signed in! Loading your dashboard...');
      await AuthRouter.routeAfterAuth(context);
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ══════════════════════════════════════════════════════
          // LAYER 1: FULL CLEAR BACKGROUND IMAGE
          // ══════════════════════════════════════════════════════
          Positioned.fill(
            child: Image.asset(
              'assets/images/BG_Image.jpeg',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A2232), Color(0xFF0D1117)],
                  ),
                ),
              ),
            ),
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 2: VERY LIGHT SCRIM
          // ══════════════════════════════════════════════════════
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.10),
            ),
          ),

          // ══════════════════════════════════════════════════════
          // LAYER 3: GLASS CARD + FORM
          // ══════════════════════════════════════════════════════
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  screenWidth > 400 ? screenWidth * 0.08 : 20,
                  24,
                ),
                child: _GlassCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),

                        // ── Logo ──────────────────────────────
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.medication_rounded,
                              size: 40,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Headline — "Back" removed ─────────
                        Text(
                          'Welcome',
                          style: AppTextStyles.h1.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Stay on track. Take care. Live well.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white.withOpacity(0.85),
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 24),

                        // ── Email field ───────────────────────
                        // ✅ FIX: White background + dark text so
                        // the typed content and icon are visible
                        _SolidTextField(
                          controller: _emailController,
                          hint: 'User Name',
                          prefixIcon: Icons.person_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!v.contains('@')) return 'Invalid email';
                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // ── Password field ────────────────────
                        _SolidTextField(
                          controller: _passwordController,
                          hint: 'Password',
                          prefixIcon: Icons.lock_outline_rounded,
                          isPassword: true,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // ── Remember me + Forgot password ─────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    tristate: false,
                                    value: _rememberMe,
                                    onChanged: (bool? newValue) {
                                      setState(() {
                                        _rememberMe = newValue ?? false;
                                      });
                                    },
                                    activeColor: AppColors.primary,
                                    checkColor: Colors.white,
                                    fillColor:
                                    WidgetStateProperty.resolveWith(
                                          (states) {
                                        if (states.contains(
                                          WidgetState.selected,
                                        )) {
                                          return AppColors.primary;
                                        }
                                        return Colors.white
                                            .withOpacity(0.85);
                                      },
                                    ),
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.7),
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    setState(
                                          () => _rememberMe = !_rememberMe,
                                    );
                                  },
                                  child: Text(
                                    'Remember me',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () {
                                // TODO: implement forgot password
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ── Login button ──────────────────────
                        _LoginButton(
                          isLoading: _isLoading,
                          onPressed: _handleEmailLogin,
                        ),

                        const SizedBox(height: 16),

                        // ── Sign up link ──────────────────────
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SignupScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Signup',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── OR Divider ────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.white.withOpacity(0.35),
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'OR',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: Colors.white.withOpacity(0.70),
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.white.withOpacity(0.35),
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Google + Apple icon buttons ───────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // ── Google ────────────────────────
                            _SocialButton(
                              onPressed: _isLoading ? null : _handleGoogleLogin,
                              child: Image.network(
                                'https://img.icons8.com/fluency/48/google-logo.png',
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => const Text(
                                  'G',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4285F4),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 20),


                            // ── Apple ─────────────────────────
                            _SocialButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                AppSnackbar.error(
                                  context,
                                  'Apple sign-in coming soon',
                                );
                              },
                              child: Image.network(
                                'https://img.icons8.com/ios-filled/50/000000/apple-logo.png',
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.black,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.apple_rounded,
                                  size: 28,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// GLASS CARD
// ══════════════════════════════════════════════════════════════
class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Colors.white.withOpacity(0.13),
          border: Border.all(
            color: Colors.white.withOpacity(0.22),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.30),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.20),
                Colors.white.withOpacity(0.06),
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: child,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SOLID TEXT FIELD
// White background + dark text so typed text and icons are
// always clearly visible regardless of the background image.
// ══════════════════════════════════════════════════════════════
class _SolidTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool isPassword;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _SolidTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.isPassword = false,
    this.keyboardType,
    this.validator,
  });

  @override
  State<_SolidTextField> createState() => _SolidTextFieldState();
}

class _SolidTextFieldState extends State<_SolidTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // ✅ Solid white background — always readable
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: widget.controller,
        obscureText: widget.isPassword && _obscured,
        keyboardType: widget.keyboardType,
        // ✅ Dark text — clearly visible on white background
        style: const TextStyle(
          color: Color(0xFF1A1A1A),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: AppColors.primary,
        validator: widget.validator,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            // ✅ Medium-dark hint text for clear placeholder
            color: Colors.grey.shade500,
            fontSize: 15,
          ),
          prefixIcon: Icon(
            widget.prefixIcon,
            // ✅ Dark icon clearly visible on white background
            color: Colors.grey.shade600,
            size: 20,
          ),
          suffixIcon: widget.isPassword
              ? IconButton(
            icon: Icon(
              _obscured
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: Colors.grey.shade500,
              size: 20,
            ),
            onPressed: () => setState(() => _obscured = !_obscured),
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppColors.primary,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFE53935),
              width: 1.5,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFE53935),
              width: 2,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          errorStyle: const TextStyle(
            color: Color(0xFFE53935),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LOGIN GRADIENT BUTTON
// ══════════════════════════════════════════════════════════════
class _LoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _LoginButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: isLoading
              ? const LinearGradient(
            colors: [Color(0xFF888888), Color(0xFF666666)],
          )
              : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFF4CAF50),
              Color(0xFF2196F3),
            ],
          ),
          boxShadow: isLoading
              ? []
              : [
            BoxShadow(
              color: const Color(0xFF4CAF50).withOpacity(0.40),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : const Text(
          'Login',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SOCIAL ICON BUTTON (Google / Apple)
// ══════════════════════════════════════════════════════════════
class _SocialButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const _SocialButton({required this.child, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // ✅ White background so Google logo colours pop clearly
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}