// lib/screens/home/caretaker/patients_tab.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/care_relationship.dart';
import '../../services/care_relationship_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/empty_state.dart';

// Patients fetched per indexed page. Small enough to render a clean first
// screen; large enough that most caretakers never need to scroll.
const _kPageSize = 12;

class PatientsTab extends StatefulWidget {
  const PatientsTab({super.key});

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  List<CareRelationship> _patients = [];

  bool _isFirstLoad   = true;
  bool _isLoadingMore = false;
  bool _hasMore       = true;
  int  _offset        = 0;
  int? _totalCount;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshAll();
    // Live updates — e.g. a new patient accepts an invite while this tab
    // is open, or an existing relationship is revoked. Any change resets
    // pagination back to page 0, since we can't know where in the index
    // the changed row now falls.
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
      if (_patients.isEmpty) _isFirstLoad = true;
    });

    try {
      final results = await Future.wait([
        CareRelationshipService.instance
            .getPatientsIMonitorPage(offset: 0, limit: _kPageSize),
        CareRelationshipService.instance.getActivePatientCount(),
      ]);

      final firstPage = results[0] as List<CareRelationship>;
      final total     = results[1] as int;

      if (!mounted) return;
      setState(() {
        _patients    = firstPage;
        _offset      = firstPage.length;
        _hasMore     = firstPage.length == _kPageSize;
        _totalCount  = total;
        _isFirstLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFirstLoad = false;
        if (_patients.isEmpty) {
          _error = e.toString().replaceAll('Exception: ', '');
        }
      });
    }
  }

  // ── Next index page — appends, never replaces ─────────────────────
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final next = await CareRelationshipService.instance
          .getPatientsIMonitorPage(offset: _offset, limit: _kPageSize);

      if (!mounted) return;
      setState(() {
        _patients      = [..._patients, ...next];
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

  @override
  Widget build(BuildContext context) {
    if (_isFirstLoad) return const _PatientsSkeleton();

    if (_error != null && _patients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Could not load patients',
                  style: AppTextStyles.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(_error!,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_patients.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 60),
            EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No patients linked yet',
              message: 'Ask a patient to invite you from their app.\n'
                  'Once linked, they will appear here.',
            ),
          ],
        ),
      );
    }

    final itemCount = _patients.length + (_hasMore ? 1 : 0);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshAll,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PatientsHeader(total: _totalCount ?? _patients.length),
                const SizedBox(height: 12),
                _PatientCard(patient: _patients[0]),
              ],
            );
          }

          if (index >= _patients.length) {
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

          return _PatientCard(patient: _patients[index]);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════════════
class _PatientsHeader extends StatelessWidget {
  final int total;
  const _PatientsHeader({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Your Patients', style: AppTextStyles.h2),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$total',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PATIENT CARD
// ══════════════════════════════════════════════════════════════
class _PatientCard extends StatelessWidget {
  final CareRelationship patient;
  const _PatientCard({required this.patient});

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: patient.displayAvatar.isNotEmpty
                    ? NetworkImage(patient.displayAvatar)
                    : null,
                child: patient.displayAvatar.isEmpty
                    ? Text(
                  patient.displayName.isNotEmpty
                      ? patient.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.displayName,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (patient.displayPhone.isNotEmpty)
                      Text(
                        patient.displayPhone,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    if (patient.relationship != null)
                      Text(
                        patient.relationshipLabel,
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),

          // ── Permissions granted to this caretaker ──
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (patient.canViewLogs)
                _PermChip(label: 'View Logs', icon: Icons.history_rounded),
              if (patient.canViewMedications)
                _PermChip(label: 'View Meds', icon: Icons.medication_rounded),
              if (patient.canReceiveAlerts)
                _PermChip(label: 'SOS Alerts', icon: Icons.sos_rounded),
              if (patient.canEditMedications)
                _PermChip(
                  label: 'Edit Meds',
                  icon: Icons.edit_rounded,
                  color: AppColors.warning,
                ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(
                'Linked since ${_formatDate(patient.acceptedAt ?? patient.invitedAt)}',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 10),
              Icon(Icons.notifications_active_rounded, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(
                'Alerts at ${patient.alertThresholdMins}m late',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ],
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
  const _PermChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: c)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SKELETON
// ══════════════════════════════════════════════════════════════
class _PatientsSkeleton extends StatelessWidget {
  const _PatientsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ],
    );
  }
}