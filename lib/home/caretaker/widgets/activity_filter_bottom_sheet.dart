// lib/home/caretaker/widgets/activity_filter_bottom_sheet.dart

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

class ActivityFilterBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> patients;
  final String? selectedPatientId;
  final String? selectedStatus;
  final void Function(String? patientId, String? status) onApply;

  const ActivityFilterBottomSheet({
    super.key,
    required this.patients,
    this.selectedPatientId,
    this.selectedStatus,
    required this.onApply,
  });

  @override
  State<ActivityFilterBottomSheet> createState() =>
      _ActivityFilterBottomSheetState();
}

class _ActivityFilterBottomSheetState extends State<ActivityFilterBottomSheet> {
  String? _selectedPatientId;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedPatientId = widget.selectedPatientId;
    _selectedStatus = widget.selectedStatus ?? 'all';
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

            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_list_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Text('Filter Activities', style: AppTextStyles.h2),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedPatientId = null;
                        _selectedStatus = 'all';
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Filter Options
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(20),
                children: [
                  // Patient Filter
                  Text('Patient', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'All Patients',
                        isSelected: _selectedPatientId == null,
                        onTap: () {
                          setState(() {
                            _selectedPatientId = null;
                          });
                        },
                      ),
                      ...widget.patients.map(
                            (patient) => _FilterChip(
                          label: patient['name'] as String,
                          isSelected: _selectedPatientId == patient['id'],
                          onTap: () {
                            setState(() {
                              _selectedPatientId = patient['id'] as String;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Status Filter
                  Text('Status', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'All Statuses',
                        isSelected: _selectedStatus == 'all',
                        onTap: () {
                          setState(() {
                            _selectedStatus = 'all';
                          });
                        },
                      ),
                      _FilterChip(
                        label: 'Taken',
                        icon: Icons.check_circle_rounded,
                        color: Colors.green,
                        isSelected: _selectedStatus == 'taken',
                        onTap: () {
                          setState(() {
                            _selectedStatus = 'taken';
                          });
                        },
                      ),
                      _FilterChip(
                        label: 'Missed',
                        icon: Icons.cancel_rounded,
                        color: AppColors.error,
                        isSelected: _selectedStatus == 'missed',
                        onTap: () {
                          setState(() {
                            _selectedStatus = 'missed';
                          });
                        },
                      ),
                      _FilterChip(
                        label: 'Pending',
                        icon: Icons.pending_rounded,
                        color: AppColors.warning,
                        isSelected: _selectedStatus == 'pending',
                        onTap: () {
                          setState(() {
                            _selectedStatus = 'pending';
                          });
                        },
                      ),
                      _FilterChip(
                        label: 'Skipped',
                        icon: Icons.remove_circle_rounded,
                        color: AppColors.textSecondary,
                        isSelected: _selectedStatus == 'skipped',
                        onTap: () {
                          setState(() {
                            _selectedStatus = 'skipped';
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Apply Button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(
                      _selectedPatientId,
                      _selectedStatus == 'all' ? null : _selectedStatus,
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Apply Filters'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withOpacity(0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? chipColor : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: isSelected ? chipColor : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}