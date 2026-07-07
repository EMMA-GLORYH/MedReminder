// lib/screens/home/patient/profile_tab.dart

import 'package:flutter/material.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
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
          child: Container(
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
        ),

        const SizedBox(height: 16),

        Text(
          _profile?.fullName ?? 'User',
          style: AppTextStyles.h1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          _profile?.role == 'patient' ? 'Patient' : 'Caretaker',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
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

        Text('Caretakers', style: AppTextStyles.h2),
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
              Icon(
                Icons.person_add_outlined,
                size: 40,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'No caretakers yet',
                style: AppTextStyles.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Invite someone to watch over your care',
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
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