// lib/screens/gui/medications/edit_medication_screen.dart

import 'package:flutter/material.dart';
import '../../models/medication.dart';
import '../../services/medication_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/snackbar/app_snackbar.dart';

class EditMedicationScreen extends StatefulWidget {
  final Medication medication;

  const EditMedicationScreen({super.key, required this.medication});

  @override
  State<EditMedicationScreen> createState() => _EditMedicationScreenState();
}

class _EditMedicationScreenState extends State<EditMedicationScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _genericNameCtrl;
  late final TextEditingController _brandNameCtrl;
  late final TextEditingController _dosageAmountCtrl;
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _refillAlertCtrl;
  late final TextEditingController _notesCtrl;

  late String _dosageUnit;
  late String _medicationType;
  String? _pillColor;
  String? _pillShape;
  bool _isSaving = false;

  final List<String> _units = ['mg', 'mcg', 'g', 'ml', 'units', 'tablets'];
  final List<String> _shapes = [
    'round', 'oval', 'capsule', 'rectangle', 'triangle', 'other'
  ];
  final List<Map<String, dynamic>> _colors = [
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
  void initState() {
    super.initState();
    final m = widget.medication;
    _genericNameCtrl = TextEditingController(text: m.genericName);
    _brandNameCtrl = TextEditingController(text: m.brandName ?? '');
    _dosageAmountCtrl = TextEditingController(text: m.dosageAmount.toString());
    _quantityCtrl = TextEditingController(
      text: m.currentQuantity?.toString() ?? '',
    );
    _refillAlertCtrl = TextEditingController(text: m.refillAlertAt.toString());
    _notesCtrl = TextEditingController(text: m.notes ?? '');
    _dosageUnit = m.dosageUnit;
    _medicationType = m.medicationType;
    _pillColor = m.pillColor;
    _pillShape = m.pillShape;
  }

  @override
  void dispose() {
    _genericNameCtrl.dispose();
    _brandNameCtrl.dispose();
    _dosageAmountCtrl.dispose();
    _quantityCtrl.dispose();
    _refillAlertCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final dosageAmount = double.tryParse(_dosageAmountCtrl.text.trim());
      if (dosageAmount == null || dosageAmount <= 0) {
        throw Exception('Please enter a valid dosage');
      }

      int? quantity;
      if (_quantityCtrl.text.trim().isNotEmpty) {
        quantity = int.tryParse(_quantityCtrl.text.trim());
      }

      final refillAlert = int.tryParse(_refillAlertCtrl.text.trim()) ?? 7;

      await MedicationService.instance.updateMedication(
        id: widget.medication.id,
        genericName: _genericNameCtrl.text.trim(),
        brandName: _brandNameCtrl.text.trim(),
        dosageAmount: dosageAmount,
        dosageUnit: _dosageUnit,
        medicationType: _medicationType,
        currentQuantity: quantity,
        refillAlertAt: refillAlert,
        pillColor: _pillColor,
        pillShape: _pillShape,
        notes: _notesCtrl.text.trim(),
      );

      if (!mounted) return;
      AppSnackbar.success(context, 'Medication updated');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to update medication');
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Medication'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
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
                      AppTextField(
                        controller: _genericNameCtrl,
                        label: 'Medication Name',
                        prefixIcon: Icons.medication_outlined,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _brandNameCtrl,
                        label: 'Brand Name (optional)',
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
                              prefixIcon: Icons.scale_outlined,
                              keyboardType: TextInputType.number,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DropdownField(
                              label: 'Unit',
                              value: _dosageUnit,
                              items: _units,
                              onChanged: (v) => setState(() => _dosageUnit = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Type', style: AppTextStyles.labelLarge),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _TypeChip(
                              label: 'Scheduled',
                              icon: Icons.schedule_rounded,
                              selected: _medicationType == 'scheduled',
                              onTap: () =>
                                  setState(() => _medicationType = 'scheduled'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TypeChip(
                              label: 'As Needed',
                              icon: Icons.medical_services_rounded,
                              selected: _medicationType == 'prn',
                              onTap: () =>
                                  setState(() => _medicationType = 'prn'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Color', style: AppTextStyles.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _colors.map((c) {
                          return _ColorChip(
                            color: c['color'],
                            selected: _pillColor == c['name'],
                            onTap: () =>
                                setState(() => _pillColor = c['name']),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Text('Shape', style: AppTextStyles.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _shapes.map((s) {
                          return _ShapeChip(
                            label: s,
                            selected: _pillShape == s,
                            onTap: () => setState(() => _pillShape = s),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      AppTextField(
                        controller: _quantityCtrl,
                        label: 'Current Quantity (optional)',
                        prefixIcon: Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _refillAlertCtrl,
                        label: 'Refill alert when quantity drops to',
                        prefixIcon: Icons.notifications_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _notesCtrl,
                        label: 'Notes (optional)',
                        prefixIcon: Icons.note_alt_outlined,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
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
                  label: 'Save Changes',
                  icon: Icons.check_rounded,
                  isLoading: _isSaving,
                  onPressed: _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 22,
                color: selected
                    ? AppColors.secondary
                    : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        child: Text(label, style: AppTextStyles.labelMedium),
      ),
    );
  }
}