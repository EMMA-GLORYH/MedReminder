// lib/screens/gui/medications/medication_detail_screen.dart

import 'package:flutter/material.dart';
import '../../models/medication.dart';
import '../../services/medication_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/dialogs/confirm_dialog.dart';
import '../../widgets/snackbar/app_snackbar.dart';
import 'add_schedule_screen.dart';
import 'edit_medication_screen.dart';

class MedicationDetailScreen extends StatefulWidget {
  final Medication medication;

  const MedicationDetailScreen({
    super.key,
    required this.medication,
  });

  @override
  State<MedicationDetailScreen> createState() =>
      _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  late Medication _medication;
  bool _isDeleting = false;
  bool _isToggling = false;
  bool _wasModified = false;

  @override
  void initState() {
    super.initState();
    _medication = widget.medication;
  }

  Future<void> _delete() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Medication?',
      message:
      'This will remove ${_medication.displayName} and ALL its schedules. '
          'This cannot be undone.',
      confirmText: 'Delete',
      type: ConfirmDialogType.danger,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      await MedicationService.instance.deleteMedicationWithSchedules(
        _medication.id,
      );

      if (!mounted) return;

      AppSnackbar.success(context, 'Medication removed');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;

      AppSnackbar.error(context, 'Failed to delete medication');
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _edit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditMedicationScreen(medication: _medication),
      ),
    );

    if (result == true && mounted) {
      final updated = await MedicationService.instance.getMedicationById(
        _medication.id,
      );

      if (updated != null && mounted) {
        setState(() {
          _medication = updated;
          _wasModified = true;
        });
      }
    }
  }

  Future<void> _manageSchedule() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleScreen(
          medicationId: _medication.id,
          medicationName: _medication.displayName,
          onOptimisticDoses: (doses) {
            // Medication detail doesn't show a schedule list,
            // so optimistic doses aren't needed here.
            debugPrint('Optimistic doses: ${doses.length}');
          },
          onSaveCompleted: () {
            if (mounted) {
              setState(() => _wasModified = true);
            }
          },
          onSaveFailed: (error) {
            debugPrint('Save failed: $error');
          },
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => _wasModified = true);
    }
  }

  Future<void> _toggleActive(bool value) async {
    setState(() => _isToggling = true);

    try {
      final updated = await MedicationService.instance.toggleActive(
        _medication.id,
        value,
      );

      if (!mounted) return;

      setState(() {
        _medication = updated;
        _wasModified = true;
        _isToggling = false;
      });

      AppSnackbar.success(
        context,
        value ? 'Medication activated' : 'Medication deactivated',
      );
    } catch (_) {
      if (!mounted) return;

      AppSnackbar.error(context, 'Failed to toggle status');
      setState(() => _isToggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = _medication;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _wasModified);
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _DetailHero(medication: med),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      children: [
                        _ActiveToggleCard(
                          isActive: med.isActive,
                          isLoading: _isToggling,
                          onChanged: _toggleActive,
                        ),

                        const SizedBox(height: 16),

                        if (med.notes != null && med.notes!.isNotEmpty) ...[
                          _DetailSection(
                            icon: Icons.note_alt_rounded,
                            title: 'Notes',
                            child: Text(
                              med.notes!,
                              style: AppTextStyles.bodyMedium,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        _DetailSection(
                          icon: Icons.info_outline_rounded,
                          title: 'Information',
                          child: Column(
                            children: [
                              _DetailRow('Generic name', med.genericName),
                              if (med.brandName != null &&
                                  med.brandName!.isNotEmpty)
                                _DetailRow('Brand name', med.brandName!),
                              _DetailRow('Dosage', med.displayDosage),
                              _DetailRow(
                                'Type',
                                med.isScheduled ? 'Scheduled' : 'As needed',
                              ),
                              if (med.pillColor != null)
                                _DetailRow(
                                  'Color',
                                  _capitalize(med.pillColor!),
                                ),
                              if (med.pillShape != null)
                                _DetailRow(
                                  'Shape',
                                  _capitalize(med.pillShape!),
                                ),
                              _DetailRow(
                                'Image',
                                med.pillImageUrl != null &&
                                    med.pillImageUrl!.isNotEmpty
                                    ? 'Saved'
                                    : 'Not added',
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        _DetailSection(
                          icon: Icons.inventory_2_rounded,
                          title: 'Inventory',
                          child: Column(
                            children: [
                              _DetailRow(
                                'Current quantity',
                                med.currentQuantity != null
                                    ? '${med.currentQuantity} ${med.dosageUnit}'
                                    : 'Not tracked',
                              ),
                              _DetailRow(
                                'Refill alert at',
                                '${med.refillAlertAt} ${med.dosageUnit}',
                              ),
                              if (med.needsRefill)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          size: 18,
                                          color: AppColors.warning,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Running low — time to refill',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                              color: AppColors.warning,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        _DetailSection(
                          icon: Icons.access_time_rounded,
                          title: 'Timeline',
                          child: Column(
                            children: [
                              _DetailRow('Added', _formatDate(med.createdAt)),
                              _DetailRow(
                                'Last updated',
                                _formatDate(med.updatedAt),
                              ),
                              _DetailRow(
                                'Status',
                                med.isActive ? 'Active' : 'Inactive',
                              ),
                            ],
                          ),
                        ),

                        if (med.isScheduled) ...[
                          const SizedBox(height: 16),
                          _ManageScheduleCard(onTap: _manageSchedule),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              _FloatingActions(
                onEdit: _edit,
                onDelete: _delete,
                isDeleting: _isDeleting,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) {
    return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  }

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

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

// ══════════════════════════════════════════════════════════════
// SMALLER HERO WITH FULL BACKGROUND MEDICATION IMAGE
// ══════════════════════════════════════════════════════════════
class _DetailHero extends StatelessWidget {
  final Medication medication;

  const _DetailHero({
    required this.medication,
  });

  bool get _hasImage =>
      medication.pillImageUrl != null && medication.pillImageUrl!.isNotEmpty;

  static const double _heroHeight = 260;   // Reduced from 320

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: SizedBox(
        width: double.infinity,
        height: _heroHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image fills the entire hero
            if (_hasImage)
              Image.network(
                medication.pillImageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;

                  return Container(
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) {
                  return _FallbackHeroBackground(
                    color: _pillColor,
                    icon: _getIconForForm(medication.dosageUnit),
                    isLight: _isLightColor(_pillColor),
                  );
                },
              )
            else
              _FallbackHeroBackground(
                color: _pillColor,
                icon: _getIconForForm(medication.dosageUnit),
                isLight: _isLightColor(_pillColor),
              ),

            // Dark overlay for better text readability when image is present
            if (_hasImage)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

            // Top bar
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                    color: _hasImage ? Colors.white : AppColors.secondary,
                  ),
                  Expanded(
                    child: Text(
                      'Medication Details',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: _hasImage ? Colors.white : AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Bottom content (pushed up due to smaller height)
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (_hasImage ? Colors.white : AppColors.primary)
                          .withValues(alpha: _hasImage ? 0.18 : 0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (_hasImage ? Colors.white : AppColors.primary)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      medication.isScheduled ? 'Scheduled' : 'As Needed',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: _hasImage ? Colors.white : AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    medication.displayName,
                    style: AppTextStyles.h1.copyWith(
                      color: _hasImage ? Colors.white : AppColors.textPrimary,
                      fontSize: 26, // Slightly smaller text for compact hero
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    medication.displayDosage,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: _hasImage
                          ? Colors.white.withValues(alpha: 0.90)
                          : AppColors.secondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  bool _isLightColor(Color color) {
    return color == Colors.white ||
        color == const Color(0xFFFFC107) ||
        color == AppColors.surfaceVariant;
  }

  IconData _getIconForForm(String unit) {
    switch (unit.toLowerCase()) {
      case 'ml':
        return Icons.medication_liquid_rounded;
      case 'tablets':
        return Icons.medication_rounded;
      case 'units':
        return Icons.vaccines_rounded;
      default:
        return Icons.medication_rounded;
    }
  }
}

class _FallbackHeroBackground extends StatelessWidget {
  final Color color;
  final IconData icon;
  final bool isLight;

  const _FallbackHeroBackground({
    required this.color,
    required this.icon,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.20),
            AppColors.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isLight ? AppColors.border : Colors.transparent,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 42,
            color: isLight ? AppColors.secondary : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ACTIVE / INACTIVE TOGGLE
// ══════════════════════════════════════════════════════════════
class _ActiveToggleCard extends StatelessWidget {
  final bool isActive;
  final bool isLoading;
  final ValueChanged<bool> onChanged;

  const _ActiveToggleCard({
    required this.isActive,
    required this.isLoading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary
                  : AppColors.textLight.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.check_rounded : Icons.pause_rounded,
              size: 18,
              color: isActive ? AppColors.secondary : Colors.white,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Active' : 'Paused',
                  style: AppTextStyles.titleSmall,
                ),
                Text(
                  isActive ? 'Reminders are on' : 'No reminders will fire',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),

          if (isLoading)
            const SizedBox(
              width: 40,
              height: 24,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else
            Switch(
              value: isActive,
              onChanged: onChanged,
              activeColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MANAGE SCHEDULE CARD
// ══════════════════════════════════════════════════════════════
class _ManageScheduleCard extends StatelessWidget {
  final VoidCallback onTap;

  const _ManageScheduleCard({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.schedule_rounded,
                color: AppColors.secondary,
                size: 20,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage Schedule',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Set times and frequency',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// FLOATING ACTION ICONS
// ══════════════════════════════════════════════════════════════
class _FloatingActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isDeleting;

  const _FloatingActions({
    required this.onEdit,
    required this.onDelete,
    required this.isDeleting,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FabButton(
            icon: Icons.edit_rounded,
            background: AppColors.primary,
            iconColor: AppColors.secondary,
            onTap: onEdit,
            tooltip: 'Edit',
          ),
          const SizedBox(width: 12),
          _FabButton(
            icon: isDeleting ? null : Icons.delete_outline_rounded,
            background: AppColors.error,
            iconColor: Colors.white,
            onTap: isDeleting ? null : onDelete,
            tooltip: 'Delete',
            isLoading: isDeleting,
          ),
        ],
      ),
    );
  }
}

class _FabButton extends StatelessWidget {
  final IconData? icon;
  final Color background;
  final Color iconColor;
  final VoidCallback? onTap;
  final String tooltip;
  final bool isLoading;

  const _FabButton({
    required this.icon,
    required this.background,
    required this.iconColor,
    required this.onTap,
    required this.tooltip,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        elevation: 6,
        shape: const CircleBorder(),
        shadowColor: background.withValues(alpha: 0.4),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: isLoading
                  ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: iconColor,
                ),
              )
                  : Icon(icon, color: iconColor, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DETAIL SECTION
// ══════════════════════════════════════════════════════════════
class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _DetailSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: AppColors.secondary),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppTextStyles.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTextStyles.bodySmall),
          ),
          Flexible(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}