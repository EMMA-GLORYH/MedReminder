// lib/screens/home/caretaker/caretaker_add_medication_screen.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/care_relationship_service.dart';
import '../../../services/medication_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/buttons/app_button.dart';
import '../../../widgets/inputs/app_text_field.dart';
import '../../../widgets/snackbar/app_snackbar.dart';
import 'caretaker_add_schedule_screen.dart';

class CaretakerAddMedicationScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const CaretakerAddMedicationScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<CaretakerAddMedicationScreen> createState() =>
      _CaretakerAddMedicationScreenState();
}

class _CaretakerAddMedicationScreenState
    extends State<CaretakerAddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _genericNameCtrl = TextEditingController();
  final _brandNameCtrl = TextEditingController();
  final _dosageAmountCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Image
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;

  // Selections
  String _dosageUnit = 'mg';
  String _medicationType = 'scheduled';
  String? _pillColor;
  String? _pillShape;

  bool _isSaving = false;
  bool _submitted = false;
  bool _hasPermission = false;
  bool _checkingPermission = true;

  final List<String> _dosageUnits = [
    'mg',
    'mcg',
    'g',
    'ml',
    'units',
    'tablets',
  ];

  final List<String> _pillShapes = [
    'round',
    'oval',
    'capsule',
    'rectangle',
    'triangle',
    'other',
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

  bool get _hasImage => _selectedImageBytes != null && _selectedImage != null;
  bool get _showImageError => _submitted && !_hasImage;
  bool get _showColorError => _submitted && _pillColor == null;
  bool get _showShapeError => _submitted && _pillShape == null;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    try {
      final canEdit = await CareRelationshipService.instance
          .canEditMedications(widget.patientId);

      if (mounted) {
        setState(() {
          _hasPermission = canEdit;
          _checkingPermission = false;
        });

        if (!canEdit) {
          AppSnackbar.error(
            context,
            'You do not have permission to add medications for this patient.',
          );
          // Delay pop slightly so snackbar is visible
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking permission: $e');
      if (mounted) {
        setState(() => _checkingPermission = false);
        AppSnackbar.error(context, 'Failed to check permissions.');
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _genericNameCtrl.dispose();
    _brandNameCtrl.dispose();
    _dosageAmountCtrl.dispose();
    _quantityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedicationImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1400,
        maxHeight: 1400,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
      });

      AppSnackbar.success(context, 'Medicine image added');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Could not open camera. Please try again.');
    }
  }

  Future<void> _saveMedication() async {
    setState(() => _submitted = true);

    final formValid = _formKey.currentState?.validate() ?? false;

    if (!formValid) return;

    if (!_hasImage) {
      AppSnackbar.error(context, 'Please add a medicine image');
      return;
    }

    if (_pillColor == null) {
      AppSnackbar.error(context, 'Please select pill color');
      return;
    }

    if (_pillShape == null) {
      AppSnackbar.error(context, 'Please select pill shape');
      return;
    }

    if (_isSaving) return;
    setState(() => _isSaving = true);

    final dosageText = _dosageAmountCtrl.text.trim();
    final dosageAmount = double.tryParse(dosageText);

    if (dosageAmount == null || dosageAmount <= 0) {
      AppSnackbar.error(context, 'Please enter a valid dosage amount');
      setState(() => _isSaving = false);
      return;
    }

    int? quantity;
    if (_quantityCtrl.text.trim().isNotEmpty) {
      quantity = int.tryParse(_quantityCtrl.text.trim());
      if (quantity == null || quantity < 0) {
        AppSnackbar.error(context, 'Please enter a valid quantity');
        setState(() => _isSaving = false);
        return;
      }
    }

    try {
      // 1. Upload image
      final imageUrl = await MedicationService.instance.uploadMedicationImage(
        bytes: _selectedImageBytes!,
        fileName: _selectedImage!.name,
      );

      // 2. Save medication with patient ID
      // Note: Ensure your MedicationService.addMedication accepts patientId
      // If it doesn't, you may need to update the service to accept it.
      final medication = await MedicationService.instance.addMedication(
        genericName: _genericNameCtrl.text.trim(),
        brandName: _brandNameCtrl.text.trim().isEmpty
            ? null
            : _brandNameCtrl.text.trim(),
        dosageAmount: dosageAmount,
        dosageUnit: _dosageUnit,
        medicationType: _medicationType,
        currentQuantity: quantity,
        pillColor: _pillColor!,
        pillShape: _pillShape!,
        pillImageUrl: imageUrl,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        patientId: widget.patientId, // Pass the patient ID here
      );

      if (!mounted) return;

      // 3. Navigate based on type
      if (_medicationType == 'scheduled') {
        AppSnackbar.success(context, 'Medication saved! Now set up the schedule.');

        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CaretakerAddScheduleScreen(
              medicationId: medication.id,
              medicationName: medication.genericName,
              patientId: widget.patientId,
              patientName: widget.patientName,
            ),
          ),
        );

        if (mounted) {
          Navigator.pop(context, result == true);
        }
      } else {
        AppSnackbar.success(context, 'Medication saved successfully!');
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Save medication error: $e');
      debugPrint('$stack');

      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackbar.error(
          context,
          'Failed to save medication. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Medication')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Medication')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: AppColors.error),
              SizedBox(height: 16),
              Text('Permission Denied'),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Medication'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Patient info banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: AppColors.primary.withOpacity(0.1),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adding medication for',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            widget.patientName,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Fixed top image card
              Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AddImageCard(
                      imageBytes: _selectedImageBytes,
                      onTap: _pickMedicationImage,
                      onRemove: _selectedImageBytes == null
                          ? null
                          : () {
                        setState(() {
                          _selectedImage = null;
                          _selectedImageBytes = null;
                        });
                      },
                    ),
                    if (_showImageError) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Please add a medicine image',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Scrollable form content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          icon: Icons.medication_rounded,
                          title: 'Medication Details',
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _genericNameCtrl,
                          label: 'Medication Name',
                          hint: 'e.g. Acetaminophen',
                          prefixIcon: Icons.medication_outlined,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Medication name is required';
                            }
                            if (v.trim().length < 2) {
                              return 'Name is too short';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _brandNameCtrl,
                          label: 'Brand Name (optional)',
                          hint: 'e.g. Tylenol',
                          prefixIcon: Icons.label_outline,
                          validator: (v) {
                            if (v != null &&
                                v.trim().isNotEmpty &&
                                v.trim().length < 2) {
                              return 'Brand name is too short';
                            }
                            return null;
                          },
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
                                keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final amount = double.tryParse(v.trim());
                                  if (amount == null || amount <= 0) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DropdownField(
                                label: 'Unit',
                                value: _dosageUnit,
                                items: _dosageUnits,
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _dosageUnit = v);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _SectionHeader(
                          icon: Icons.category_rounded,
                          title: 'Medication Type',
                        ),
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
                                onTap: () =>
                                    setState(() => _medicationType = 'prn'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _SectionHeader(
                          icon: Icons.palette_rounded,
                          title: 'Pill Identification',
                          subtitle: 'Required for future camera verification',
                        ),
                        const SizedBox(height: 12),

                        Text('Color', style: AppTextStyles.labelLarge),
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _pillColors.map((c) {
                            final selected = _pillColor == c['name'];
                            return _ColorChip(
                              color: c['color'] as Color,
                              name: c['name'] as String,
                              selected: selected,
                              onTap: () {
                                setState(
                                        () => _pillColor = c['name'] as String);
                              },
                            );
                          }).toList(),
                        ),

                        if (_showColorError)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Select a pill color',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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

                        if (_showShapeError)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Select a pill shape',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),

                        _SectionHeader(
                          icon: Icons.inventory_2_rounded,
                          title: 'Inventory',
                          subtitle: 'Optional',
                        ),
                        const SizedBox(height: 12),

                        AppTextField(
                          controller: _quantityCtrl,
                          label: 'Current Quantity',
                          hint: 'e.g. 30 pills',
                          prefixIcon: Icons.medication_liquid_outlined,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final qty = int.tryParse(v.trim());
                            if (qty == null || qty < 0) {
                              return 'Enter a valid quantity';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        AppTextField(
                          controller: _notesCtrl,
                          label: 'Notes (optional)',
                          hint: 'e.g. Take with food',
                          prefixIcon: Icons.note_alt_outlined,
                          maxLines: 3,
                          validator: (v) {
                            if (v != null && v.trim().length > 300) {
                              return 'Notes must be under 300 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),

              // Fixed bottom save button
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
// WIDGETS
// ══════════════════════════════════════════════════════════════

class _AddImageCard extends StatelessWidget {
  final Uint8List? imageBytes;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _AddImageCard({
    required this.imageBytes,
    required this.onTap,
    this.onRemove,
  });

  bool get hasImage => imageBytes != null;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 120,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: hasImage
                  ? null
                  : LinearGradient(
                colors: [
                  AppColors.secondary,
                  AppColors.secondaryLight,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              color: hasImage ? AppColors.surface : null,
              borderRadius: BorderRadius.circular(20),
              border: hasImage ? Border.all(color: AppColors.border) : null,
              image: hasImage
                  ? DecorationImage(
                image: MemoryImage(imageBytes!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.35),
                  BlendMode.darken,
                ),
              )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasImage
                        ? Colors.white.withValues(alpha: 0.9)
                        : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasImage
                        ? Icons.camera_alt_rounded
                        : Icons.add_a_photo_rounded,
                    color: AppColors.secondary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasImage ? 'Medicine image added' : 'Add image',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasImage
                            ? 'Tap to retake the medicine photo'
                            : 'Take a clear photo of the actual medicine',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
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
        ),
        if (hasImage && onRemove != null)
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.titleMedium),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: AppTextStyles.bodySmall,
                ),
            ],
          ),
        ),
      ],
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
              style: AppTextStyles.bodyLarge,
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e),
                ),
              )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

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
            Icon(
              icon,
              size: 24,
              color: selected ? AppColors.secondary : AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.titleSmall.copyWith(
                color: selected ? AppColors.secondary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: AppTextStyles.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

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

  bool get _isLight =>
      color == Colors.white ||
          color == Colors.yellow ||
          color == const Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkWell(
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
              ? Icon(
            Icons.check_rounded,
            size: 20,
            color: _isLight ? AppColors.secondary : Colors.white,
          )
              : null,
        ),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
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
            color: selected ? AppColors.secondary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}