// lib/screens/medications/add_schedule_screen.dart

import 'package:flutter/material.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/snackbar/app_snackbar.dart';
import '../../services/medication_service.dart';

class AddScheduleScreen extends StatefulWidget {
  final String medicationId;
  final String medicationName;

  const AddScheduleScreen({
    super.key,
    required this.medicationId,
    required this.medicationName,
  });

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  String _frequencyType = 'daily';
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  double _intervalHours = 8;
  final List<int> _selectedDays = [0, 1, 2, 3, 4, 5, 6]; // All days
  bool _escalationEnabled = true;
  bool _isSaving = false;

  final _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (picked != null) {
      setState(() => _times[index] = picked);
    }
  }

  void _addTimeSlot() {
    setState(() {
      _times.add(TimeOfDay(
        hour: (_times.last.hour + 8) % 24,
        minute: 0,
      ));
    });
  }

  void _removeTimeSlot(int index) {
    if (_times.length > 1) {
      setState(() => _times.removeAt(index));
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        if (_selectedDays.length > 1) _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  Future<void> _saveSchedule() async {
    setState(() => _isSaving = true);

    try {
      // ── 1. Fetch the medication details ────────────────────────
      final medication = await MedicationService.instance
          .getMedicationById(widget.medicationId);

      if (medication == null) {
        throw Exception('Medication not found');
      }

      // ── 2. Build display values for notifications ──────────────
      final medName = (medication.brandName?.isNotEmpty ?? false)
          ? medication.brandName!
          : medication.genericName;

      final dosageStr = medication.dosageAmount % 1 == 0
          ? medication.dosageAmount.toInt().toString()
          : medication.dosageAmount.toString();
      final dosageDisplay = '$dosageStr ${medication.dosageUnit}';

      // ── 3. Save the schedule ───────────────────────────────────
      await ScheduleService.instance.addSchedule(
        medicationId:      widget.medicationId,
        medicationName:    medName,
        dosageDisplay:     dosageDisplay,
        frequencyType:     _frequencyType,
        scheduledTimes:    _frequencyType == 'daily' ||
            _frequencyType == 'multiple_daily'
            ? _times
            : null,
        intervalHours:     _frequencyType == 'every_x_hours'
            ? _intervalHours
            : null,
        scheduledDays:     _selectedDays.length == 7 ? null : _selectedDays,
        escalationEnabled: _escalationEnabled,
      );

      if (!mounted) return;
      AppSnackbar.success(context, 'Schedule saved!');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to save schedule');
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Schedule'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Medication name banner ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.medication_rounded,
                          color: AppColors.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(widget.medicationName,
                            style: AppTextStyles.titleMedium),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Frequency picker ──
                Text('How often?', style: AppTextStyles.titleMedium),
                const SizedBox(height: 12),

                _FrequencyOption(
                  label: 'Once a day',
                  description: 'One dose per day',
                  icon: Icons.wb_sunny_outlined,
                  selected: _frequencyType == 'daily',
                  onTap: () {
                    setState(() {
                      _frequencyType = 'daily';
                      _times = [const TimeOfDay(hour: 8, minute: 0)];
                    });
                  },
                ),
                const SizedBox(height: 8),
                _FrequencyOption(
                  label: 'Multiple times a day',
                  description: 'Set specific times',
                  icon: Icons.schedule_rounded,
                  selected: _frequencyType == 'multiple_daily',
                  onTap: () {
                    setState(() {
                      _frequencyType = 'multiple_daily';
                      if (_times.length < 2) {
                        _times = [
                          const TimeOfDay(hour: 8, minute: 0),
                          const TimeOfDay(hour: 20, minute: 0),
                        ];
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                _FrequencyOption(
                  label: 'Every X hours',
                  description: 'Strict interval spacing',
                  icon: Icons.timer_outlined,
                  selected: _frequencyType == 'every_x_hours',
                  onTap: () =>
                      setState(() => _frequencyType = 'every_x_hours'),
                ),
                const SizedBox(height: 8),
                _FrequencyOption(
                  label: 'As needed',
                  description: 'No fixed schedule (PRN)',
                  icon: Icons.medical_services_outlined,
                  selected: _frequencyType == 'as_needed',
                  onTap: () =>
                      setState(() => _frequencyType = 'as_needed'),
                ),

                const SizedBox(height: 24),

                // ── Time slots (for daily/multiple) ──
                if (_frequencyType == 'daily' ||
                    _frequencyType == 'multiple_daily') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Reminder times',
                          style: AppTextStyles.titleMedium),
                      if (_frequencyType == 'multiple_daily')
                        TextButton.icon(
                          onPressed: _addTimeSlot,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add time'),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.secondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._times.asMap().entries.map((entry) {
                    final index = entry.key;
                    final time = entry.value;
                    return _TimeSlotTile(
                      time: time,
                      canRemove: _times.length > 1,
                      onTap: () => _pickTime(index),
                      onRemove: () => _removeTimeSlot(index),
                    );
                  }),
                ],

                // ── Interval hours ──
                if (_frequencyType == 'every_x_hours') ...[
                  Text('Every ${_intervalHours.toStringAsFixed(0)} hours',
                      style: AppTextStyles.titleMedium),
                  const SizedBox(height: 8),
                  Slider(
                    value: _intervalHours,
                    min: 1,
                    max: 24,
                    divisions: 23,
                    activeColor: AppColors.primary,
                    label: '${_intervalHours.toStringAsFixed(0)}h',
                    onChanged: (v) =>
                        setState(() => _intervalHours = v),
                  ),
                ],

                // ── Days picker ──
                if (_frequencyType != 'as_needed') ...[
                  const SizedBox(height: 16),
                  Text('Which days?', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (i) {
                      final selected = _selectedDays.contains(i);
                      return InkWell(
                        onTap: () => _toggleDay(i),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : AppColors.surface,
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            _weekdays[i],
                            style: AppTextStyles.labelSmall.copyWith(
                              color: selected
                                  ? AppColors.secondary
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Escalation toggle ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded,
                          color: AppColors.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Escalating alerts',
                                style: AppTextStyles.titleSmall),
                            Text(
                              'Alarm → SMS if missed',
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _escalationEnabled,
                        onChanged: (v) =>
                            setState(() => _escalationEnabled = v),
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
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
                label: 'Save Schedule',
                icon: Icons.check_rounded,
                isLoading: _isSaving,
                onPressed: _saveSchedule,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _FrequencyOption extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FrequencyOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                color:
                selected ? AppColors.secondary : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: selected
                            ? AppColors.secondary
                            : AppColors.textPrimary,
                      )),
                  Text(description, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
class _TimeSlotTile extends StatelessWidget {
  final TimeOfDay time;
  final bool canRemove;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _TimeSlotTile({
    required this.time,
    required this.canRemove,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = time.format(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded, color: AppColors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Text(formatted, style: AppTextStyles.titleMedium),
            ),
          ),
          if (canRemove)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onRemove,
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}