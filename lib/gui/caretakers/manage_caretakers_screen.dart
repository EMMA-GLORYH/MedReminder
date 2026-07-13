// lib/gui/caretakers/manage_caretakers_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../models/care_relationship.dart';
import '../../services/care_relationship_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/snackbar/app_snackbar.dart';

class ManageCaretakersScreen extends StatefulWidget {
  const ManageCaretakersScreen({super.key});

  @override
  State<ManageCaretakersScreen> createState() => _ManageCaretakersScreenState();
}

class _ManageCaretakersScreenState extends State<ManageCaretakersScreen> {
  List<CareRelationship> _caretakers = [];
  bool    _isLoading = true;
  String? _error;

  // Realtime: watch care_relationships WHERE patient_id = me
  // so the list refreshes when a caretaker accepts in-app
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
    final patientId = supabase.auth.currentUser?.id;
    if (patientId == null) return;

    _subscription = supabase
        .channel('patient_caretakers_$patientId')
        .onPostgresChanges(
      event:    PostgresChangeEvent.all,
      schema:   'public',
      table:    'care_relationships',
      callback: (_) { if (mounted) _load(silent: true); },
    )
        .subscribe();
  }

  // ── Load ────────────────────────────────────────────────────
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _isLoading = true; _error = null; });
    try {
      final list = await CareRelationshipService.instance.getMyCaretakers();
      if (!mounted) return;
      setState(() {
        _caretakers = list;
        _isLoading  = false;
        _error      = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error     = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // ── Open invite sheet ───────────────────────────────────────
  Future<void> _openInviteSheet() async {
    final sent = await showModalBottomSheet<bool>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder:            (_) => const _InviteSheet(),
    );
    if (sent == true && mounted) _load();
  }

  // ── Resend invite email ─────────────────────────────────────
  Future<void> _resendInvite(CareRelationship rel) async {
    try {
      await CareRelationshipService.instance.resendInviteEmail(rel.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Invite resent to ${rel.displayName}');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context,
          e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ── Revoke / cancel ─────────────────────────────────────────
  Future<void> _confirmRevoke(CareRelationship rel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surface,
        title: Text(rel.isPending ? 'Cancel Invite?' : 'Remove Caretaker?'),
        content: Text(
          rel.isPending
              ? 'Cancel the pending invite to ${rel.displayName}?\n\n'
              'You can invite them again later.'
              : 'Remove ${rel.displayName} as your caretaker?\n\n'
              'They will no longer receive your medication alerts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(rel.isPending ? 'Cancel Invite' : 'Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await CareRelationshipService.instance.revokeCaretaker(rel.id);
      if (!mounted) return;
      AppSnackbar.success(
        context,
        rel.isPending
            ? 'Invite to ${rel.displayName} cancelled'
            : '${rel.displayName} removed',
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Action failed. Please try again.');
    }
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation:       0,
        title:           Text('My Caretakers', style: AppTextStyles.titleMedium),
        centerTitle:     true,
        iconTheme:       const IconThemeData(color: AppColors.primary),
        foregroundColor: AppColors.primary,
        actions: [
          if (_isLoading && _caretakers.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            ),
        ],
      ),
      body:                  _buildBody(),
      floatingActionButton:  FloatingActionButton(
        onPressed:       _openInviteSheet,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip:         'Invite Caretaker',
        child: const Icon(Icons.person_add_rounded, size: 26),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _caretakers.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_error != null && _caretakers.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded,
              size: 56, color: AppColors.error),
          const SizedBox(height: 16),
          Text('Could not load caretakers',
              style: AppTextStyles.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(_error!,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _load,
            icon:  const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ]),
      ));
    }

    if (_caretakers.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_outline_rounded,
                size: 52, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text('No caretakers yet', style: AppTextStyles.h2),
          const SizedBox(height: 8),
          Text(
            'Invite a family member, doctor, or nurse\n'
                'to monitor your medication adherence.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _openInviteSheet,
            icon:  const Icon(Icons.person_add_rounded),
            label: const Text('Invite Your First Caretaker'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      ));
    }

    return RefreshIndicator(
      color:     AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _StatsRow(caretakers: _caretakers),
          const SizedBox(height: 16),
          const _InfoBanner(),
          const SizedBox(height: 16),
          ..._caretakers.map((rel) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CaretakerCard(
              relationship: rel,
              onRevoke:     () => _confirmRevoke(rel),
              onResend:     rel.isPending ? () => _resendInvite(rel) : null,
            ),
          )),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STATS ROW
// ══════════════════════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  final List<CareRelationship> caretakers;
  const _StatsRow({required this.caretakers});

  @override
  Widget build(BuildContext context) {
    final active  = caretakers.where((r) => r.isActive).length;
    final pending = caretakers.where((r) => r.isPending).length;
    return Row(children: [
      Expanded(child: _StatChip(value: '$active',
          label: 'Active', color: Colors.greenAccent)),
      const SizedBox(width: 12),
      Expanded(child: _StatChip(value: '$pending',
          label: 'Pending', color: AppColors.warning)),
      const SizedBox(width: 12),
      Expanded(child: _StatChip(value: '${caretakers.length}',
          label: 'Total', color: AppColors.primary)),
    ]);
  }
}

class _StatChip extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _StatChip({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Text(value, style: AppTextStyles.h2.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.bodySmall),
      ]),
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
        color:        AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Caretakers receive SOS alerts and missed-dose notifications. '
                'Pending invites are waiting for the caretaker to accept in the app.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CARETAKER CARD
// ══════════════════════════════════════════════════════════════
class _CaretakerCard extends StatefulWidget {
  final CareRelationship relationship;
  final VoidCallback     onRevoke;
  final VoidCallback?    onResend;

  const _CaretakerCard({
    required this.relationship,
    required this.onRevoke,
    this.onResend,
  });

  @override
  State<_CaretakerCard> createState() => _CaretakerCardState();
}

class _CaretakerCardState extends State<_CaretakerCard> {
  bool _isResending = false;

  Future<void> _handleResend() async {
    setState(() => _isResending = true);
    widget.onResend?.call();
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _isResending = false);
  }

  Color get _statusColor {
    if (widget.relationship.isActive)  return Colors.greenAccent;
    if (widget.relationship.isPending) return AppColors.warning;
    return AppColors.error;
  }

  String get _statusLabel {
    if (widget.relationship.isActive)  return 'Active';
    if (widget.relationship.isPending) return 'Pending';
    return 'Revoked';
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.relationship;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: rel.isPending
              ? AppColors.warning.withValues(alpha: 0.35)
              : rel.isActive
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset:     const Offset(0, 3),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──────────────────────────────────────────
        Row(children: [
          _Avatar(name: rel.displayName, url: rel.profileAvatarUrl),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rel.displayName,
                style:    AppTextStyles.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            if (rel.profilePhone != null && rel.profilePhone!.isNotEmpty)
              Text(rel.profilePhone!,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
            if (rel.relationship != null)
              Text(rel.relationshipLabel,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.primary)),
          ])),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        _statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: _statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(_statusLabel,
                style: AppTextStyles.labelSmall.copyWith(
                    color: _statusColor, fontWeight: FontWeight.bold)),
          ),
        ]),

        // ── Pending notice ───────────────────────────────────
        if (rel.isPending) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:        AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Icon(Icons.schedule_rounded,
                  size: 14, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting for ${rel.displayName} to open the app and accept.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.warning),
                ),
              ),
            ]),
          ),
        ],

        // ── Active notice ───────────────────────────────────
        if (rel.isActive) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:        Colors.greenAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded,
                  size: 14, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Active since ${_formatDate(rel.acceptedAt ?? rel.invitedAt)}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: Colors.greenAccent),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 12),
        Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 10),

        // ── Permissions ──────────────────────────────────────
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (rel.canViewLogs)
            _PermChip(label: 'View Logs',
                icon: Icons.history_rounded),
          if (rel.canViewMedications)
            _PermChip(label: 'View Meds',
                icon: Icons.medication_rounded),
          if (rel.canReceiveAlerts)
            _PermChip(label: 'SOS Alerts',
                icon: Icons.sos_rounded),
          if (rel.canEditMedications)
            _PermChip(label: 'Edit Meds',
                icon: Icons.edit_rounded,
                color: AppColors.warning),
        ]),

        const SizedBox(height: 12),

        // ── Footer actions ───────────────────────────────────
        Row(children: [
          Icon(Icons.calendar_today_rounded,
              size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Invited ${_formatDate(rel.invitedAt)}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),

          // Resend (pending only)
          if (rel.isPending && widget.onResend != null)
            TextButton.icon(
              onPressed: _isResending ? null : _handleResend,
              icon: _isResending
                  ? const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary))
                  : const Icon(Icons.send_rounded, size: 14),
              label: Text(_isResending ? 'Sending…' : 'Resend'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),

          // Remove / Cancel
          TextButton.icon(
            onPressed: widget.onRevoke,
            icon:  const Icon(Icons.person_remove_rounded, size: 14),
            label: Text(rel.isPending ? 'Cancel' : 'Remove'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ]),
      ]),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _Avatar extends StatelessWidget {
  final String  name;
  final String? url;
  const _Avatar({required this.name, this.url});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius:          24,
      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      backgroundImage: (url != null && url!.isNotEmpty)
          ? NetworkImage(url!) : null,
      child: (url == null || url!.isEmpty)
          ? Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
            color:      AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize:   18),
      )
          : null,
    );
  }
}

