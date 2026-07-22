// lib/home/caretaker/widgets/activity_detail_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/patient_activity.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

class ActivityDetailBottomSheet extends StatelessWidget {
  final PatientActivity activity;

  const ActivityDetailBottomSheet({
    super.key,
    required this.activity,
  });

  Color get _statusColor {
    if (activity.isTaken) return Colors.green;
    if (activity.isMissed) return AppColors.error;
    if (activity.isPending) return AppColors.warning;
    return AppColors.textSecondary;
  }

  IconData get _statusIcon {
    if (activity.isTaken) return Icons.check_circle_rounded;
    if (activity.isMissed) return Icons.cancel_rounded;
    if (activity.isPending) return Icons.pending_rounded;
    return Icons.remove_circle_rounded;
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, y \'at\' h:mm a').format(dateTime);
  }

  String _formatDeviation(int minutes) {
    if (minutes == 0) return 'On time';
    final absMinutes = minutes.abs();
    final direction = minutes > 0 ? 'late' : 'early';

    if (absMinutes < 60) {
      return '$absMinutes min $direction';
    }

    final hours = absMinutes ~/ 60;
    final mins = absMinutes % 60;

    if (mins == 0) {
      return '$hours hr $direction';
    }

    return '$hours hr $mins min $direction';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Content
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(20),
                children: [
                  // Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        backgroundImage: activity.patientAvatar != null
                            ? NetworkImage(activity.patientAvatar!)
                            : null,
                        child: activity.patientAvatar == null
                            ? Text(
                          activity.patientInitial,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
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
                              activity.patientName,
                              style: AppTextStyles.h2,
                            ),
                            if (activity.relationship != null)
                              Text(
                                activity.relationship!,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIcon,
                              size: 16,
                              color: _statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              activity.statusLabel,
                              style: AppTextStyles.labelMedium.copyWith(
                                color: _statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 24),

                  // Medication Details
                  _SectionTitle(title: 'Medication'),
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: Icons.medication_rounded,
                    label: 'Medicine',
                    value: activity.displayMedicationName,
                  ),
                  _DetailRow(
                    icon: Icons.science_rounded,
                    label: 'Dosage',
                    value: activity.displayDosage,
                  ),
                  if (activity.pillColor != null)
                    _DetailRow(
                      icon: Icons.palette_rounded,
                      label: 'Pill Color',
                      value: activity.pillColor!,
                    ),

                  const SizedBox(height: 24),

                  // Timing Details
                  _SectionTitle(title: 'Timing'),
                  const SizedBox(height: 12),
                  _DetailRow(
                    icon: Icons.schedule_rounded,
                    label: 'Scheduled For',
                    value: _formatDateTime(activity.scheduledFor),
                  ),
                  if (activity.loggedAt != null)
                    _DetailRow(
                      icon: Icons.access_time_rounded,
                      label: 'Taken At',
                      value: _formatDateTime(activity.loggedAt!),
                    ),
                  if (activity.deviationMinutes != null)
                    _DetailRow(
                      icon: Icons.timer_rounded,
                      label: 'Deviation',
                      value: _formatDeviation(activity.deviationMinutes!),
                      valueColor: activity.deviationMinutes!.abs() > 30
                          ? AppColors.warning
                          : null,
                    ),

                  if (activity.markedAsMissed) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warning.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_rounded,
                            color: AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Automatically marked as missed after 24 hours',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (activity.notes != null && activity.notes!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(title: 'Notes'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        activity.notes!,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Close Button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.titleMedium.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: valueColor,
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