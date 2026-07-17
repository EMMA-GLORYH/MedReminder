// lib/gui/medications/add_schedule_screen.dart

import 'package:flutter/material.dart';

import '../../models/medication_schedule.dart';
import '../../services/medication_service.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/snackbar/app_snackbar.dart';

class AddScheduleScreen extends StatefulWidget {
  final String medicationId;
  final String medicationName;

  /// Called immediately after the user taps Save, before the database
  /// write completes. The dashboard uses this to show the dose card
  /// instantly with a "Saving…" indicator.
  final void Function(List<TodayDose> optimisticDoses)? onOptimisticDoses;

  /// Called after the background save succeeds so the dashboard can
  /// reload the real data from the database.
  final VoidCallback? onSaveCompleted;

  /// Called if the background save fails so the dashboard can remove
  /// the optimistic doses.
  final void Function(String error)? onSaveFailed;

  const AddScheduleScreen({
    super.key,
    required this.medicationId,
    required this.medicationName,
    this.onOptimisticDoses,
    this.onSaveCompleted,
    this.onSaveFailed,
  });

  @override
  State<AddScheduleScreen> createState() =>
      _AddScheduleScreenState();
}

class _AddScheduleScreenState
    extends State<AddScheduleScreen> {
  String _frequencyType = 'daily';
  List<TimeOfDay> _times = [
    const TimeOfDay(hour: 8, minute: 0),
  ];
  double _intervalHours = 8;
  List<int> _selectedDays = [0, 1, 2, 3, 4, 5, 6];
  bool _escalationEnabled = true;
  bool _isSaving = false;
  bool _isLoading = true;

  MedicationSchedule? _existingSchedule;

  final _weekdays = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  @override
  void initState() {
    super.initState();
    _checkExistingSchedule();
  }

  Future<void> _checkExistingSchedule() async {
    try {
      final schedules = await ScheduleService.instance
          .getSchedulesForMedication(
        widget.medicationId,
      );

      if (schedules.isNotEmpty) {
        final existing = schedules.first;

        if (mounted) {
          setState(() {
            _existingSchedule = existing;
            _frequencyType = existing.frequencyType;
            _escalationEnabled = existing.escalationEnabled;

            if (existing.scheduledTimes != null) {
              _times = List<TimeOfDay>.from(
                existing.scheduledTimes!,
              );
            }

            if (existing.scheduledDays != null) {
              _selectedDays = List<int>.from(
                existing.scheduledDays!,
              );
            }

            _intervalHours = existing.intervalHours ?? 8.0;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading existing schedule: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD OPTIMISTIC DOSES FROM FORM STATE
  //
  // Constructs TodayDose objects from the current form selections
  // without waiting for the database. These are shown immediately
  // on the dashboard with a "Saving…" badge.
  // ══════════════════════════════════════════════════════════════

  List<TodayDose> _buildOptimisticDoses({
    required String dosageDisplay,
    required String? pillImageUrl,
    required String? patientId,
  }) {
    final today = DateTime.now();
    final doses = <TodayDose>[];

    final effectiveTimes =
    (_frequencyType == 'daily' ||
        _frequencyType == 'multiple_daily')
        ? _times
        : _frequencyType == 'every_x_hours'
        ? [
      TimeOfDay.fromDateTime(
        today.add(
          Duration(
            minutes:
            (_intervalHours * 60).round(),
          ),
        ),
      ),
    ]
        : <TimeOfDay>[];

    for (final time in effectiveTimes) {
      final scheduledTime = DateTime(
        today.year,
        today.month,
        today.day,
        time.hour,
        time.minute,
      );

      // Only show doses that are scheduled for today.
      final weekday = today.weekday % 7;
      final isScheduledToday = _selectedDays.isEmpty ||
          _selectedDays.length == 7 ||
          _selectedDays.contains(weekday);

      if (!isScheduledToday) continue;

      doses.add(
        TodayDose(
          // Temporary ID for the optimistic dose.
          scheduleId:
          'optimistic_${widget.medicationId}_${time.hour}_${time.minute}',
          medicationId: widget.medicationId,
          medicationName: widget.medicationName,
          genericName: widget.medicationName,
          dosageAmount: _parseDosageAmount(dosageDisplay),
          dosageUnit: _parseDosageUnit(dosageDisplay),
          pillImageUrl: pillImageUrl,
          scheduledTime: scheduledTime,
          patientId: patientId,
          isPending: true,
        ),
      );
    }

    return doses;
  }

  double _parseDosageAmount(String display) {
    final parts = display.trim().split(RegExp(r'\s+'));
    return double.tryParse(parts.first) ?? 1.0;
  }

  String _parseDosageUnit(String display) {
    final parts = display.trim().split(RegExp(r'\s+'));
    return parts.length > 1
        ? parts.sublist(1).join(' ')
        : 'dose';
  }

  // ══════════════════════════════════════════════════════════════
  // SAVE
  // ══════════════════════════════════════════════════════════════

  Future<void> _saveSchedule() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final medication = await MedicationService.instance
          .getMedicationById(widget.medicationId);

      if (medication == null) {
        if (mounted) {
          AppSnackbar.error(
            context,
            'Medication not found. Please try again.',
          );
          setState(() => _isSaving = false);
        }
        return;
      }

      final dosageDisplay = medication.displayDosage;
      final pillImageUrl = medication.pillImageUrl;
      final patientId = medication.patientId;

      // ── Step 1: Build optimistic doses immediately ─────────
      final optimisticDoses = _buildOptimisticDoses(
        dosageDisplay: dosageDisplay,
        pillImageUrl: pillImageUrl,
        patientId: patientId,
      );

      // ── Step 2: Notify dashboard to show them immediately ──
      widget.onOptimisticDoses?.call(optimisticDoses);

      // ── Step 3: Show success snackbar and navigate back ────
      if (mounted) {
        AppSnackbar.success(
          context,
          _existingSchedule != null
              ? 'Schedule updated!'
              : 'Schedule saved!',
        );

        Navigator.pop(context, true);
      }

      // ── Step 4: Save to database in background ─────────────
      if (_existingSchedule != null) {
        await ScheduleService.instance.updateSchedule(
          id: _existingSchedule!.id,
          medicationId: widget.medicationId,
          medicationName: widget.medicationName,
          dosageDisplay: dosageDisplay,
          frequencyType: _frequencyType,
          scheduledTimes:
          (_frequencyType == 'daily' ||
              _frequencyType == 'multiple_daily')
              ? _times
              : null,
          intervalHours:
          _frequencyType == 'every_x_hours'
              ? _intervalHours
              : null,
          scheduledDays: _selectedDays.length == 7
              ? null
              : _selectedDays,
          escalationEnabled: _escalationEnabled,
          pillImageUrl: pillImageUrl,
        );
      } else {
        await ScheduleService.instance.addSchedule(
          medicationId: widget.medicationId,
          medicationName: widget.medicationName,
          dosageDisplay: dosageDisplay,
          frequencyType: _frequencyType,
          scheduledTimes:
          (_frequencyType == 'daily' ||
              _frequencyType == 'multiple_daily')
              ? _times
              : null,
          intervalHours:
          _frequencyType == 'every_x_hours'
              ? _intervalHours
              : null,
          scheduledDays: _selectedDays.length == 7
              ? null
              : _selectedDays,
          escalationEnabled: _escalationEnabled,
          pillImageUrl: pillImageUrl,
        );
      }

      // ── Step 5: Notify dashboard to reload real data ────────
      widget.onSaveCompleted?.call();
    } catch (e, stack) {
      debugPrint('❌ Background save error: $e');
      debugPrint('$stack');

      // Remove the optimistic doses and show the error.
      widget.onSaveFailed?.call(
        'Failed to save schedule. Please try again.',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _existingSchedule != null
              ? 'Edit Schedule'
              : 'Set Schedule',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Medication name header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
              AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.medication_rounded,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.medicationName,
                    style: AppTextStyles.titleMedium,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'How often?',
            style: AppTextStyles.titleMedium,
          ),

          const SizedBox(height: 12),

          _FrequencyOption(
            label: 'Once a day',
            description: 'One dose per day',
            icon: Icons.wb_sunny_outlined,
            selected: _frequencyType == 'daily',
            onTap: () => setState(() {
              _frequencyType = 'daily';
              _times = [
                const TimeOfDay(hour: 8, minute: 0),
              ];
            }),
          ),

          const SizedBox(height: 8),

          _FrequencyOption(
            label: 'Multiple times a day',
            description: 'Set specific times',
            icon: Icons.schedule_rounded,
            selected: _frequencyType == 'multiple_daily',
            onTap: () => setState(
                  () => _frequencyType = 'multiple_daily',
            ),
          ),

          const SizedBox(height: 8),

          _FrequencyOption(
            label: 'Every X hours',
            description: 'Strict interval spacing',
            icon: Icons.timer_outlined,
            selected: _frequencyType == 'every_x_hours',
            onTap: () => setState(
                  () => _frequencyType = 'every_x_hours',
            ),
          ),

          const SizedBox(height: 8),

          _FrequencyOption(
            label: 'As needed',
            description: 'No fixed schedule',
            icon: Icons.medical_services_outlined,
            selected: _frequencyType == 'as_needed',
            onTap: () => setState(
                  () => _frequencyType = 'as_needed',
            ),
          ),

          // Time slots
          if (_frequencyType == 'daily' ||
              _frequencyType == 'multiple_daily') ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reminder times',
                  style: AppTextStyles.titleMedium,
                ),
                if (_frequencyType == 'multiple_daily')
                  TextButton.icon(
                    onPressed: () => setState(
                          () => _times.add(
                        const TimeOfDay(
                          hour: 12,
                          minute: 0,
                        ),
                      ),
                    ),
                    icon: const Icon(
                      Icons.add,
                      size: 16,
                    ),
                    label: const Text('Add time'),
                  ),
              ],
            ),
            ..._times.asMap().entries.map(
                  (entry) => _TimeSlotTile(
                time: entry.value,
                canRemove: _times.length > 1,
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: entry.value,
                  );

                  if (picked != null) {
                    setState(
                          () => _times[entry.key] = picked,
                    );
                  }
                },
                onRemove: () => setState(
                      () => _times.removeAt(entry.key),
                ),
              ),
            ),
          ],

          // Interval slider
          if (_frequencyType == 'every_x_hours') ...[
            const SizedBox(height: 20),
            Text(
              'Interval: ${_intervalHours.toInt()} hours',
              style: AppTextStyles.titleMedium,
            ),
            Slider(
              value: _intervalHours,
              min: 1,
              max: 24,
              divisions: 23,
              onChanged: (value) =>
                  setState(() => _intervalHours = value),
            ),
          ],

          // Day picker
          if (_frequencyType != 'as_needed') ...[
            const SizedBox(height: 20),
            Text(
              'Which days?',
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: List.generate(7, (index) {
                final selected =
                _selectedDays.contains(index);

                return InkWell(
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedDays.remove(index);
                    } else {
                      _selectedDays.add(index);
                    }
                  }),
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
                      _weekdays[index],
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],

          const SizedBox(height: 32),

          AppButton(
            label: _existingSchedule != null
                ? 'Update Schedule'
                : 'Save Schedule',
            isLoading: _isSaving,
            onPressed: _saveSchedule,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// FREQUENCY OPTION
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
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected
                  ? AppColors.secondary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.titleSmall
                        .copyWith(
                      color: selected
                          ? AppColors.secondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TIME SLOT TILE
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.access_time_rounded,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Text(
                time.format(context),
                style: AppTextStyles.titleMedium,
              ),
            ),
          ),
          if (canRemove)
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 20,
              ),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}