// lib/screens/gui/caretakers/pending_invites_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/care_relationship.dart';
import '../../services/care_relationship_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/snackbar/app_snackbar.dart';

const int _kPageSize = 10;

class PendingInvitesScreen extends StatefulWidget {
  const PendingInvitesScreen({super.key});

  @override
  State<PendingInvitesScreen> createState() =>
      _PendingInvitesScreenState();
}

class _PendingInvitesScreenState
    extends State<PendingInvitesScreen> {
  List<CareRelationship> _invites = [];

  bool _isFirstLoad = true;
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _refreshQueued = false;

  int _offset = 0;
  int? _totalCount;

  String? _error;

  final ScrollController _scrollController =
  ScrollController();

  RealtimeChannel? _subscription;
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);

    _refreshAll();
    _subscribeToChanges();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _subscription?.unsubscribe();
    _scrollController.dispose();

    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // REALTIME
  // ══════════════════════════════════════════════════════════════

  void _subscribeToChanges() {
    _subscription =
        CareRelationshipService.instance
            .subscribeToMyInvites(() {
          if (!mounted) return;

          // Several database events can arrive together. Debouncing prevents
          // repeated overlapping refreshes.
          _realtimeDebounce?.cancel();

          _realtimeDebounce = Timer(
            const Duration(milliseconds: 350),
                () {
              if (mounted) {
                _refreshAll(silent: true);
              }
            },
          );
        });
  }

  // ══════════════════════════════════════════════════════════════
  // LOAD FIRST PAGE
  // ══════════════════════════════════════════════════════════════

  Future<void> _refreshAll({
    bool silent = false,
  }) async {
    if (_isRefreshing) {
      _refreshQueued = true;
      return;
    }

    _isRefreshing = true;

    if (mounted && !silent) {
      setState(() {
        _error = null;

        if (_invites.isEmpty) {
          _isFirstLoad = true;
        }
      });
    }

    try {
      final results = await Future.wait([
        CareRelationshipService.instance
            .getPendingInvitesPage(
          offset: 0,
          limit: _kPageSize,
        ),
        CareRelationshipService.instance
            .getPendingInviteCount(),
      ]);

      final firstPage =
      results[0] as List<CareRelationship>;

      final total = results[1] as int;

      if (!mounted) return;

      setState(() {
        _invites = firstPage;
        _offset = firstPage.length;
        _totalCount = total;

        // More pages exist only when the number loaded is less than
        // the exact database count.
        _hasMore = _offset < total;

        _isFirstLoad = false;
        _error = null;
      });
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to load pending invites: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _isFirstLoad = false;

        if (_invites.isEmpty) {
          _error = error
              .toString()
              .replaceAll('Exception: ', '');
        }
      });
    } finally {
      _isRefreshing = false;

      if (_refreshQueued && mounted) {
        _refreshQueued = false;

        unawaited(
          _refreshAll(silent: true),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LOAD NEXT PAGE
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadMore() async {
    if (_isLoadingMore ||
        _isRefreshing ||
        !_hasMore) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final next =
      await CareRelationshipService.instance
          .getPendingInvitesPage(
        offset: _offset,
        limit: _kPageSize,
      );

      if (!mounted) return;

      // Protect against duplicate rows if a Realtime refresh and
      // pagination request overlap.
      final currentIds =
      _invites.map((invite) => invite.id).toSet();

      final uniqueNext = next
          .where(
            (invite) => !currentIds.contains(invite.id),
      )
          .toList();

      setState(() {
        _invites = [
          ..._invites,
          ...uniqueNext,
        ];

        _offset += next.length;

        final total = _totalCount;

        _hasMore = total != null
            ? _offset < total
            : next.length == _kPageSize;

        _isLoadingMore = false;
      });
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to load more invites: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    const threshold = 300.0;
    final position =
        _scrollController.position;

    if (position.pixels >=
        position.maxScrollExtent - threshold) {
      _loadMore();
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ACCEPT
  // ══════════════════════════════════════════════════════════════

  Future<void> _accept(
      CareRelationship invite,
      ) async {
    try {
      final accepted =
      await CareRelationshipService.instance
          .acceptInvite(invite.id);

      if (!mounted) return;

      // Remove immediately for responsive UI. Realtime will later
      // synchronize the final list.
      _removeInviteLocally(invite.id);

      await _showAcceptedDialog(
        invite.displayName,
      );

      if (!mounted) return;

      await _refreshAll(silent: true);

      debugPrint(
        '✅ Relationship ${accepted.id} is active and SOS-ready',
      );
    } catch (error, stack) {
      debugPrint(
        '❌ Could not accept invite: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      AppSnackbar.error(
        context,
        error.toString().replaceAll(
          'Exception: ',
          '',
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // DECLINE
  // ══════════════════════════════════════════════════════════════

  Future<void> _decline(
      CareRelationship invite,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: AppColors.surface,
          title: const Text('Decline Invite?'),
          content: Text(
            'Decline the invite from '
                '${invite.displayName}?\n\n'
                'They can send you another invite later.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Decline'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await CareRelationshipService.instance
          .declineInvite(invite.id);

      if (!mounted) return;

      _removeInviteLocally(invite.id);

      AppSnackbar.success(
        context,
        'Invite from ${invite.displayName} declined',
      );

      await _refreshAll(silent: true);
    } catch (error, stack) {
      debugPrint(
        '❌ Could not decline invite: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      AppSnackbar.error(
        context,
        error.toString().replaceAll(
          'Exception: ',
          '',
        ),
      );
    }
  }

  void _removeInviteLocally(String inviteId) {
    final currentTotal =
        _totalCount ?? _invites.length;

    setState(() {
      _invites.removeWhere(
            (invite) => invite.id == inviteId,
      );

      _totalCount = currentTotal > 0
          ? currentTotal - 1
          : 0;

      // A subsequent silent refresh resets this to the exact
      // database pagination offset.
      _offset = _invites.length;

      _hasMore =
          _offset < (_totalCount ?? 0);
    });
  }

  // ══════════════════════════════════════════════════════════════
  // ACCEPTED DIALOG
  // ══════════════════════════════════════════════════════════════

  Future<void> _showAcceptedDialog(
      String patientName,
      ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
              BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primary
                    .withValues(alpha: 0.40),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary
                      .withValues(alpha: 0.15),
                  blurRadius: 32,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary
                        .withValues(alpha: 0.10),
                    border: Border.all(
                      color: AppColors.primary
                          .withValues(alpha: 0.30),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.handshake_rounded,
                    color: AppColors.primary,
                    size: 38,
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  "You're now a Caretaker!",
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style:
                    AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    children: [
                      const TextSpan(
                        text: 'You are now monitoring ',
                      ),
                      TextSpan(
                        text: patientName,
                        style: AppTextStyles.bodyMedium
                            .copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(
                        text:
                        ".\n\nYou'll receive SOS alerts "
                            'and medication notifications '
                            'according to the permissions granted.',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary
                        .withValues(alpha: 0.08),
                    borderRadius:
                    BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary
                          .withValues(alpha: 0.20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sos_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This connection is now active '
                              'and can receive SOS alerts.',
                          style: AppTextStyles.bodySmall
                              .copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: const Text(
                      'Great!',
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
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: AppColors.primary,
        ),
        foregroundColor: AppColors.primary,
        title: Row(
          children: [
            Text(
              'Pending Invites',
              style: AppTextStyles.titleMedium,
            ),
            if ((_totalCount ?? 0) > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: Text(
                  '${_totalCount ?? _invites.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_error != null && _invites.isEmpty) {
      return _ErrorView(
        message: _error!,
        onRetry: () => _refreshAll(),
      );
    }

    if (_invites.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _refreshAll(
          silent: true,
        ),
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            _EmptyInvites(),
          ],
        ),
      );
    }

    final itemCount =
        _invites.length + (_hasMore ? 1 : 0);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _refreshAll(
        silent: true,
      ),
      child: ListView.separated(
        controller: _scrollController,
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        separatorBuilder: (_, __) {
          return const SizedBox(height: 12);
        },
        itemBuilder: (_, index) {
          if (index >= _invites.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 20,
              ),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                )
                    : const SizedBox(height: 22),
              ),
            );
          }

          final invite = _invites[index];

          return _InviteCard(
            key: ValueKey(invite.id),
            invite: invite,
            onAccept: () => _accept(invite),
            onDecline: () => _decline(invite),
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
    super.key,
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_InviteCard> createState() =>
      _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  bool _isAccepting = false;
  bool _isDeclining = false;

  Future<void> _handleAccept() async {
    if (_isAccepting || _isDeclining) return;

    setState(() => _isAccepting = true);

    try {
      await widget.onAccept();
    } finally {
      if (mounted) {
        setState(() => _isAccepting = false);
      }
    }
  }

  Future<void> _handleDecline() async {
    if (_isAccepting || _isDeclining) return;

    setState(() => _isDeclining = true);

    try {
      await widget.onDecline();
    } finally {
      if (mounted) {
        setState(() => _isDeclining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final busy = _isAccepting || _isDeclining;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary
              .withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary
                    .withValues(alpha: 0.12),
                backgroundImage:
                invite.displayAvatar.isNotEmpty
                    ? NetworkImage(
                  invite.displayAvatar,
                )
                    : null,
                child: invite.displayAvatar.isEmpty
                    ? Text(
                  invite.displayName.isNotEmpty
                      ? invite.displayName[0]
                      .toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                )
                    : null,
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.displayName,
                      style:
                      AppTextStyles.titleMedium,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                    if (invite
                        .displayPhone.isNotEmpty)
                      Text(
                        invite.displayPhone,
                        style: AppTextStyles.bodySmall
                            .copyWith(
                          color:
                          AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),

              Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning
                      .withValues(alpha: 0.15),
                  borderRadius:
                  BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.warning
                        .withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  'Pending',
                  style:
                  AppTextStyles.labelSmall.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius:
              BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _DetailRow(
                  icon:
                  Icons.medical_information_rounded,
                  label: 'Relationship',
                  value: invite.relationshipLabel,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  icon: Icons
                      .notifications_active_rounded,
                  label: 'Alert threshold',
                  value:
                  '${invite.alertThresholdMins} minutes late',
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  icon:
                  Icons.calendar_today_rounded,
                  label: 'Invited',
                  value:
                  _formatDate(invite.invitedAt),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (invite.canViewLogs)
                const _PermBadge(
                  label: 'View logs',
                  icon: Icons.history_rounded,
                ),
              if (invite.canViewMedications)
                const _PermBadge(
                  label: 'View meds',
                  icon: Icons.medication_rounded,
                ),
              if (invite.canReceiveAlerts)
                const _PermBadge(
                  label: 'SOS alerts',
                  icon: Icons.sos_rounded,
                ),
              if (invite.canEditMedications)
                const _PermBadge(
                  label: 'Edit meds',
                  icon: Icons.edit_rounded,
                  color: AppColors.warning,
                ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                  busy ? null : _handleDecline,
                  icon: _isDeclining
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.error,
                    ),
                  )
                      : const Icon(
                    Icons.close_rounded,
                    size: 18,
                  ),
                  label: const Text('Decline'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: AppColors.error
                          .withValues(alpha: 0.50),
                    ),
                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed:
                  busy ? null : _handleAccept,
                  icon: _isAccepting
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(
                    Icons.check_rounded,
                    size: 20,
                  ),
                  label: Text(
                    _isAccepting
                        ? 'Accepting…'
                        : 'Accept',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
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

    final hour =
    local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute =
    local.minute.toString().padLeft(2, '0');
    final period =
    local.hour < 12 ? 'AM' : 'PM';

    return '${months[local.month - 1]} '
        '${local.day}, ${local.year}  '
        '$hour:$minute $period';
  }
}

// ══════════════════════════════════════════════════════════════
// DETAIL ROW
// ══════════════════════════════════════════════════════════════

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: AppTextStyles.labelSmall,
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PERMISSION BADGE
// ══════════════════════════════════════════════════════════════

class _PermBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _PermBadge({
    required this.label,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = color ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color:
        badgeColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
          badgeColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: badgeColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style:
            AppTextStyles.labelSmall.copyWith(
              color: badgeColor,
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

class _EmptyInvites extends StatelessWidget {
  const _EmptyInvites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary
                    .withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_rounded,
                size: 52,
                color: AppColors.primary
                    .withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No pending invites',
              style: AppTextStyles.h2,
            ),
            const SizedBox(height: 8),
            Text(
              'When a patient invites you as their\n'
                  'caretaker it will appear here.',
              style:
              AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
              Icons.error_outline_rounded,
              size: 56,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load invites',
              style: AppTextStyles.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style:
              AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
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