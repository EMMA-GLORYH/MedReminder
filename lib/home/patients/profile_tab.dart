// lib/home/patients/profile_tab.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<Map<String, dynamic>> _caretakers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = AuthService.instance.currentUser?.id;

      if (userId == null) {
        if (mounted) {
          setState(() {
            _error = 'No user session found.';
            _isLoading = false;
          });
        }
        return;
      }

      // ── Load profile directly ──────────────────────────────
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      Profile? profile;
      if (profileData != null) {
        profile = Profile.fromJson(
          Map<String, dynamic>.from(profileData as Map),
        );
      }

      // ── Load caretakers ────────────────────────────────────
      List<Map<String, dynamic>> caretakers = [];

      try {
        final response = await Supabase.instance.client
            .from('care_relationships')
            .select('''
              id,
              relationship,
              status,
              can_view_logs,
              can_view_medications,
              can_receive_alerts,
              can_edit_medications,
              alert_threshold_mins,
              created_at,
              caregiver:profiles!care_relationships_caregiver_id_fkey (
                id,
                full_name,
                phone_number,
                avatar_url
              )
            ''')
            .eq('patient_id', userId)
            .inFilter('status', ['pending', 'active'])
            .order('created_at', ascending: false);

        if (response is List) {
          caretakers = response
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } catch (dbErr) {
        debugPrint('⚠️ Error fetching care relationships: $dbErr');
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _caretakers = caretakers;
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('❌ Error loading profile tab: $e');
      debugPrint('$stack');
      if (mounted) {
        setState(() {
          _error = 'Could not load profile. Pull down to retry.';
          _isLoading = false;
        });
      }
    }
  }

  // ── Safe string helpers — never call on nullable directly ──

  String _safeName() {
    final name = _profile?.fullName;
    if (name == null) return 'User';
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'User' : trimmed;
  }

  String _safePhone() {
    final phone = _profile?.phoneNumber;
    if (phone == null) return 'Not provided';
    final trimmed = phone.trim();
    return trimmed.isEmpty ? 'Not provided' : trimmed;
  }

  String _safeTimezone() {
    final tz = _profile?.timezone;
    if (tz == null) return 'UTC';
    final trimmed = tz.trim();
    return trimmed.isEmpty ? 'UTC' : trimmed;
  }

  String _safeRole() {
    if (_profile == null) return 'User';
    if (_profile!.isPatient) return 'Patient';
    if (_profile!.isCaretaker) return 'Caretaker';
    return 'User';
  }

  String _safeEmail() {
    final email = AuthService.instance.currentUser?.email;
    if (email == null) return '—';
    final trimmed = email.trim();
    return trimmed.isEmpty ? '—' : trimmed;
  }

  bool _hasAvatar() {
    final url = _profile?.avatarUrl;
    if (url == null) return false;
    return url.trim().isNotEmpty;
  }

  String _avatarUrl() => _profile!.avatarUrl!.trim();

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _ProfileSkeleton();

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadProfileData,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProfileData,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _buildHeader(),
          const SizedBox(height: 28),
          _buildPersonalDetails(),
          const SizedBox(height: 28),
          _buildCaretakersSection(),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────

  Widget _buildHeader() {
    final hasAvatar = _hasAvatar();

    return Column(
      children: [
        // Avatar
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
              width: 2,
            ),
            image: hasAvatar
                ? DecorationImage(
              image: NetworkImage(_avatarUrl()),
              fit: BoxFit.cover,
            )
                : null,
          ),
          child: !hasAvatar
              ? const Icon(
            Icons.person_rounded,
            size: 42,
            color: AppColors.secondary,
          )
              : null,
        ),

        const SizedBox(height: 12),

        // Name
        Text(
          _safeName(),
          style: AppTextStyles.h1,
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 6),

        // Role badge
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            _safeRole(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ── Personal details ─────────────────────────────────────────

  Widget _buildPersonalDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Personal Details', style: AppTextStyles.titleMedium),
        const SizedBox(height: 10),
        _ProfileTile(
          icon: Icons.email_outlined,
          label: 'Email',
          value: _safeEmail(),
        ),
        _ProfileTile(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: _safePhone(),
        ),
        _ProfileTile(
          icon: Icons.public_rounded,
          label: 'Timezone',
          value: _safeTimezone(),
        ),
      ],
    );
  }

  // ── Caretakers section ───────────────────────────────────────

  Widget _buildCaretakersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Text('Caretakers', style: AppTextStyles.titleMedium),
            const SizedBox(width: 8),
            if (_caretakers.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_caretakers.length}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 12),

        // Empty state
        if (_caretakers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 28,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.supervisor_account_outlined,
                  size: 40,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
                Text(
                  'No caretakers linked yet',
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'When someone connects to your account\nas a caretaker, they will appear here.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._caretakers.map(
                (rel) => _CaretakerCard(relationship: rel),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CARETAKER CARD
// ══════════════════════════════════════════════════════════════

class _CaretakerCard extends StatelessWidget {
  final Map<String, dynamic> relationship;

  const _CaretakerCard({required this.relationship});

  // ── Safe extraction helpers ───────────────────────────────

  Map<String, dynamic> _caregiver() {
    final raw = relationship['caregiver'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return {};
  }

  String _name(Map<String, dynamic> cg) {
    final raw = cg['full_name'];
    if (raw == null) return 'Caretaker';
    final trimmed = raw.toString().trim();
    return trimmed.isEmpty ? 'Caretaker' : trimmed;
  }

  String? _avatarUrl(Map<String, dynamic> cg) {
    final raw = cg['avatar_url'];
    if (raw == null) return null;
    final trimmed = raw.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _phone(Map<String, dynamic> cg) {
    final raw = cg['phone_number'];
    if (raw == null) return null;
    final trimmed = raw.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _relLabel() {
    final raw = relationship['relationship'];
    if (raw == null) return 'Caregiver';
    switch (raw.toString().toLowerCase().trim()) {
      case 'family':
        return 'Family Member';
      case 'doctor':
        return 'Doctor';
      case 'nurse':
        return 'Nurse';
      case 'caregiver':
        return 'Caregiver';
      default:
        return 'Caregiver';
    }
  }

  String _statusLabel() {
    final raw = relationship['status'];
    if (raw == null) return 'Pending';
    final s = raw.toString().trim();
    if (s.isEmpty) return 'Pending';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  Color _statusColor() {
    final raw = relationship['status'];
    if (raw == null) return AppColors.textSecondary;
    switch (raw.toString().toLowerCase().trim()) {
      case 'active':
        return AppColors.primary;
      case 'pending':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cg = _caregiver();
    final fullName = _name(cg);
    final avatarUrl = _avatarUrl(cg);
    final phone = _phone(cg);
    final statusColor = _statusColor();

    final canLogs = relationship['can_view_logs'] == true;
    final canMeds = relationship['can_view_medications'] == true;
    final canAlert = relationship['can_receive_alerts'] == true;
    final canEdit = relationship['can_edit_medications'] == true;

    final hasAnyPermission = canLogs || canMeds || canAlert || canEdit;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // ── Main row ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                  AppColors.primary.withValues(alpha: 0.12),
                  backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(
                    Icons.person_rounded,
                    color: AppColors.secondary,
                    size: 24,
                  )
                      : null,
                ),

                const SizedBox(width: 12),

                // Name + type
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: AppTextStyles.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _relLabel(),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (phone != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 11,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              phone,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Permissions row ──────────────────────────────────
          if (hasAnyPermission) ...[
            Divider(
              height: 1,
              color: AppColors.border,
              indent: 14,
              endIndent: 14,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (canLogs)
                    const _PermissionBadge(
                      label: 'View Logs',
                      icon: Icons.history_rounded,
                    ),
                  if (canMeds)
                    const _PermissionBadge(
                      label: 'Medications',
                      icon: Icons.medication_outlined,
                    ),
                  if (canAlert)
                    const _PermissionBadge(
                      label: 'Alerts',
                      icon: Icons.notifications_active_outlined,
                    ),
                  if (canEdit)
                    const _PermissionBadge(
                      label: 'Can Edit',
                      icon: Icons.edit_note_rounded,
                      isWarning: true,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PERMISSION BADGE
// ══════════════════════════════════════════════════════════════

class _PermissionBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isWarning;

  const _PermissionBadge({
    required this.label,
    required this.icon,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? AppColors.warning : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontSize: 10,
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: const [
        Center(
          child: SkeletonBox(width: 88, height: 88, borderRadius: 44),
        ),
        SizedBox(height: 14),
        Center(
          child: SkeletonBox(height: 22, width: 160, borderRadius: 6),
        ),
        SizedBox(height: 8),
        Center(
          child: SkeletonBox(height: 24, width: 80, borderRadius: 20),
        ),
        SizedBox(height: 32),
        SkeletonBox(width: 130, height: 18, borderRadius: 6),
        SizedBox(height: 10),
        SkeletonBox(height: 54, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(height: 54, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(height: 54, borderRadius: 12),
        SizedBox(height: 32),
        SkeletonBox(width: 110, height: 18, borderRadius: 6),
        SizedBox(height: 12),
        SkeletonBox(height: 100, borderRadius: 16),
        SizedBox(height: 10),
        SkeletonBox(height: 100, borderRadius: 16),
      ],
    );
  }
}