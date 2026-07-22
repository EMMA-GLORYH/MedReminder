// lib/screens/auth/onboarding_screen.dart

import 'package:flutter/material.dart';

import 'package:mar/services/auth_service.dart';
import 'package:mar/services/auth_router.dart';
import 'package:mar/theme/app_colors.dart';
import 'package:mar/theme/app_text_styles.dart';
import 'package:mar/widgets/buttons/app_button.dart';
import 'package:mar/widgets/inputs/app_text_field.dart';
import 'package:mar/widgets/snackbar/app_snackbar.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() =>
      _OnboardingScreenState();
}

class _OnboardingScreenState
    extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  String _selectedRole = 'patient';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _prefillPhone();
  }

  Future<void> _prefillPhone() async {
    try {
      final profile =
      await AuthService.instance.getCurrentProfile();

      if (profile?.phoneNumber != null &&
          profile!.phoneNumber!.isNotEmpty &&
          mounted) {
        _phoneController.text = profile.phoneNumber!;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final databaseRole = _selectedRole == 'caretaker'
        ? 'caregiver'
        : _selectedRole;

    try {
      await AuthService.instance.completeOnboarding(
        role: databaseRole,
        phoneNumber: _phoneController.text.trim(),
      );

      if (!mounted) return;
      await AuthRouter.routeAfterAuth(context);
    } catch (e) {
      debugPrint('❌ Onboarding failed to complete: $e');

      if (mounted) {
        final errorDetail = e
            .toString()
            .replaceFirst('Exception: ', '');

        final shortError = errorDetail.length > 120
            ? '${errorDetail.substring(0, 120)}...'
            : errorDetail;

        AppSnackbar.error(
          context,
          'Failed to save: $shortError',
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding:
          const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                Center(
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withValues(alpha: 0.12),
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
                  'One last step!',
                  style: AppTextStyles.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell us how you\'ll use MedReminder '
                      'so we can set up your experience.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                Text(
                  'I am a…',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _RoleTile(
                        label: 'Patient',
                        icon: Icons
                            .personal_injury_outlined,
                        description:
                        'I want to track\nmy own medications',
                        selected:
                        _selectedRole == 'patient',
                        onTap: () => setState(
                              () => _selectedRole = 'patient',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleTile(
                        label: 'Caretaker',
                        icon: Icons.favorite_outline,
                        description:
                        'I help someone else\nmanage their meds',
                        selected:
                        _selectedRole == 'caretaker',
                        onTap: () => setState(
                              () => _selectedRole = 'caretaker',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                AppTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: '+233 XX XXX XXXX',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                  v == null || v.trim().isEmpty
                      ? 'Phone is required for alerts'
                      : null,
                ),

                const Spacer(),

                AnimatedSwitcher(
                  duration:
                  const Duration(milliseconds: 200),
                  child: _RoleBadge(
                    key: ValueKey(_selectedRole),
                    role: _selectedRole,
                  ),
                ),

                const SizedBox(height: 16),

                AppButton(
                  label: 'Get Started',
                  isLoading: _isLoading,
                  onPressed: _complete,
                ),
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
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.label,
    required this.icon,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: 20,
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 36,
              color: selected
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: AppTextStyles.titleSmall.copyWith(
                color: selected
                    ? AppColors.primary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: AppTextStyles.bodySmall.copyWith(
                color: selected
                    ? AppColors.primary
                    .withValues(alpha: 0.75)
                    : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({
    super.key,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final isPatient = role == 'patient';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPatient
                ? Icons.check_circle_outline_rounded
                : Icons.supervisor_account_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isPatient
                  ? 'As a Patient you can log doses, '
                  'set schedules, and get reminders.'
                  : 'As a Caretaker you can manage '
                  'medications and schedules for a patient.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}