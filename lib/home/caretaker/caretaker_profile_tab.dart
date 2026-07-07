// lib/screens/home/caretaker/caretaker_profile_tab.dart

import 'package:flutter/material.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';

class CaretakerProfileTab extends StatefulWidget {
  const CaretakerProfileTab({super.key});

  @override
  State<CaretakerProfileTab> createState() => _CaretakerProfileTabState();
}

class _CaretakerProfileTabState extends State<CaretakerProfileTab> {
  Profile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.instance.getCurrentProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SkeletonBox(width: 100, height: 100, borderRadius: 50),
            SizedBox(height: 24),
            SkeletonBox(height: 20, width: 200),
            SizedBox(height: 8),
            SkeletonBox(height: 16, width: 150),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),

        // ── Avatar ──
        Center(
          child: Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                  image: _profile?.avatarUrl != null
                      ? DecorationImage(
                    image: NetworkImage(_profile!.avatarUrl!),
                    fit: BoxFit.cover,
                  )
                      : null,
                ),
                child: _profile?.avatarUrl == null
                    ? const Icon(
                  Icons.person_rounded,
                  size: 48,
                  color: AppColors.secondary,
                )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 16,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Text(
          _profile?.fullName ?? 'Caretaker',
          style: AppTextStyles.h1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Caretaker',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.secondary,
            ),
          ),
        ),

        const SizedBox(height: 32),

        _ProfileTile(
          icon: Icons.email_outlined,
          label: 'Email',
          value: AuthService.instance.currentUser?.email ?? '—',
        ),
        _ProfileTile(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: _profile?.phoneNumber ?? 'Not set',
        ),
        _ProfileTile(
          icon: Icons.public_rounded,
          label: 'Timezone',
          value: _profile?.timezone ?? 'UTC',
        ),

        const SizedBox(height: 24),

        Text('Alert Preferences', style: AppTextStyles.h2),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _AlertToggle(
                icon: Icons.notifications_rounded,
                label: 'Push Notifications',
                value: true,
                onChanged: (v) {},
              ),
              const Divider(height: 24),
              _AlertToggle(
                icon: Icons.sms_rounded,
                label: 'SMS Alerts',
                value: true,
                onChanged: (v) {},
              ),
              const Divider(height: 24),
              _AlertToggle(
                icon: Icons.phone_in_talk_rounded,
                label: 'Emergency Calls',
                value: false,
                onChanged: (v) {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.labelSmall),
                const SizedBox(height: 4),
                Text(value, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AlertToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: AppTextStyles.bodyMedium),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }
}