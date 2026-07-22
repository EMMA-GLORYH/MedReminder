// lib/home/caretaker/widgets/patient_activity_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/patient_activity.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

class PatientActivityCard extends StatelessWidget {
  final PatientActivity activity;
  final VoidCallback onTap;

  const PatientActivityCard({
    super.key,
    required this.activity,
    required this.onTap,
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activityDate = DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
    );

    final formatter = DateFormat.jm();
    final timeStr = formatter.format(dateTime);

    if (activityDate == today) {
      return 'Today at $timeStr';
    } else if (activityDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday at $timeStr';
    } else {
      return '${DateFormat.MMMd().format(dateTime)} at $timeStr';
    }
  }

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
            // Patient Avatar
            CircleAvatar(
              radius: 24,
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
                  fontSize: 18,
                ),
              )
                  : null,
            ),
            const SizedBox(width: 12),

            // Activity Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          activity.patientName,
                          style: AppTextStyles.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIcon,
                              size: 12,
                              color: _statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              activity.statusLabel,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: _statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activity.displayMedicationName,
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.medication_rounded,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        activity.displayDosage,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.schedule_rounded,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _formatTime(activity.scheduledFor),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
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