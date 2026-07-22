// lib/home/caretaker/caretaker_dashboard_tab.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../gui/caretakers/pending_invites_screen.dart';
import '../../models/patient_activity.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../services/patient_activity_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';
import 'widgets/activity_detail_bottom_sheet.dart';
import 'widgets/activity_filter_bottom_sheet.dart';
import 'widgets/patient_activity_card.dart';

class CaretakerDashboardTab extends StatefulWidget {
  const CaretakerDashboardTab({super.key});

  @override
  State<CaretakerDashboardTab> createState() => _CaretakerDashboardTabState();
}

class _CaretakerDashboardTabState extends State<CaretakerDashboardTab> {
  Profile? _profile;
  bool _isLoading = true;

  List<PatientActivity> _activities = [];
  Map<String, int> _stats = {};
  List<Map<String, dynamic>> _patients = [];

  String? _selectedPatientId;
  String? _selectedStatus;

  RealtimeChannel? _activitySubscription;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _activitySubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.instance.getCurrentProfile();
    if (mounted) {
      setState(() {
        _profile = profile as Profile?;
        _isLoading = false;
      });

      if (_profile != null) {
        _subscribeToActivities();
        _loadInitialData();
      }
    }
  }

  void _subscribeToActivities() {
    if (_profile == null) return;

    _activitySubscription = PatientActivityService.instance
        .subscribeToPatientActivities(
      caregiverId: _profile!.id,
      onData: (activities) {
        if (mounted) {
          setState(() {
            _activities = activities;
          });
        }
      },
      onError: (error) {
        debugPrint('❌ Activity subscription error: $error');
      },
    );
  }

  Future<void> _loadInitialData() async {
    if (_profile == null) return;

    try {
      final results = await Future.wait([
        PatientActivityService.instance.getRecentActivities(
          caregiverId: _profile!.id,
          patientId: _selectedPatientId,
          status: _selectedStatus,
          limit: 20,
        ),
        PatientActivityService.instance.getActivityStats(
          caregiverId: _profile!.id,
          patientId: _selectedPatientId,
        ),
        PatientActivityService.instance.getPatientsWithActivity(
          caregiverId: _profile!.id,
        ),
      ]);

      if (mounted) {
        setState(() {
          _activities = results[0] as List<PatientActivity>;
          _stats = results[1] as Map<String, int>;
          _patients = results[2] as List<Map<String, dynamic>>;
        });
      }
    } catch (error, stack) {
      debugPrint('❌ Failed to load dashboard data: $error');
      debugPrint('$stack');
    }
  }

  Future<void> _refreshData() async {
    await _loadInitialData();
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ActivityFilterBottomSheet(
        patients: _patients,
        selectedPatientId: _selectedPatientId,
        selectedStatus: _selectedStatus,
        onApply: (patientId, status) {
          setState(() {
            _selectedPatientId = patientId;
            _selectedStatus = status;
          });
          _loadInitialData();
        },
      ),
    );
  }

  void _showActivityDetail(PatientActivity activity) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ActivityDetailBottomSheet(
        activity: activity,
      ),
    );
  }

  void _openPendingInvites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PendingInvitesScreen()),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  bool get _hasActiveFilters =>
      _selectedPatientId != null || (_selectedStatus != null && _selectedStatus != 'all');

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _CaretakerDashboardSkeleton();
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // Stats Grid
          if (_stats.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.check_circle_rounded,
                    iconColor: Colors.green,
                    label: 'Taken',
                    value: '${_stats['taken'] ?? 0}',
                    suffix: 'doses',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.cancel_rounded,
                    iconColor: AppColors.error,
                    label: 'Missed',
                    value: '${_stats['missed'] ?? 0}',
                    suffix: 'doses',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.pending_rounded,
                    iconColor: AppColors.warning,
                    label: 'Pending',
                    value: '${_stats['pending'] ?? 0}',
                    suffix: 'doses',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.remove_circle_rounded,
                    iconColor: AppColors.textSecondary,
                    label: 'Skipped',
                    value: '${_stats['skipped'] ?? 0}',
                    suffix: 'doses',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],

          // Recent Activity Section
          Row(
            children: [
              Expanded(
                child: Text('Recent Activity', style: AppTextStyles.h2),
              ),
              if (_hasActiveFilters)
                Chip(
                  label: const Text('Filtered'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _selectedPatientId = null;
                      _selectedStatus = null;
                    });
                    _loadInitialData();
                  },
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  labelStyle: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: _hasActiveFilters ? AppColors.primary : AppColors.textSecondary,
                ),
                onPressed: _openFilterSheet,
                tooltip: 'Filter activities',
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_activities.isEmpty)
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
                    _hasActiveFilters
                        ? 'No activities match your filters'
                        : 'No recent activity',
                    style: AppTextStyles.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hasActiveFilters
                        ? 'Try adjusting your filter criteria'
                        : 'Once you link with patients, their activity will appear here',
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._activities.map((activity) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PatientActivityCard(
                activity: activity,
                onTap: () => _showActivityDetail(activity),
              ),
            )),

          const SizedBox(height: 24),

          // Quick Actions
          Text('Quick Actions', style: AppTextStyles.h2),
          const SizedBox(height: 12),

          _QuickActionTile(
            icon: Icons.person_add_rounded,
            iconColor: AppColors.primary,
            title: 'Link with a patient',
            subtitle: 'View and respond to pending invites',
            onTap: _openPendingInvites,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STAT CARD
// ══════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════
// QUICK ACTION TILE
// ══════════════════════════════════════════════════════════════

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

// ══════════════════════════════════════════════════════════════
// SKELETON
// ══════════════════════════════════════════════════════════════

class _CaretakerDashboardSkeleton extends StatelessWidget {
  const _CaretakerDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(height: 60, borderRadius: 12),
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
        SizedBox(height: 12),
        SkeletonBox(height: 140, borderRadius: 16),
      ],
    );
  }
}