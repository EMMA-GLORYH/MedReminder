// lib/screens/home/caretaker/patients_tab.dart

import 'package:flutter/material.dart';
import 'package:mar/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mar/models/care_relationship.dart';
import 'package:mar/services/care_relationship_service.dart';
import 'package:mar/theme/app_colors.dart';
import 'package:mar/theme/app_text_styles.dart';
import 'package:mar/widgets/empty_state.dart';

import '../../home/patients/history_tab.dart';
// import '../../home/caretaker/alerts_tab.dart';
import '../../home/caretaker/patient_medications_screen.dart';

const _kPageSize = 12;

class PatientsTab extends StatefulWidget {
  const PatientsTab({super.key});

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  List<CareRelationship> _patients =
  <CareRelationship>[];

  bool _isFirstLoad = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  int _offset = 0;
  int? _totalCount;
  String? _error;

  final ScrollController _scrollController =
  ScrollController();

  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);
    _refreshAll();

    _subscription =
        CareRelationshipService.instance
            .subscribeToMyInvites(
          _refreshAll,
        );
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;

    setState(() {
      _error = null;

      if (_patients.isEmpty) {
        _isFirstLoad = true;
      }
    });

    try {
      final results = await Future.wait<Object>([
        CareRelationshipService.instance
            .getPatientsIMonitorPage(
          offset: 0,
          limit: _kPageSize,
        ),
        CareRelationshipService.instance
            .getActivePatientCount(),
      ]);

      final firstPage =
      results[0] as List<CareRelationship>;

      final total = results[1] as int;

      if (!mounted) return;

      setState(() {
        _patients = firstPage;
        _offset = firstPage.length;
        _hasMore = firstPage.length == _kPageSize;
        _totalCount = total;
        _isFirstLoad = false;
      });
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to load caretaker patients: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _isFirstLoad = false;

        if (_patients.isEmpty) {
          _error = error
              .toString()
              .replaceAll('Exception: ', '');
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final next =
      await CareRelationshipService.instance
          .getPatientsIMonitorPage(
        offset: _offset,
        limit: _kPageSize,
      );

      if (!mounted) return;

      setState(() {
        _patients = <CareRelationship>[
          ..._patients,
          ...next,
        ];

        _offset += next.length;
        _hasMore = next.length == _kPageSize;
        _isLoadingMore = false;
      });
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to load more patients: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    const threshold = 300.0;
    final position = _scrollController.position;

    if (position.pixels >=
        position.maxScrollExtent - threshold) {
      _loadMore();
    }
  }

  void _showPermissionDenied({
    required String action,
    required CareRelationship patient,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
          content: Text(
            'You are not permitted to $action for '
                '${patient.displayName}.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }

  void _openPatientLogs(
      BuildContext context,
      CareRelationship patient,
      ) {
    if (!patient.canViewLogs) {
      _showPermissionDenied(
        action: 'view logs',
        patient: patient,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HistoryTab(
          patientId: patient.patientId,
          patientName: patient.displayName,
        ),
      ),
    );
  }

  void _openPatientMedications(
      BuildContext context,
      CareRelationship patient,
      ) {
    if (!patient.canViewMedications) {
      _showPermissionDenied(
        action: 'view medications',
        patient: patient,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PatientMedicationsScreen(
          patientId: patient.patientId,
          patientName: patient.displayName,
        ),
      ),
    );
  }

  // void _openPatientAlerts(
  //     BuildContext context,
  //     CareRelationship patient,
  //     ) {
  //   if (!patient.canReceiveAlerts) {
  //     _showPermissionDenied(
  //       action: 'view SOS alerts',
  //       patient: patient,
  //     );
  //     return;
  //   }
  //
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute<void>(
  //       builder: (_) => AlertsTab(
  //         patientId: patient.patientId,
  //         patientName: patient.displayName,
  //       ),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    if (_isFirstLoad) {
      return const _PatientsSkeleton();
    }

    if (_error != null && _patients.isEmpty) {
      return _ErrorState(
        message: _error!,
        onRetry: _refreshAll,
      );
    }

    if (_patients.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshAll,
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 60),
            EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No patients linked yet',
              message:
              'Ask a patient to invite you from their app.\n'
                  'Once linked, they will appear here.',
            ),
          ],
        ),
      );
    }

    final itemCount =
        _patients.length + (_hasMore ? 1 : 0);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshAll,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24,
        ),
        itemCount: itemCount,
        separatorBuilder: (_, __) =>
        const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                _PatientsHeader(
                  total:
                  _totalCount ?? _patients.length,
                ),
                const SizedBox(height: 12),
                _PatientCard(
                  patient: _patients[index],
                  onViewLogs: _openPatientLogs,
                  onViewMedications: _openPatientMedications,
                ),
              ],
            );
          }

          if (index >= _patients.length) {
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
                  ),
                )
                    : const SizedBox(height: 22),
              ),
            );
          }

          final patient = _patients[index];

          return _PatientCard(
            patient: patient,
            onViewLogs: _openPatientLogs,
            onViewMedications: _openPatientMedications,
          );
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

  const _PatientsHeader({
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Your Patients',
          style: AppTextStyles.h2,
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$total',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
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

  final void Function(
      BuildContext context,
      CareRelationship patient,
      ) onViewLogs;

  final void Function(
      BuildContext context,
      CareRelationship patient,
      ) onViewMedications;


  const _PatientCard({
    required this.patient,
    required this.onViewLogs,
    required this.onViewMedications,
  });

  String _formatDate(DateTime date) {
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

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final patientName = patient.displayName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.04,
            ),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
                radius: 24,
                backgroundColor:
                AppColors.primary.withValues(
                  alpha: 0.15,
                ),
                backgroundImage:
                patient.displayAvatar.isNotEmpty
                    ? NetworkImage(
                  patient.displayAvatar,
                )
                    : null,
                child: patient.displayAvatar.isEmpty
                    ? Text(
                  patientName.isNotEmpty
                      ? patientName[0]
                      .toUpperCase()
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
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (patient.displayPhone.isNotEmpty)
                      Text(
                        patient.displayPhone,
                        style: AppTextStyles.bodySmall
                            .copyWith(
                          color:
                          AppColors.textSecondary,
                        ),
                      ),
                    if (patient.relationship != null)
                      Text(
                        patient.relationshipLabel,
                        style: AppTextStyles.labelSmall
                            .copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ),
              _ActiveBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            color: AppColors.border,
            height: 1,
          ),
          const SizedBox(height: 12),

          Text(
            'Patient access',
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),

          _PatientActionButton(
            label: 'View Logs',
            subtitle: 'Dose history for $patientName',
            icon: Icons.history_rounded,
            enabled: patient.canViewLogs,
            onPressed: () => onViewLogs(
              context,
              patient,
            ),
          ),
          const SizedBox(height: 8),

          _PatientActionButton(
            label: 'View Medications',
            subtitle: 'Medication list for $patientName',
            icon: Icons.medication_rounded,
            enabled: patient.canViewMedications,
            onPressed: () => onViewMedications(
              context,
              patient,
            ),
          ),

          const SizedBox(height: 12),

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
                  'Linked since ${_formatDate(
                    patient.acceptedAt ??
                        patient.invitedAt,
                  )}',
                  style: AppTextStyles.bodySmall
                      .copyWith(
                    color:
                    AppColors.textSecondary,
                  ),
                ),
              ),
              const Icon(
                Icons.notifications_active_rounded,
                size: 12,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                '${patient.alertThresholdMins}m',
                style: AppTextStyles.bodySmall
                    .copyWith(
                  color:
                  AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(
          alpha: 0.15,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.greenAccent.withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: const Text(
        'Active',
        style: TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _PatientActionButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color? color;
  final bool enabled;
  final VoidCallback onPressed;

  const _PatientActionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final actionColor =
        color ?? AppColors.secondary;

    return Material(
      color: enabled
          ? actionColor.withValues(alpha: 0.08)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? actionColor.withValues(
                alpha: 0.28,
              )
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: enabled
                      ? actionColor.withValues(
                    alpha: 0.14,
                  )
                      : AppColors.textSecondary
                      .withValues(alpha: 0.10),
                  borderRadius:
                  BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: enabled
                      ? actionColor
                      : AppColors.textSecondary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppLocalizations.of(context) !=
                          null
                          ? AppTextStyles.titleSmall
                          .copyWith(
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors
                            .textSecondary,
                        fontWeight:
                        FontWeight.w700,
                      )
                          : AppTextStyles.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? subtitle
                          : 'Permission not granted',
                      style: AppTextStyles.bodySmall
                          .copyWith(
                        color:
                        AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                enabled
                    ? Icons.chevron_right_rounded
                    : Icons.lock_outline_rounded,
                color: enabled
                    ? actionColor
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
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
      physics:
      const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
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
              'Could not load patients',
              style: AppTextStyles.titleMedium,
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