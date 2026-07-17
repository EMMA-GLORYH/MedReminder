// lib/home/caretaker/caretaker_dashboard_tab.dart

import 'package:flutter/material.dart';
import '../../gui/caretakers/pending_invites_screen.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';

class CaretakerDashboardTab extends StatefulWidget {
  const CaretakerDashboardTab({super.key});

  @override
  State<CaretakerDashboardTab> createState() => _CaretakerDashboardTabState();
}

class _CaretakerDashboardTabState extends State<CaretakerDashboardTab> {
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
        _profile = profile as Profile?;
        _isLoading = false;
      });
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openPendingInvites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PendingInvitesScreen()),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _CaretakerDashboardSkeleton();
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          const SizedBox(height: 24),

          // ── Stats Row ──
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.people_rounded,
                  iconColor: AppColors.secondary,
                  label: 'Patients',
                  value: '0',
                  suffix: 'active',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.warning_amber_rounded,
                  iconColor: AppColors.warning,
                  label: 'Alerts',
                  value: '0',
                  suffix: 'today',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle_rounded,
                  iconColor: AppColors.primary,
                  label: 'On Track',
                  value: '—',
                  suffix: 'patients',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.error_outline_rounded,
                  iconColor: AppColors.error,
                  label: 'Needs Help',
                  value: '0',
                  suffix: 'patients',
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ── Recent Activity Section ──
          Text('Recent Activity', style: AppTextStyles.h2),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.timeline_rounded,
                    size: 32,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No recent activity',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Once you link with patients, their activity will appear here',
                  style: AppTextStyles.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Quick Actions ──
          Text('Quick Actions', style: AppTextStyles.h2),
          const SizedBox(height: 12),

          _QuickActionTile(
            icon: Icons.person_add_rounded,
            iconColor: AppColors.primary,
            title: 'Link with a patient',
            subtitle: 'View and respond to pending invites',
            onTap: _openPendingInvites,
          ),

          const SizedBox(height: 8),

          _QuickActionTile(
            icon: Icons.notifications_active_rounded,
            iconColor: AppColors.warning,
            title: 'Alert Settings',
            subtitle: 'Configure how you receive notifications',
            onTap: () {},
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Stat Card ──
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String suffix;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(label, style: AppTextStyles.labelSmall),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTextStyles.h1),
              const SizedBox(width: 4),
              Text(suffix, style: AppTextStyles.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Quick Action Tile ──
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton ──
class _CaretakerDashboardSkeleton extends StatelessWidget {
  const _CaretakerDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(height: 100, borderRadius: 20),
        SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 100, borderRadius: 16)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 100, borderRadius: 16)),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 100, borderRadius: 16)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 100, borderRadius: 16)),
          ],
        ),
        SizedBox(height: 32),
        SkeletonBox(height: 20, width: 150),
        SizedBox(height: 12),
        SkeletonBox(height: 140, borderRadius: 16),
      ],
    );
  }
}