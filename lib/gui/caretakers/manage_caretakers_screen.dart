// lib/gui/caretakers/manage_caretakers_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/care_relationship.dart';
import '../../services/care_relationship_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/snackbar/app_snackbar.dart';

const Color _activeGreen = Color(0xFF16834C);

class ManageCaretakersScreen extends StatefulWidget {
  const ManageCaretakersScreen({super.key});

  @override
  State<ManageCaretakersScreen> createState() =>
      _ManageCaretakersScreenState();
}

class _ManageCaretakersScreenState
    extends State<ManageCaretakersScreen> {
  List<CareRelationship> _caretakers = [];

  bool _isLoading = true;
  String? _error;

  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToChanges();
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }

  void _subscribeToChanges() {
    _subscription = CareRelationshipService.instance
        .subscribeToMyCaretakers(() {
      if (mounted) {
        _load(silent: true);
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final list =
      await CareRelationshipService.instance.getMyCaretakers();

      if (!mounted) return;

      setState(() {
        _caretakers = list;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openInviteSheet() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _InviteSheet(),
    );

    if (sent == true && mounted) {
      await _load(silent: true);
    }
  }

  Future<void> _resendInvite(CareRelationship relationship) async {
    try {
      await CareRelationshipService.instance.resendInviteEmail(
        relationship.id,
      );

      if (!mounted) return;

      AppSnackbar.success(
        context,
        'Invite resent to ${relationship.displayName}',
      );
    } catch (e) {
      if (!mounted) return;

      AppSnackbar.error(
        context,
        e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> _confirmRevoke(
      CareRelationship relationship,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: AppColors.surface,
        title: Text(
          relationship.isPending
              ? 'Cancel Invite?'
              : 'Remove Caretaker?',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          relationship.isPending
              ? 'Cancel the pending invite to '
              '${relationship.displayName}?\n\n'
              'You can invite them again later.'
              : 'Remove ${relationship.displayName} as your '
              'caretaker?\n\nThey will no longer receive '
              'your medication or SOS alerts.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: Text(
              relationship.isPending
                  ? 'Cancel Invite'
                  : 'Remove',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await CareRelationshipService.instance.revokeCaretaker(
        relationship.id,
      );

      if (!mounted) return;

      AppSnackbar.success(
        context,
        relationship.isPending
            ? 'Invite to ${relationship.displayName} cancelled'
            : '${relationship.displayName} removed',
      );

      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;

      AppSnackbar.error(
        context,
        'Action failed. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: AppColors.secondary,
        ),
        foregroundColor: AppColors.secondary,
        title: Text(
          'My Caretakers',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_isLoading && _caretakers.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openInviteSheet,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.secondary,
        elevation: 6,
        shape: const CircleBorder(),
        tooltip: 'Invite Caretaker',
        child: const Icon(
          Icons.person_add_rounded,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _caretakers.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_error != null && _caretakers.isEmpty) {
      return _ErrorView(
        message: _error!,
        onRetry: () => _load(),
      );
    }

    if (_caretakers.isEmpty) {
      return _EmptyCaretakers(
        onAdd: _openInviteSheet,
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _StatsRow(caretakers: _caretakers),
          const SizedBox(height: 16),
          const _InfoBanner(),
          const SizedBox(height: 18),
          Text(
            'Care Network',
            style: AppTextStyles.h2.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._caretakers.map(
                (relationship) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CaretakerCard(
                relationship: relationship,
                onRevoke: () => _confirmRevoke(relationship),
                onResend: relationship.isPending
                    ? () => _resendInvite(relationship)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STATS
// ══════════════════════════════════════════════════════════════

class _StatsRow extends StatelessWidget {
  final List<CareRelationship> caretakers;

  const _StatsRow({
    required this.caretakers,
  });

  @override
  Widget build(BuildContext context) {
    final active = caretakers.where((item) => item.isActive).length;
    final pending = caretakers.where((item) => item.isPending).length;

    return Row(
      children: [
        Expanded(
          child: _StatChip(
            value: '$active',
            label: 'Active',
            color: _activeGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            value: '$pending',
            label: 'Pending',
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            value: '${caretakers.length}',
            label: 'Total',
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatChip({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.h2.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INFO BANNER
// ══════════════════════════════════════════════════════════════

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.secondary,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Active caretakers can receive SOS alerts and '
                  'medication notifications. Pending invites must '
                  'be accepted first.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CARETAKER CARD
// ══════════════════════════════════════════════════════════════

class _CaretakerCard extends StatefulWidget {
  final CareRelationship relationship;
  final VoidCallback onRevoke;
  final Future<void> Function()? onResend;

  const _CaretakerCard({
    required this.relationship,
    required this.onRevoke,
    this.onResend,
  });

  @override
  State<_CaretakerCard> createState() =>
      _CaretakerCardState();
}

class _CaretakerCardState extends State<_CaretakerCard> {
  bool _isResending = false;

  Future<void> _handleResend() async {
    if (_isResending || widget.onResend == null) return;

    setState(() => _isResending = true);

    try {
      await widget.onResend!.call();
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Color get _statusColor {
    if (widget.relationship.isActive) {
      return _activeGreen;
    }

    if (widget.relationship.isPending) {
      return AppColors.warning;
    }

    return AppColors.error;
  }

  String get _statusLabel {
    if (widget.relationship.isActive) return 'Active';
    if (widget.relationship.isPending) return 'Pending';

    return 'Revoked';
  }

  @override
  Widget build(BuildContext context) {
    final relationship = widget.relationship;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: relationship.isPending
              ? AppColors.warning.withValues(alpha: 0.40)
              : relationship.isActive
              ? _activeGreen.withValues(alpha: 0.35)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                name: relationship.displayName,
                url: relationship.profileAvatarUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      relationship.displayName,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (relationship.profilePhone != null &&
                        relationship.profilePhone!.isNotEmpty)
                      Text(
                        relationship.profilePhone!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (relationship.relationship != null)
                      Text(
                        relationship.relationshipLabel,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusBadge(
                label: _statusLabel,
                color: _statusColor,
              ),
            ],
          ),

          if (relationship.isPending) ...[
            const SizedBox(height: 12),
            _StatusNotice(
              icon: Icons.schedule_rounded,
              text:
              'Waiting for ${relationship.displayName} '
                  'to accept the invitation.',
              color: AppColors.warning,
            ),
          ],

          if (relationship.isActive) ...[
            const SizedBox(height: 12),
            _StatusNotice(
              icon: Icons.check_circle_rounded,
              text:
              'Active since ${_formatDate(relationship.acceptedAt ?? relationship.invitedAt)}',
              color: _activeGreen,
            ),
          ],

          const SizedBox(height: 12),
          Divider(
            color: AppColors.border,
            height: 1,
          ),
          const SizedBox(height: 11),

          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (relationship.canViewLogs)
                const _PermChip(
                  label: 'View Logs',
                  icon: Icons.history_rounded,
                ),
              if (relationship.canViewMedications)
                const _PermChip(
                  label: 'View Meds',
                  icon: Icons.medication_rounded,
                ),
              if (relationship.canReceiveAlerts)
                const _PermChip(
                  label: 'SOS Alerts',
                  icon: Icons.sos_rounded,
                  color: _activeGreen,
                ),
              if (relationship.canEditMedications)
                const _PermChip(
                  label: 'Edit Meds',
                  icon: Icons.edit_rounded,
                  color: AppColors.warning,
                ),
            ],
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 12,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Invited ${_formatDate(relationship.invitedAt)}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              if (relationship.isPending &&
                  widget.onResend != null)
                TextButton.icon(
                  onPressed:
                  _isResending ? null : _handleResend,
                  icon: _isResending
                      ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.secondary,
                    ),
                  )
                      : const Icon(
                    Icons.send_rounded,
                    size: 14,
                  ),
                  label: Text(
                    _isResending ? 'Sending…' : 'Resend',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

              TextButton.icon(
                onPressed: widget.onRevoke,
                icon: const Icon(
                  Icons.person_remove_rounded,
                  size: 14,
                ),
                label: Text(
                  relationship.isPending
                      ? 'Cancel'
                      : 'Remove',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[local.month - 1]} '
        '${local.day}, ${local.year}';
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;

  const _Avatar({
    required this.name,
    this.url,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = url != null && url!.trim().isNotEmpty;

    return CircleAvatar(
      radius: 24,
      backgroundColor:
      AppColors.primary.withValues(alpha: 0.18),
      backgroundImage:
      hasImage ? NetworkImage(url!) : null,
      child: !hasImage
          ? Text(
        name.isNotEmpty
            ? name[0].toUpperCase()
            : '?',
        style: const TextStyle(
          color: AppColors.secondary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      )
          : null,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _StatusNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _PermChip({
    required this.label,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: chipColor.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: chipColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: chipColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════

class _EmptyCaretakers extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyCaretakers({
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(
                      alpha: 0.14,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.people_outline_rounded,
                    size: 52,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'No caretakers yet',
                  style: AppTextStyles.h2.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Invite a family member, doctor, or nurse '
                      'to monitor your medication adherence and '
                      'receive SOS alerts.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(
                    Icons.person_add_rounded,
                  ),
                  label: const Text(
                    'Invite Your First Caretaker',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                  ),
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
// ERROR VIEW
// ══════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 56,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load caretakers',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INVITE BOTTOM SHEET
// ══════════════════════════════════════════════════════════════

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() =>
      _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  String? _relationship;
  bool _canEdit = false;
  bool _isSending = false;

  static const _relationships = [
    (
    'family',
    'Family',
    Icons.family_restroom_rounded,
    ),
    (
    'doctor',
    'Doctor',
    Icons.local_hospital_rounded,
    ),
    (
    'nurse',
    'Nurse',
    Icons.medical_services_rounded,
    ),
    (
    'caregiver',
    'Caregiver',
    Icons.favorite_rounded,
    ),
  ];

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      await CareRelationshipService.instance
          .inviteCaretaker(
        caretakerEmail:
        _emailController.text.trim(),
        relationship: _relationship,
        canEditMedications: _canEdit,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _InviteSuccessDialog(
          email: _emailController.text.trim(),
        ),
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll(
              'Exception: ',
              '',
            ),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom =
        MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + keyboardBottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius:
                    BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Invite a Caretaker',
                style: AppTextStyles.h2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'They will receive an invitation and '
                    'accept it inside the app.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 24),

              TextFormField(
                controller: _emailController,
                keyboardType:
                TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText:
                  "Caretaker's Email Address",
                  hintText: 'name@example.com',
                  hintStyle:
                  AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  labelStyle:
                  AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: AppColors.secondary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';

                  if (email.isEmpty) {
                    return 'Email is required';
                  }

                  final validEmail = RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch(email);

                  if (!validEmail) {
                    return 'Enter a valid email address';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 20),

              Text(
                'Relationship (optional)',
                style: AppTextStyles.titleSmall.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _relationships.map((item) {
                  final (value, label, icon) = item;
                  final selected =
                      _relationship == value;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _relationship =
                        selected ? null : value;
                      });
                    },
                    borderRadius:
                    BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration:
                      const Duration(milliseconds: 150),
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(
                          alpha: 0.15,
                        )
                            : AppColors.background,
                        borderRadius:
                        BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 16,
                            color: selected
                                ? AppColors.secondary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: AppTextStyles
                                .labelMedium
                                .copyWith(
                              color: selected
                                  ? AppColors.secondary
                                  : AppColors.textPrimary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius:
                  BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      size: 20,
                      color: _canEdit
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Allow editing medications',
                            style: AppTextStyles.titleSmall
                                .copyWith(
                              color:
                              AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'They can add or change your medication list',
                            style: AppTextStyles.bodySmall
                                .copyWith(
                              color: AppColors
                                  .textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _canEdit,
                      onChanged: (value) {
                        setState(() {
                          _canEdit = value;
                        });
                      },
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed:
                  _isSending ? null : _send,
                  icon: _isSending
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.secondary,
                    ),
                  )
                      : const Icon(
                    Icons.send_rounded,
                    size: 20,
                  ),
                  label: Text(
                    _isSending
                        ? 'Sending Invite…'
                        : 'Send Invite',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    AppColors.primary,
                    foregroundColor:
                    AppColors.secondary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SUCCESS DIALOG
// ══════════════════════════════════════════════════════════════

class _InviteSuccessDialog extends StatelessWidget {
  final String email;

  const _InviteSuccessDialog({
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(
              alpha: 0.40,
            ),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(
                alpha: 0.15,
              ),
              blurRadius: 32,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(
                      alpha: 0.08,
                    ),
                    border: Border.all(
                      color: AppColors.primary
                          .withValues(alpha: 0.25),
                      width: 2,
                    ),
                  ),
                ),
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(
                      alpha: 0.14,
                    ),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_rounded,
                    color: AppColors.secondary,
                    size: 36,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              'Invite Sent!',
              style: AppTextStyles.h2.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                children: [
                  const TextSpan(
                    text: 'An invite was sent to\n',
                  ),
                  TextSpan(
                    text: email,
                    style:
                    AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(
                    text:
                    '\n\nThey must open MedReminder '
                        'and accept it under Pending Invites.',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primary,
                  foregroundColor:
                  AppColors.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'Got it',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}