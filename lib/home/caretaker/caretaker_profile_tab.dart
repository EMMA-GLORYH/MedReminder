// lib/screens/home/caretaker/caretaker_profile_tab.dart

import 'package:flutter/material.dart';
import '../../models/care_relationship.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../services/care_relationship_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';
import '../../widgets/snackbar/app_snackbar.dart';

class CaretakerProfileTab extends StatefulWidget {
  const CaretakerProfileTab({super.key});

  @override
  State<CaretakerProfileTab> createState() => _CaretakerProfileTabState();
}

class _CaretakerProfileTabState extends State<CaretakerProfileTab> {
  Profile? _profile;
  bool _isLoading = true;
  List<CareRelationship> _connectedPatients = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final results = await Future.wait([
        AuthService.instance.getCurrentProfile(),
        CareRelationshipService.instance.getPatientsIMonitor(),
      ]);

      if (!mounted) return;

      setState(() {
        _profile = results[0] as Profile?;
        _connectedPatients = (results[1] as List<CareRelationship>?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading caretaker profile: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _disconnectPatient(CareRelationship relationship) async {
    final patientName = relationship.patientName.trim().isNotEmpty
        ? relationship.patientName
        : 'this patient';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Disconnect Patient'),
        content: Text(
          'You will immediately lose access to $patientName.\n\n''You can reconnect later if the patient sends another invitation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await CareRelationshipService.instance.disconnectPatient(relationship.id);
      await _loadProfile();

      if (!mounted) return;
      AppSnackbar.success(context, '$patientName disconnected.');
    } catch (e) {
      debugPrint('❌ Disconnect error: $e');
      if (!mounted) return;
      AppSnackbar.error(context, 'Failed to disconnect patient.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _CaretakerProfileSkeleton();
    }

    final email = AuthService.instance.currentUser?.email ?? '—';
    final avatarUrl = _profile?.avatarUrl?.trim();
    final bool hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final phoneStr = _profile?.phoneNumber?.trim();
    final phoneDisplay =
    (phoneStr != null && phoneStr.isNotEmpty) ? phoneStr : 'Not set';
    final timezone =
    (_profile?.timezone ?? '').trim().isNotEmpty ? _profile!.timezone : 'UTC';

    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Profile Header Card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 2),
                    image: hasAvatar
                        ? DecorationImage(
                      image: NetworkImage(avatarUrl!),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: !hasAvatar
                      ? const Icon(
                    Icons.person_rounded,
                    size: 48,
                    color: AppColors.secondary,
                  )
                      : null,
                ),
                const SizedBox(height: 14),
                Text(
                  (_profile?.fullName ?? '').trim().isNotEmpty
                      ? _profile!.fullName
                      : 'Caretaker',
                  style: AppTextStyles.h1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Caretaker',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Personal Details ──
          Text('Personal Details', style: AppTextStyles.titleMedium),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.email_outlined,
            label: 'Email',
            value: email,
          ),
          _ProfileTile(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: phoneDisplay,
          ),
          _ProfileTile(
            icon: Icons.public_rounded,
            label: 'Timezone',
            value: timezone,
          ),

          const SizedBox(height: 28),

          // ── Connected Patients Header ──
          Row(
            children: [
              Text('Connected Patients', style: AppTextStyles.titleMedium),
              const SizedBox(width: 8),
              if (_connectedPatients.isNotEmpty)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_connectedPatients.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Connected Patients List ──
          if (_connectedPatients.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 38,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 10),
                  Text('No connected patients', style: AppTextStyles.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'When you accept a patient invitation, they will appear here.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._connectedPatients.map(
                  (rel) => _ConnectedPatientCard(
                relationship: rel,
                onDisconnect: () => _disconnectPatient(rel),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CONNECTED PATIENT CARD
// ══════════════════════════════════════════════════════════════

class _ConnectedPatientCard extends StatelessWidget {
  final CareRelationship relationship;
  final VoidCallback onDisconnect;

  const _ConnectedPatientCard({
    required this.relationship,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final name = relationship.patientName.trim().isNotEmpty
        ? relationship.patientName
        : 'Patient';

    final avatarUrl = relationship.patientAvatarUrl?.trim();
    final bool hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final relType = (relationship.relationship ?? '').trim();
    final phone = relationship.patientPhone?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                child: !hasAvatar
                    ? const Icon(
                  Icons.person_rounded,
                  color: AppColors.secondary,
                  size: 22,
                )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (relType.isNotEmpty)
                      Text(
                        relType[0].toUpperCase() + relType.substring(1),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off_rounded, size: 16),
                label: const Text('Disconnect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.4),
                  ),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.phone_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  phone,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PROFILE TILE
// ══════════════════════════════════════════════════════════════

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.labelSmall),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SKELETON
// ══════════════════════════════════════════════════════════════

class _CaretakerProfileSkeleton extends StatelessWidget {
  const _CaretakerProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        SizedBox(height: 12),
        Center(child: SkeletonBox(width: 96, height: 96, borderRadius: 48)),
        SizedBox(height: 16),
        Center(child: SkeletonBox(height: 22, width: 160)),
        SizedBox(height: 32),
        SkeletonBox(height: 52, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(height: 52, borderRadius: 12),
        SizedBox(height: 28),
        SkeletonBox(height: 20, width: 140),
        SizedBox(height: 12),
        SkeletonBox(height: 72, borderRadius: 16),
      ],
    );
  }
}