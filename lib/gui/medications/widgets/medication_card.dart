// lib/screens/gui/medications/widgets/medication_card.dart

import 'package:flutter/material.dart';
import '../../../models/medication.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

class MedicationCard extends StatelessWidget {
  final Medication medication;
  final bool hasSchedule;
  final VoidCallback? onTap;
  final VoidCallback? onScheduleTap;

  const MedicationCard({
    super.key,
    required this.medication,
    this.hasSchedule = false,
    this.onTap,
    this.onScheduleTap,
  });

  Color get _pillColor {
    switch (medication.pillColor?.toLowerCase()) {
      case 'white':  return Colors.white;
      case 'blue':   return const Color(0xFF4A90E2);
      case 'red':    return const Color(0xFFE53935);
      case 'yellow': return const Color(0xFFFFC107);
      case 'green':  return AppColors.primary;
      case 'orange': return const Color(0xFFFF9800);
      case 'pink':   return const Color(0xFFEC407A);
      case 'purple': return const Color(0xFF9C27B0);
      case 'brown':  return const Color(0xFF795548);
      default:       return AppColors.surfaceVariant;
    }
  }

  bool get _isLightPill =>
      _pillColor == Colors.white ||
          _pillColor == const Color(0xFFFFC107) ||
          _pillColor == AppColors.surfaceVariant;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              // Pill color indicator
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _pillColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isLightPill ? AppColors.border : Colors.transparent,
                  ),
                ),
                child: Icon(
                  Icons.medication_rounded,
                  size: 20,
                  color: _isLightPill ? AppColors.secondary : Colors.white,
                ),
              ),

              const SizedBox(width: 12),

              // Name + dosage + generic
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.brandName ?? medication.genericName,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          medication.displayDosage,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (medication.brandName != null) ...[
                          Text(
                            '  •  ',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary.withValues(alpha: 0.5),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              medication.genericName,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Right side: status + action
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Status badge
                  _StatusPill(
                    label: medication.isScheduled ? 'Scheduled' : 'PRN',
                    color: medication.isScheduled ? AppColors.info : AppColors.warning,
                  ),

                  // Quantity or schedule warning
                  if (medication.isScheduled && !hasSchedule) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onScheduleTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Set time',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (medication.currentQuantity != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${medication.currentQuantity} left',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: medication.needsRefill
                            ? AppColors.error
                            : AppColors.textSecondary,
                        fontWeight: medication.needsRefill
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(width: 4),

              // Chevron
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}