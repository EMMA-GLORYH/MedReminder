// lib/screens/medications/add_medication_screen.dart

import 'package:flutter/material.dart';
import '../../models/medication.dart';
import '../../services/medication_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/snackbar/app_snackbar.dart';
import 'add_schedule_screen.dart';

class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _genericNameCtrl = TextEditingController();
  final _brandNameCtrl = TextEditingController();
  final _dosageAmountCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Selections
  String _dosageUnit = 'mg';
  String _medicationType = 'scheduled';
  String? _pillColor;
  String? _pillShape;
  bool _isSaving = false;

  // Track if any meds were saved (so parent knows to refresh)
  bool _anySaved = false;

  final List<String> _dosageUnits = [
    'mg', 'mcg', 'g', 'ml', 'units', 'tablets',
  ];
  final List<String> _pillShapes = [
    'round', 'oval', 'capsule', 'rectangle', 'triangle', 'other',
  ];
  final List<Map<String, dynamic>> _pillColors = [
    {'name': 'white', 'color': Colors.white},
    {'name': 'blue', 'color': Colors.blue},
    {'name': 'red', 'color': Colors.red},
    {'name': 'yellow', 'color': Colors.yellow},
    {'name': 'green', 'color': AppColors.primary},
    {'name': 'orange', 'color': Colors.orange},
    {'name': 'pink', 'color': Colors.pink},
    {'name': 'purple', 'color': Colors.purple},
    {'name': 'brown', 'color': Colors.brown},
  ];

  @override
  void dispose() {
    _genericNameCtrl.dispose();
    _brandNameCtrl.dispose();
    _dosageAmountCtrl.dispose();
    _quantityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _genericNameCtrl.clear();
    _brandNameCtrl.clear();
    _dosageAmountCtrl.clear();
    _quantityCtrl.clear();
    _notesCtrl.clear();
    setState(() {
      _dosageUnit = 'mg';
      _medicationType = 'scheduled';
      _pillColor = null;
      _pillShape = null;
    });
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final dosageText = _dosageAmountCtrl.text.trim();
      final dosageAmount = double.tryParse(dosageText);
      if (dosageAmount == null || dosageAmount <= 0) {
        throw Exception('Please enter a valid dosage amount');
      }

      int? quantity;
      if (_quantityCtrl.text.trim().isNotEmpty) {
        quantity = int.tryParse(_quantityCtrl.text.trim());
      }

      // ── Save medication ──
      final medication = await MedicationService.instance.addMedication(
        genericName: _genericNameCtrl.text.trim(),
        brandName: _brandNameCtrl.text.trim(),
        dosageAmount: dosageAmount,
        dosageUnit: _dosageUnit,
        medicationType: _medicationType,
        currentQuantity: quantity,
        pillColor: _pillColor,
        pillShape: _pillShape,
        notes: _notesCtrl.text.trim(),
      );

      if (!mounted) return;

      // ── Route based on type ──
      if (_medicationType == 'scheduled') {
        // Go to schedule screen
        AppSnackbar.success(context, 'Now let\'s set up your schedule');
        final result = await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AddScheduleScreen(
              medicationId: medication.id,
              medicationName: medication.displayName,
            ),
          ),
        );
        if (mounted && result == true) {
          Navigator.pop(context, true);
        }
      } else {
        // PRN doesn't need a schedule
        AppSnackbar.success(context, 'Medication saved!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, _friendlyError(e.toString()));
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showNextStepDialog(Medication medication) async {
    final isScheduled = medication.medicationType == 'scheduled';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SuccessDialog(
        medicationName: medication.displayName,
        isScheduled: isScheduled,
        onScheduleNow: () async {
          Navigator.pop(dialogContext);
          final scheduled = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddScheduleScreen(
                medicationId: medication.id,
                medicationName: medication.displayName,
              ),
            ),
          );
          // After returning from schedule screen, reset form
          // so user can add another if they want
          if (mounted) _resetForm();
        },
        onAddAnother: () {
          Navigator.pop(dialogContext);
          _resetForm();
        },
        onFinish: () {
          Navigator.pop(dialogContext);
          Navigator.pop(context, true); // Back to previous screen
        },
      ),
    );
  }

  String _friendlyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('rls') || lower.contains('policy')) {
      return 'Permission denied. Please contact support.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'No internet connection.';
    }
    if (lower.contains('valid')) {
      return error.replaceAll('Exception: ', '');
    }
    return 'Failed to save medication. Please try again.';
  }

  Future<bool> _onWillPop() async {
    // Return whether any meds were saved
    Navigator.pop(context, _anySaved);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Medication'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context, _anySaved),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ScanBottleCard(onTap: () {
                          AppSnackbar.info(
                              context, 'Bottle scan coming soon!');
                        }),
                        const SizedBox(height: 24),

                        _SectionHeader(
                            icon: Icons.medication_rounded,
                            title: 'Medication Details'),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _genericNameCtrl,
                          label: 'Medication Name',
                          hint: 'e.g. Acetaminophen',
                          prefixIcon: Icons.medication_outlined,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _brandNameCtrl,
                          label: 'Brand Name (optional)',
                          hint: 'e.g. Tylenol',
                          prefixIcon: Icons.label_outline,
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: AppTextField(
                                controller: _dosageAmountCtrl,
                                label: 'Dosage',
                                hint: '500',
                                prefixIcon: Icons.scale_outlined,
                                keyboardType: TextInputType.number,
                                validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DropdownField(
                                label: 'Unit',
                                value: _dosageUnit,
                                items: _dosageUnits,
                                onChanged: (v) =>
                                    setState(() => _dosageUnit = v!),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        _SectionHeader(
                            icon: Icons.category_rounded,
                            title: 'Medication Type'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _TypeCard(
                                label: 'Scheduled',
                                icon: Icons.schedule_rounded,
                                description: 'Fixed times daily',
                                selected: _medicationType == 'scheduled',
                                onTap: () => setState(
                                        () => _medicationType = 'scheduled'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TypeCard(
                                label: 'As Needed',
                                icon: Icons.medical_services_rounded,
                                description: 'When symptoms appear',
                                selected: _medicationType == 'prn',
                                onTap: () => setState(
                                        () => _medicationType = 'prn'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        _SectionHeader(
                            icon: Icons.palette_rounded,
                            title: 'Pill Identification',
                            subtitle: 'Helps with camera verification'),
                        const SizedBox(height: 12),

                        Text('Color', style: AppTextStyles.labelLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _pillColors.map((c) {
                            final selected = _pillColor == c['name'];
                            return _ColorChip(
                              color: c['color'],
                              name: c['name'],
                              selected: selected,
                              onTap: () =>
                                  setState(() => _pillColor = c['name']),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        Text('Shape', style: AppTextStyles.labelLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _pillShapes.map((s) {
                            final selected = _pillShape == s;
                            return _ShapeChip(
                              label: s,
                              selected: selected,
                              onTap: () => setState(() => _pillShape = s),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 24),

                        _SectionHeader(
                            icon: Icons.inventory_2_rounded,
                            title: 'Inventory',
                            subtitle: 'Optional'),
                        const SizedBox(height: 12),

                        AppTextField(
                          controller: _quantityCtrl,
                          label: 'Current Quantity',
                          hint: 'e.g. 30 pills',
                          prefixIcon: Icons.medication_liquid_outlined,
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _notesCtrl,
                          label: 'Notes (optional)',
                          hint: 'e.g. Take with food',
                          prefixIcon: Icons.note_alt_outlined,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: AppButton(
                    label: 'Save Medication',
                    icon: Icons.check_rounded,
                    isLoading: _isSaving,
                    onPressed: _saveMedication,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SUCCESS DIALOG (Choose next action)
// ══════════════════════════════════════════════════════════════
class _SuccessDialog extends StatelessWidget {
  final String medicationName;
  final bool isScheduled;
  final VoidCallback onScheduleNow;
  final VoidCallback onAddAnother;
  final VoidCallback onFinish;

  const _SuccessDialog({
    required this.medicationName,
    required this.isScheduled,
    required this.onScheduleNow,
    required this.onAddAnother,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Medication Added!',
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              medicationName,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              isScheduled
                  ? 'What would you like to do next?'
                  : 'PRN medications don\'t need a schedule',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── Schedule Now (only for scheduled meds) ──
            if (isScheduled) ...[
              AppButton(
                label: 'Schedule Now',
                icon: Icons.schedule_rounded,
                onPressed: onScheduleNow,
              ),
              const SizedBox(height: 10),
            ],

            // ── Add Another ──
            AppButton(
              label: 'Add Another Medication',
              icon: Icons.add_rounded,
              variant: AppButtonVariant.outline,
              onPressed: onAddAnother,
            ),

            const SizedBox(height: 10),

            // ── Finish ──
            AppButton(
              label: isScheduled ? 'Schedule Later' : 'Done',
              variant: AppButtonVariant.text,
              onPressed: onFinish,
            ),

            if (isScheduled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You won\'t get reminders until you set a schedule',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SCAN BOTTLE CARD
// ══════════════════════════════════════════════════════════════
class _ScanBottleCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanBottleCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.secondary, AppColors.secondaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.secondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan pill bottle',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Auto-fill from a photo',
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
// SECTION HEADER
// ══════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.secondary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.titleMedium),
            if (subtitle != null)
              Text(subtitle!, style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DROPDOWN FIELD
// ══════════════════════════════════════════════════════════════
class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down_rounded),
              style: AppTextStyles.bodyLarge,
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TYPE CARD
// ══════════════════════════════════════════════════════════════
class _TypeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.label,
    required this.icon,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 24,
                color: selected
                    ? AppColors.secondary
                    : AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(label,
                style: AppTextStyles.titleSmall.copyWith(
                  color: selected
                      ? AppColors.secondary
                      : AppColors.textPrimary,
                )),
            const SizedBox(height: 2),
            Text(description, style: AppTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// COLOR CHIP
// ══════════════════════════════════════════════════════════════
class _ColorChip extends StatelessWidget {
  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.secondary : AppColors.border,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded,
            size: 20, color: AppColors.secondary)
            : null,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SHAPE CHIP
// ══════════════════════════════════════════════════════════════
class _ShapeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected
                ? AppColors.secondary
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}