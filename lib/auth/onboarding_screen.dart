// lib/screens/auth/onboarding_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/buttons/app_button.dart';
import '../widgets/inputs/app_text_field.dart';
import '../widgets/loaders/app_loader.dart';
import '../widgets/snackbar/app_snackbar.dart';
import '../gui/splash_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  String _selectedRole = 'patient';
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    AppLoader.show(context, message: 'Setting up your profile...');

    try {
      await AuthService.instance.completeOnboarding(
        role: _selectedRole,
        phoneNumber: _phoneController.text.trim(),
      );

      if (!mounted) return;
      AppLoader.hide(context);

      // In _complete() after successful onboarding

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const SplashScreen(showBranding: false),  // ← Add this
        ),
            (route) => false,
      );
    } catch (e) {
      if (mounted) {
        AppLoader.hide(context);
        AppSnackbar.error(context, 'Failed to save. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
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
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.waving_hand_rounded,
                      size: 48,
                      color: AppColors.secondary,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'Almost there!',
                  style: AppTextStyles.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us a bit more about how you\'ll use MedReminder',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                Text('I am a...', style: AppTextStyles.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RoleTile(
                        label: 'Patient',
                        icon: Icons.personal_injury_outlined,
                        selected: _selectedRole == 'patient',
                        onTap: () => setState(() => _selectedRole = 'patient'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleTile(
                        label: 'Caretaker',
                        icon: Icons.favorite_outline,
                        selected: _selectedRole == 'caretaker',
                        onTap: () => setState(() => _selectedRole = 'caretaker'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

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

                const Spacer(),

                AppButton(
                  label: 'Continue',
                  isLoading: _isLoading,
                  onPressed: _complete,
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
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
              ? AppColors.primary.withOpacity(0.15)
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