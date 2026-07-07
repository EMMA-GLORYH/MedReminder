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
      case 'white':
        return Colors.white;
      case 'blue':
        return const Color(0xFF4A90E2);
      case 'red':
        return const Color(0xFFE53935);
      case 'yellow':
        return const Color(0xFFFFC107);
      case 'green':
        return AppColors.primary;
      case 'orange':
        return const Color(0xFFFF9800);
      case 'pink':
        return const Color(0xFFEC407A);
      case 'purple':
        return const Color(0xFF9C27B0);
      case 'brown':
        return const Color(0xFF795548);
      default:
        return AppColors.surfaceVariant;
    }
  }

  bool get _isLightPill =>
      _pillColor == Colors.white ||
          _pillColor == const Color(0xFFFFC107) ||
          _pillColor == AppColors.surfaceVariant;

  bool get _hasImage =>
      medication.pillImageUrl != null && medication.pillImageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _MedicationThumbnail(
                imageUrl: medication.pillImageUrl,
                fallbackColor: _pillColor,
                isLight: _isLightPill,
                medicationType: medication.medicationType,
              ),

              const SizedBox(width: 12),

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

                    const SizedBox(height: 3),

                    Row(
                      children: [
                        Text(
                          medication.displayDosage,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (medication.brandName != null &&
                            medication.brandName!.isNotEmpty) ...[
                          Text(
                            '  •  ',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.5,
                              ),
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

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        _StatusPill(
                          label: medication.isScheduled ? 'Scheduled' : 'PRN',
                          color: medication.isScheduled
                              ? AppColors.info
                              : AppColors.warning,
                        ),

                        if (medication.currentQuantity != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${medication.currentQuantity} left',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: medication.needsRefill
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                              fontWeight: medication.needsRefill
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              if (medication.isScheduled && !hasSchedule)
                InkWell(
                  onTap: onScheduleTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: AppColors.warning,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicationThumbnail extends StatelessWidget {
  final String? imageUrl;
  final Color fallbackColor;
  final bool isLight;
  final String medicationType;

  const _MedicationThumbnail({
    required this.imageUrl,
    required this.fallbackColor,
    required this.isLight,
    required this.medicationType,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;

          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) {
          return _FallbackThumbnail(
            color: fallbackColor,
            isLight: isLight,
            medicationType: medicationType,
          );
        },
      )
          : _FallbackThumbnail(
        color: fallbackColor,
        isLight: isLight,
        medicationType: medicationType,
      ),
    );
  }
}

class _FallbackThumbnail extends StatelessWidget {
  final Color color;
  final bool isLight;
  final String medicationType;

  const _FallbackThumbnail({
    required this.color,
    required this.isLight,
    required this.medicationType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: Icon(
        medicationType == 'prn'
            ? Icons.medical_services_rounded
            : Icons.medication_rounded,
        size: 24,
        color: isLight ? AppColors.secondary : Colors.white,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.color,
  });

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
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}