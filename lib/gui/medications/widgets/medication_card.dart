// lib/screens/gui/medications/widgets/medication_card.dart

import 'package:flutter/material.dart';
import '../../../models/medication.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

/// Same public API as before — medication, hasSchedule, onTap, onScheduleTap
/// — so it drops in without any call-site changes. The whole card now
/// carries the medication's set pill_color as a visual accent (left bar +
/// subtle background tint), not just the fallback icon swatch.
class MedicationCard extends StatelessWidget {
  final Medication medication;
  final bool hasSchedule;
  final VoidCallback onTap;
  final VoidCallback onScheduleTap;

  const MedicationCard({
    super.key,
    required this.medication,
    required this.hasSchedule,
    required this.onTap,
    required this.onScheduleTap,
  });

  bool get _hasImage =>
      medication.pillImageUrl != null && medication.pillImageUrl!.isNotEmpty;

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
        return AppColors.secondary;
    }
  }

  /// The color actually used for the card's accent bar / tint / border.
  /// A literal white accent would be invisible against the card surface,
  /// so "white" pills fall back to a neutral outline tone instead of
  /// disappearing — every other color is used as-is.
  Color get _cardAccentColor {
    if (medication.pillColor?.toLowerCase() == 'white') {
      return AppColors.textSecondary;
    }
    return _pillColor;
  }

  IconData get _fallbackIcon {
    switch (medication.dosageUnit.toLowerCase()) {
      case 'ml':
        return Icons.medication_liquid_rounded;
      case 'units':
        return Icons.vaccines_rounded;
      default:
        return Icons.medication_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _cardAccentColor;

    // A refill warning always takes priority over the color-coded border,
    // since it's actionable and time-sensitive; the tint and left bar
    // still reflect the pill color underneath either way.
    final borderColor = medication.needsRefill
        ? AppColors.warning.withValues(alpha: 0.5)
        : accent.withValues(alpha: 0.35);

    // Subtle tint blended onto the surface color rather than a flat
    // saturated fill, so text stays legible regardless of which color
    // is set (including bright yellows/greens).
    final backgroundColor =
    Color.alphaBlend(accent.withValues(alpha: 0.06), AppColors.surface);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Color-coded accent bar — the at-a-glance pill color ──
                Container(width: 5, color: accent),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Image / fallback visual ──
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _hasImage
                                  ? Image.network(
                                medication.pillImageUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _FallbackVisual(
                                  color: _pillColor,
                                  icon: _fallbackIcon,
                                ),
                              )
                                  : _FallbackVisual(color: _pillColor, icon: _fallbackIcon),
                            ),

                            const SizedBox(width: 14),

                            // ── Name, dosage, type badge ──
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    medication.displayName,
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
                                      const SizedBox(width: 8),
                                      _TypeBadge(isScheduled: medication.isScheduled),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // ── Refill warning ──
                            if (medication.needsRefill)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.error_rounded,
                                    color: AppColors.warning, size: 20),
                              ),
                          ],
                        ),

                        // ── Quantity / pill shape+color row ──
                        if (medication.currentQuantity != null ||
                            medication.pillShape != null ||
                            medication.pillColor != null) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (medication.currentQuantity != null)
                                _InfoChip(
                                  icon: Icons.inventory_2_outlined,
                                  label: '${medication.currentQuantity} left',
                                  warn: medication.needsRefill,
                                ),
                              if (medication.pillShape != null)
                                _InfoChip(
                                  icon: Icons.circle_outlined,
                                  label: _capitalize(medication.pillShape!),
                                ),
                              if (medication.pillColor != null)
                                _InfoChip(
                                  icon: Icons.palette_outlined,
                                  label: _capitalize(medication.pillColor!),
                                  swatchColor: _pillColor,
                                ),
                            ],
                          ),
                        ],

                        // ── Notes preview ──
                        if (medication.notes != null &&
                            medication.notes!.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            medication.notes!.trim(),
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        const SizedBox(height: 10),

                        // ── Schedule status / action ──
                        GestureDetector(
                          onTap: onScheduleTap,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Icon(
                                hasSchedule
                                    ? Icons.event_available_rounded
                                    : Icons.event_busy_rounded,
                                size: 15,
                                color: hasSchedule
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hasSchedule ? 'Scheduled' : 'No schedule — tap to add',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: hasSchedule
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.chevron_right_rounded,
                                  size: 18,
                                  color:
                                  AppColors.textSecondary.withValues(alpha: 0.6)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _FallbackVisual extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _FallbackVisual({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      color: color.withValues(alpha: 0.85),
      child: Icon(
        icon,
        // Keep the icon visible against a white swatch too.
        color: color == Colors.white ? AppColors.secondary : Colors.white,
        size: 26,
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final bool isScheduled;
  const _TypeBadge({required this.isScheduled});

  @override
  Widget build(BuildContext context) {
    final color = isScheduled ? AppColors.primary : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isScheduled ? 'Scheduled' : 'As needed',
        style: AppTextStyles.labelSmall.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool warn;
  final Color? swatchColor;
  const _InfoChip({
    required this.icon,
    required this.label,
    this.warn = false,
    this.swatchColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = warn ? AppColors.warning : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatchColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: swatchColor,
                shape: BoxShape.circle,
                border: swatchColor == Colors.white
                    ? Border.all(color: AppColors.border)
                    : null,
              ),
            ),
            const SizedBox(width: 5),
          ] else
            Icon(icon, size: 12, color: color),
          if (swatchColor == null) const SizedBox(width: 4),
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}