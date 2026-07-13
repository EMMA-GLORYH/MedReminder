// lib/screens/gui/caretakers/pending_invites_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/care_relationship.dart';
import '../../services/care_relationship_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/snackbar/app_snackbar.dart';

// Invites fetched per indexed page. Small enough to render a clean first
// screen; large enough that most caretakers never need to scroll.
const _kPageSize = 10;

class PendingInvitesScreen extends StatefulWidget {
  const PendingInvitesScreen({super.key});

  @override
  State<PendingInvitesScreen> createState() => _PendingInvitesScreenState();
}

class _PendingInvitesScreenState extends State<PendingInvitesScreen> {
  List<CareRelationship> _invites = [];

  bool _isFirstLoad   = true;
  bool _isLoadingMore = false;
  bool _hasMore       = true;
  int  _offset        = 0;
  int? _totalCount;    // accurate total from a lightweight count query
  String? _error;

  final ScrollController _scrollController = ScrollController();

  // Realtime subscription handle
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshAll();
    // Subscribe to live changes so if a patient cancels/resends, this
    // screen updates automatically without pulling to refresh. Any change
    // resets pagination back to page 0, since we can't know where in the
    // index the changed row now falls.
    _subscription = CareRelationshipService.instance
        .subscribeToMyInvites(_refreshAll);
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Index page 0 — resets pagination state ────────────────────────
  Future<void> _refreshAll() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      if (_invites.isEmpty) _isFirstLoad = true;
    });

    try {
      final results = await Future.wait([
        CareRelationshipService.instance
            .getPendingInvitesPage(offset: 0, limit: _kPageSize),
        CareRelationshipService.instance.getPendingInviteCount(),
      ]);

      final firstPage = results[0] as List<CareRelationship>;
      final total     = results[1] as int;

      if (!mounted) return;
      setState(() {
        _invites     = firstPage;
        _offset      = firstPage.length;
        _hasMore     = firstPage.length == _kPageSize;
        _totalCount  = total;
        _isFirstLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFirstLoad = false;
        if (_invites.isEmpty) _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ── Next index page — appends, never replaces ─────────────────────
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final next = await CareRelationshipService.instance
          .getPendingInvitesPage(offset: _offset, limit: _kPageSize);

      if (!mounted) return;
      setState(() {
        _invites       = [..._invites, ...next];
        _offset        += next.length;
        _hasMore       = next.length == _kPageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    const threshold = 300.0;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - threshold) {
      _loadMore();
    }
  }

  Future<void> _accept(CareRelationship invite) async {
    try {
      await CareRelationshipService.instance.acceptInvite(invite.id);
      if (!mounted) return;
      _showAcceptedDialog(invite.displayName);
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Could not accept invite. Please try again.');
    }
  }

  Future<void> _decline(CareRelationship invite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surface,
        title: const Text('Decline Invite?'),
        content: Text(
          'Decline the invite from ${invite.displayName}?\n\n'
              'They can send you another invite later.',
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
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await CareRelationshipService.instance.declineInvite(invite.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Invite from ${invite.displayName} declined');
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Could not decline invite. Please try again.');
    }
  }

  void _showAcceptedDialog(String patientName) {
    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4), width: 2),
            boxShadow: [
              BoxShadow(
                  color:      AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 32),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width:  76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.1),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 2),
              ),
              child: const Icon(Icons.handshake_rounded,
                  color: AppColors.primary, size: 38),
            ),

            const SizedBox(height: 20),

            Text("You're now a Caretaker!",
                style:     AppTextStyles.h2,
                textAlign: TextAlign.center),

            const SizedBox(height: 10),

            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                children: [
                  const TextSpan(text: 'You are now monitoring '),
                  TextSpan(
                    text: patientName,
                    style: AppTextStyles.bodyMedium.copyWith(
                        color:      AppColors.primary,
                        fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                    text: ".\n\nYou'll receive alerts when they miss "
                        'a dose or press SOS.',
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
                child: const Text('Great!',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation:       0,
        iconTheme:       const IconThemeData(color: AppColors.primary),
        foregroundColor: AppColors.primary,
        title: Row(
          children: [
            Text('Pending Invites', style: AppTextStyles.titleMedium),
            if ((_totalCount ?? 0) > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        AppColors.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_totalCount ?? _invites.length}',
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isFirstLoad) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_error != null && _invites.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              size: 56, color: AppColors.error),
          const SizedBox(height: 16),
          Text('Could not load invites',
              style: AppTextStyles.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
              onPressed: _refreshAll,
              icon:  const Icon(Icons.refresh_rounded),
              label: const Text('Retry')),
        ]),
      ));
    }

    if (_invites.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inbox_rounded,
                size: 52, color: AppColors.primary.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 24),
          Text('No pending invites', style: AppTextStyles.h2),
          const SizedBox(height: 8),
          Text(
            'When a patient invites you as their\ncaretaker it will appear here.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ]),
      ));
    }

    final itemCount = _invites.length + (_hasMore ? 1 : 0);

    return RefreshIndicator(
      color:     AppColors.primary,
      onRefresh: _refreshAll,
      child: ListView.separated(
        controller:       _scrollController,
        padding:          const EdgeInsets.all(16),
        itemCount:        itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i >= _invites.length) {
            // Trailing row: spinner while a page is in flight, otherwise
            // an invisible sentinel that simply triggers _onScroll.
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
                    : const SizedBox(height: 22),
              ),
            );
          }

          return _InviteCard(
            invite:    _invites[i],
            onAccept:  () async => _accept(_invites[i]),
            onDecline: () async => _decline(_invites[i]),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INVITE CARD
// ══════════════════════════════════════════════════════════════
class _InviteCard extends StatefulWidget {
  final CareRelationship invite;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  bool _isAccepting  = false;
  bool _isDeclining  = false;

  Future<void> _handleAccept() async {
    setState(() => _isAccepting = true);
    await widget.onAccept();
    if (mounted) setState(() => _isAccepting = false);
  }

  Future<void> _handleDecline() async {
    setState(() => _isDeclining = true);
    await widget.onDecline();
    if (mounted) setState(() => _isDeclining = false);
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final busy   = _isAccepting || _isDeclining;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Row(children: [
          // Avatar
          CircleAvatar(
            radius:          26,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            backgroundImage: invite.displayAvatar.isNotEmpty
                ? NetworkImage(invite.displayAvatar) : null,
            child: invite.displayAvatar.isEmpty
                ? Text(
                invite.displayName.isNotEmpty
                    ? invite.displayName[0].toUpperCase() : '?',
                style: TextStyle(
                    color:      AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize:   20))
                : null,
          ),

          const SizedBox(width: 14),

          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invite.displayName,
                    style:    AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (invite.displayPhone.isNotEmpty)
                  Text(invite.displayPhone,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
              ])),

          // Pending badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Text('Pending',
                style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.warning, fontWeight: FontWeight.bold)),
          ),
        ]),

        const SizedBox(height: 16),

        // ── Details ──
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            _DetailRow(
              icon:  Icons.medical_information_rounded,
              label: 'Relationship',
              value: invite.relationshipLabel,
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon:  Icons.notifications_active_rounded,
              label: 'Alert threshold',
              value: '${invite.alertThresholdMins} minutes late',
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon:  Icons.calendar_today_rounded,
              label: 'Invited',
              value: _formatDate(invite.invitedAt),
            ),
          ]),
        ),

        const SizedBox(height: 14),

        // ── Permissions preview ──
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (invite.canViewLogs)
            _PermBadge(label: 'View logs',   icon: Icons.history_rounded),
          if (invite.canViewMedications)
            _PermBadge(label: 'View meds',   icon: Icons.medication_rounded),
          if (invite.canReceiveAlerts)
            _PermBadge(label: 'SOS alerts',  icon: Icons.sos_rounded),
          if (invite.canEditMedications)
            _PermBadge(label: 'Edit meds',   icon: Icons.edit_rounded,
                color: AppColors.warning),
        ]),

        const SizedBox(height: 18),

        // ── Action buttons ──
        Row(children: [
          // Decline
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : _handleDecline,
              icon: _isDeclining
                  ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.error))
                  : const Icon(Icons.close_rounded, size: 18),
              label: const Text('Decline'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side:            BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                padding:         const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Accept
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: busy ? null : _handleAccept,
              icon: _isAccepting
                  ? const SizedBox(
                  width:  16,
                  height: 16,
                  child:  CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(_isAccepting ? 'Accepting…' : 'Accept'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:         const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h  = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m  = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m $ap';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: AppColors.textSecondary),
      const SizedBox(width: 8),
      Text('$label: ', style: AppTextStyles.labelSmall),
      Expanded(
        child: Text(value,
            style:    AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

class _PermBadge extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color?   color;
  const _PermBadge({required this.label, required this.icon, this.color});

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
        Text(label,
            style: AppTextStyles.labelSmall.copyWith(color: c)),
      ]),
    );
  }
}