class _PermChip extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color?   color;
  const _PermChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: c)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INVITE BOTTOM SHEET
// ══════════════════════════════════════════════════════════════
class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  String? _relationship;
  bool    _canEdit   = false;
  bool    _isSending = false;

  static const _relationships = [
    ('family',    'Family',    Icons.family_restroom_rounded),
    ('doctor',    'Doctor',    Icons.local_hospital_rounded),
    ('nurse',     'Nurse',     Icons.medical_services_rounded),
    ('caregiver', 'Caregiver', Icons.favorite_rounded),
  ];

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    try {
      await CareRelationshipService.instance.inviteCaretaker(
        caretakerEmail:     _emailCtrl.text.trim(),
        relationship:       _relationship,
        canEditMedications: _canEdit,
      );
      if (!mounted) return;

      // Show success dialog then close sheet
      await showDialog(
        context:            context,
        barrierDismissible: false,
        builder: (_) => _InviteSuccessDialog(
            email: _emailCtrl.text.trim()),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ));
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color:        AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text('Invite a Caretaker', style: AppTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  'They will receive an email invite and accept it inside the app.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),

                const SizedBox(height: 24),

                // Email field
                TextFormField(
                  controller:      _emailCtrl,
                  keyboardType:    TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText:  "Caretaker's Email Address",
                    hintText:   'name@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    filled:    true,
                    fillColor: AppColors.background,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Relationship chips
                Text('Relationship (optional)',
                    style: AppTextStyles.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing:    8,
                  runSpacing: 8,
                  children: _relationships.map((r) {
                    final (value, label, icon) = r;
                    final selected = _relationship == value;
                    return GestureDetector(
                      onTap: () => setState(() =>
                      _relationship = selected ? null : value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary : AppColors.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon, size: 16,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(label,
                              style: AppTextStyles.labelMedium.copyWith(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.textPrimary)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // Can edit toggle
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:        AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border:       Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.edit_rounded, size: 20,
                        color: _canEdit
                            ? AppColors.warning
                            : AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Allow editing medications',
                              style: AppTextStyles.titleSmall),
                          Text('They can add or change your medication list',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        ])),
                    Switch(
                      value:       _canEdit,
                      onChanged:   (v) => setState(() => _canEdit = v),
                      activeColor: AppColors.primary,
                    ),
                  ]),
                ),

                const SizedBox(height: 28),

                // Send button
                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      _isSending ? 'Sending Invite…' : 'Send Invite',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INVITE SUCCESS DIALOG
// ══════════════════════════════════════════════════════════════
class _InviteSuccessDialog extends StatelessWidget {
  final String email;
  const _InviteSuccessDialog({required this.email});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35), width: 2),
          boxShadow: [
            BoxShadow(
                color:      AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 32),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Icon
          Stack(alignment: Alignment.center, children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                color:  AppColors.primary.withValues(alpha: 0.08),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    width: 2),
              ),
            ),
            Container(
              width: 66, height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.mark_email_read_rounded,
                  color: AppColors.primary, size: 36),
            ),
          ]),

          const SizedBox(height: 20),

          Text('Invite Sent!',
              style: AppTextStyles.h2, textAlign: TextAlign.center),

          const SizedBox(height: 10),

          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              children: [
                const TextSpan(text: 'An invite was sent to\n'),
                TextSpan(
                  text: email,
                  style: AppTextStyles.bodyMedium.copyWith(
                      color:      AppColors.primary,
                      fontWeight: FontWeight.bold),
                ),
                const TextSpan(
                  text: '\n\nThey need to open MedReminder '
                      'and go to Pending Invites to accept.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          SizedBox(
            width:  double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}