import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/medication_schedule.dart';
import '../../../services/care_relationship_service.dart';
import '../../../services/local_cache_service.dart';
import '../../../services/medication_service.dart';
import '../../../services/schedule_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/buttons/app_button.dart';
import '../../../widgets/snackbar/app_snackbar.dart';

class CaretakerAddScheduleScreen extends StatefulWidget {
  final String medicationId;
  final String medicationName;
  final String patientId;
  final String patientName;

  final void Function(List<TodayDose> optimisticDoses)? onOptimisticDoses;
  final VoidCallback? onSaveCompleted;
  final void Function(String error)? onSaveFailed;

  const CaretakerAddScheduleScreen({
    super.key,
    required this.medicationId,
    required this.medicationName,
    required this.patientId,
    required this.patientName,
    this.onOptimisticDoses,
    this.onSaveCompleted,
    this.onSaveFailed,
  });

  @override
  State<CaretakerAddScheduleScreen> createState() =>
      _CaretakerAddScheduleScreenState();
}

class _CaretakerAddScheduleScreenState
    extends State<CaretakerAddScheduleScreen> {
  String _resolvedPatientId = '';

  String _frequencyType = 'daily';
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  double _intervalHours = 8;
  List<int> _selectedDays = [0, 1, 2, 3, 4, 5, 6];
  bool _escalationEnabled = true;

  bool _isSaving = false;
  bool _isLoading = true;
  bool _scheduleSaved = false;
  bool _hasUnsavedChanges = false;
  bool _hasPermission = false;
  bool _checkingPermission = true;

  MedicationSchedule? _existingSchedule;
  MedicationSchedule? _originalSchedule;

  final _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  DateTime? _lastSaveAttempt;
  static const Duration _saveCooldown = Duration(seconds: 3);

  static const List<_TimePreset> _timePresets = [
    _TimePreset(
      'Morning',
      Icons.wb_sunny_rounded,
      TimeOfDay(hour: 8, minute: 0),
    ),
    _TimePreset(
      'Noon',
      Icons.wb_sunny_outlined,
      TimeOfDay(hour: 12, minute: 0),
    ),
    _TimePreset(
      'Afternoon',
      Icons.wb_twilight_rounded,
      TimeOfDay(hour: 15, minute: 0),
    ),
    _TimePreset(
      'Evening',
      Icons.nights_stay_outlined,
      TimeOfDay(hour: 18, minute: 0),
    ),
    _TimePreset(
      'Night',
      Icons.bedtime_rounded,
      TimeOfDay(hour: 21, minute: 0),
    ),
    _TimePreset(
      'Bedtime',
      Icons.dark_mode_rounded,
      TimeOfDay(hour: 22, minute: 30),
    ),
  ];

  static const List<_SchedulePreset> _schedulePresets = [
    _SchedulePreset(
      'Once daily',
      'Morning',
      [TimeOfDay(hour: 8, minute: 0)],
    ),
    _SchedulePreset(
      'Twice daily',
      'Morning & Evening',
      [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
    ),
    _SchedulePreset(
      'Three times',
      'Morning, Noon & Evening',
      [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 13, minute: 0),
        TimeOfDay(hour: 19, minute: 0),
      ],
    ),
    _SchedulePreset(
      'Four times',
      'Every 6 hours',
      [
        TimeOfDay(hour: 6, minute: 0),
        TimeOfDay(hour: 12, minute: 0),
        TimeOfDay(hour: 18, minute: 0),
        TimeOfDay(hour: 22, minute: 0),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<String> _resolveTruePatientId(String id) async {
    final safeId = id.trim();
    if (safeId.isEmpty) return safeId;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('id', safeId)
          .maybeSingle();

      if (profile != null && profile['id'] != null) {
        return safeId;
      }
    } catch (_) {}

    try {
      final relationship = await Supabase.instance.client
          .from('care_relationships')
          .select('patient_id')
          .eq('id', safeId)
          .maybeSingle();

      if (relationship != null && relationship['patient_id'] != null) {
        return relationship['patient_id'].toString();
      }
    } catch (_) {}

    return safeId;
  }

  Future<void> _initialize() async {
    try {
      _resolvedPatientId = await _resolveTruePatientId(widget.patientId);
      debugPrint(
        '🚀 CaretakerAddScheduleScreen resolved patient ID: $_resolvedPatientId',
      );
      await _checkPermission();
    } catch (e) {
      debugPrint('❌ Failed to initialize schedule screen: $e');
      if (!mounted) return;
      setState(() => _checkingPermission = false);
      AppSnackbar.error(context, 'Failed to load schedule setup.');
      Navigator.pop(context);
    }
  }

  Future<void> _checkPermission() async {
    try {
      final canEdit = await CareRelationshipService.instance
          .canEditMedications(_resolvedPatientId);

      if (!mounted) return;

      setState(() {
        _hasPermission = canEdit;
        _checkingPermission = false;
      });

      if (!canEdit) {
        AppSnackbar.error(
          context,
          'You do not have permission to manage schedules for this patient.',
        );
        Navigator.pop(context);
      } else {
        _loadExistingSchedule();
      }
    } catch (e) {
      debugPrint('Error checking permission: $e');
      if (!mounted) return;
      setState(() => _checkingPermission = false);
      AppSnackbar.error(context, 'Failed to check permissions.');
      Navigator.pop(context);
    }
  }

  Future<void> _loadExistingSchedule() async {
    try {
      final cachedSchedules = await LocalCacheService.instance
          .getCachedSchedulesForMedication(widget.medicationId);

      if (cachedSchedules.isNotEmpty) {
        final existing = cachedSchedules.first;
        if (!mounted) return;
        setState(() {
          _existingSchedule = existing;
          _originalSchedule = existing;
          _frequencyType = existing.frequencyType;
          _escalationEnabled = existing.escalationEnabled;
          if (existing.scheduledTimes != null) {
            _times = List<TimeOfDay>.from(existing.scheduledTimes!);
          }
          if (existing.scheduledDays != null) {
            _selectedDays = List<int>.from(existing.scheduledDays!);
          }
          _intervalHours = existing.intervalHours ?? 8.0;
          _isLoading = false;
        });
        return;
      }

      final schedules = await ScheduleService.instance.getSchedulesForMedication(
        widget.medicationId,
        patientId: _resolvedPatientId,
      );

      if (schedules.isNotEmpty && mounted) {
        final existing = schedules.first;
        setState(() {
          _existingSchedule = existing;
          _originalSchedule = existing;
          _frequencyType = existing.frequencyType;
          _escalationEnabled = existing.escalationEnabled;
          if (existing.scheduledTimes != null) {
            _times = List<TimeOfDay>.from(existing.scheduledTimes!);
          }
          if (existing.scheduledDays != null) {
            _selectedDays = List<int>.from(existing.scheduledDays!);
          }
          _intervalHours = existing.intervalHours ?? 8.0;
        });
      }
    } catch (e) {
      debugPrint('Error loading existing schedule: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _hasChanges() {
    if (_originalSchedule == null) return true;

    return _frequencyType != _originalSchedule!.frequencyType ||
        _escalationEnabled != _originalSchedule!.escalationEnabled ||
        _intervalHours != (_originalSchedule!.intervalHours ?? 8.0) ||
        !_listsEqual(_times, _originalSchedule!.scheduledTimes ?? []) ||
        !_listsEqual(_selectedDays, _originalSchedule!.scheduledDays ?? []);
  }

  bool _listsEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _markAsChanged() {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  void _applyPreset(_SchedulePreset preset) {
    _markAsChanged();
    setState(() {
      _frequencyType = preset.times.length == 1 ? 'daily' : 'multiple_daily';
      _times = List<TimeOfDay>.from(preset.times);
    });
    AppSnackbar.success(context, '${preset.name} schedule applied');
  }

  void _addTimePreset(_TimePreset preset) {
    final exists = _times.any(
          (t) => t.hour == preset.time.hour && t.minute == preset.time.minute,
    );

    if (exists) {
      AppSnackbar.error(context, '${preset.label} is already added');
      return;
    }

    _markAsChanged();
    setState(() {
      _times.add(preset.time);
      _times.sort((a, b) {
        final aMinutes = a.hour * 60 + a.minute;
        final bMinutes = b.hour * 60 + b.minute;
        return aMinutes.compareTo(bMinutes);
      });

      if (_times.length > 1 && _frequencyType == 'daily') {
        _frequencyType = 'multiple_daily';
      }
    });
  }

  Future<TimeOfDay?> _showTimePickerSheet(TimeOfDay initial) async {
    DateTime tempValue = DateTime(
      2024,
      1,
      1,
      initial.hour,
      initial.minute,
    );

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.of(sheetContext).viewPadding.bottom;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              bottomPadding > 0 ? bottomPadding : 12,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select reminder time',
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  Divider(color: AppColors.border, height: 1),
                  SizedBox(
                    height: 220,
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        brightness: Theme.of(sheetContext).brightness,
                        primaryColor: AppColors.primary,
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        use24hFormat: false,
                        minuteInterval: 1,
                        initialDateTime: tempValue,
                        onDateTimeChanged: (value) {
                          tempValue = value;
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(
                                sheetContext,
                                TimeOfDay(
                                  hour: tempValue.hour,
                                  minute: tempValue.minute,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCustomTime({int? replaceIndex}) async {
    final initial = replaceIndex != null
        ? _times[replaceIndex]
        : const TimeOfDay(hour: 12, minute: 0);

    final picked = await _showTimePickerSheet(initial);
    if (picked == null) return;

    _markAsChanged();

    setState(() {
      if (replaceIndex != null) {
        _times[replaceIndex] = picked;
      } else {
        final exists = _times.any(
              (t) => t.hour == picked.hour && t.minute == picked.minute,
        );

        if (exists) {
          AppSnackbar.error(context, 'This time is already added');
          return;
        }

        _times.add(picked);

        if (_times.length > 1 && _frequencyType == 'daily') {
          _frequencyType = 'multiple_daily';
        }
      }

      _times.sort((a, b) {
        final aMinutes = a.hour * 60 + a.minute;
        final bMinutes = b.hour * 60 + b.minute;
        return aMinutes.compareTo(bMinutes);
      });
    });
  }

  void _selectAllDays() {
    _markAsChanged();
    setState(() => _selectedDays = [0, 1, 2, 3, 4, 5, 6]);
  }

  void _selectWeekdays() {
    _markAsChanged();
    setState(() => _selectedDays = [1, 2, 3, 4, 5]);
  }

  void _selectWeekends() {
    _markAsChanged();
    setState(() => _selectedDays = [0, 6]);
  }

  List<TodayDose> _buildOptimisticDoses({
    required String dosageDisplay,
    required String? pillImageUrl,
  }) {
    final today = DateTime.now();
    final doses = <TodayDose>[];

    final effectiveTimes =
    (_frequencyType == 'daily' || _frequencyType == 'multiple_daily')
        ? _times
        : _frequencyType == 'every_x_hours'
        ? [
      TimeOfDay.fromDateTime(
        today.add(
          Duration(minutes: (_intervalHours * 60).round()),
        ),
      ),
    ]
        : <TimeOfDay>[];

    for (final time in effectiveTimes) {
      final scheduledTime =
      DateTime(today.year, today.month, today.day, time.hour, time.minute);

      final weekday = today.weekday % 7;
      final isScheduledToday = _selectedDays.isEmpty ||
          _selectedDays.length == 7 ||
          _selectedDays.contains(weekday);

      if (!isScheduledToday) continue;

      doses.add(
        TodayDose(
          scheduleId: 'optimistic_${widget.medicationId}_${time.hour}_${time.minute}',
          medicationId: widget.medicationId,
          medicationName: widget.medicationName,
          genericName: widget.medicationName,
          dosageAmount: _parseDosageAmount(dosageDisplay),
          dosageUnit: _parseDosageUnit(dosageDisplay),
          pillImageUrl: pillImageUrl,
          scheduledTime: scheduledTime,
          patientId: _resolvedPatientId,
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
    return parts.length > 1 ? parts.sublist(1).join(' ') : 'dose';
  }

  bool _canSave() {
    if (_lastSaveAttempt != null) {
      final elapsed = DateTime.now().difference(_lastSaveAttempt!);
      if (elapsed < _saveCooldown) {
        return false;
      }
    }
    return !_isSaving;
  }

  Future<void> _saveSchedule() async {
    if (!_canSave()) {
      AppSnackbar.warning(context, 'Please wait a moment before saving again');
      return;
    }

    if ((_frequencyType == 'daily' || _frequencyType == 'multiple_daily') &&
        _times.isEmpty) {
      AppSnackbar.error(context, 'Please add at least one time');
      return;
    }

    if (_frequencyType != 'as_needed' && _selectedDays.isEmpty) {
      AppSnackbar.error(context, 'Please select at least one day');
      return;
    }

    if (_existingSchedule != null && !_hasChanges()) {
      AppSnackbar.info(context, 'No changes to save');
      Navigator.pop(context, false);
      return;
    }

    setState(() {
      _isSaving = true;
      _lastSaveAttempt = DateTime.now();
    });

    try {
      final medication =
      await MedicationService.instance.getMedicationById(widget.medicationId);

      if (medication == null) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        AppSnackbar.error(context, 'Medication not found. Please try again.');
        widget.onSaveFailed?.call('Medication not found');
        return;
      }

      final dosageDisplay = medication.displayDosage;
      final pillImageUrl = medication.pillImageUrl;

      final optimisticDoses = _buildOptimisticDoses(
        dosageDisplay: dosageDisplay,
        pillImageUrl: pillImageUrl,
      );
      widget.onOptimisticDoses?.call(optimisticDoses);

      MedicationSchedule? savedSchedule;

      if (_existingSchedule != null) {
        savedSchedule = await ScheduleService.instance.updateSchedule(
          id: _existingSchedule!.id,
          medicationId: widget.medicationId,
          medicationName: widget.medicationName,
          dosageDisplay: dosageDisplay,
          patientId: _resolvedPatientId,
          frequencyType: _frequencyType,
          scheduledTimes:
          (_frequencyType == 'daily' || _frequencyType == 'multiple_daily')
              ? _times
              : null,
          intervalHours:
          _frequencyType == 'every_x_hours' ? _intervalHours : null,
          scheduledDays: _selectedDays.length == 7 ? null : _selectedDays,
          escalationEnabled: _escalationEnabled,
          pillImageUrl: pillImageUrl,
        );
      } else {
        savedSchedule = await ScheduleService.instance.addSchedule(
          medicationId: widget.medicationId,
          medicationName: widget.medicationName,
          dosageDisplay: dosageDisplay,
          patientId: _resolvedPatientId,
          frequencyType: _frequencyType,
          scheduledTimes:
          (_frequencyType == 'daily' || _frequencyType == 'multiple_daily')
              ? _times
              : null,
          intervalHours:
          _frequencyType == 'every_x_hours' ? _intervalHours : null,
          scheduledDays: _selectedDays.length == 7 ? null : _selectedDays,
          escalationEnabled: _escalationEnabled,
          pillImageUrl: pillImageUrl,
        );
      }

      if (savedSchedule != null) {
        await LocalCacheService.instance.cacheSchedule(savedSchedule);
      }

      if (!mounted) return;

      setState(() {
        _scheduleSaved = true;
        _hasUnsavedChanges = false;
        _originalSchedule = savedSchedule;
      });

      AppSnackbar.success(
        context,
        _existingSchedule != null
            ? 'Schedule updated for ${widget.patientName}!'
            : 'Schedule saved for ${widget.patientName}!',
      );

      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) Navigator.pop(context, true);
      widget.onSaveCompleted?.call();
    } catch (e, stack) {
      debugPrint('❌ Save schedule error: $e');
      debugPrint('$stack');

      final exists = await _checkIfScheduleExists();

      if (exists) {
        if (!mounted) return;
        setState(() {
          _scheduleSaved = true;
          _hasUnsavedChanges = false;
        });

        AppSnackbar.success(context, 'Schedule saved for ${widget.patientName}!');
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.pop(context, true);
        widget.onSaveCompleted?.call();
      } else {
        if (!mounted) return;
        setState(() => _isSaving = false);
        AppSnackbar.error(context, 'Failed to save schedule. Please try again.');
        widget.onSaveFailed?.call('Failed to save schedule. Please try again.');
      }
    }
  }

  Future<bool> _checkIfScheduleExists() async {
    try {
      final schedules = await ScheduleService.instance.getSchedulesForMedication(
        widget.medicationId,
        patientId: _resolvedPatientId,
      );
      return schedules.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking schedule existence: $e');
      return false;
    }
  }

  Future<bool> _handleBackButton() async {
    if (_isSaving) {
      AppSnackbar.warning(context, 'Please wait for save to complete');
      return false;
    }

    if (_hasUnsavedChanges) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
            'You have unsaved changes. Do you want to discard them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      return shouldDiscard ?? false;
    }

    return true;
  }

  Widget _buildUnsavedNotice() {
    if (!_hasUnsavedChanges) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You have unsaved changes. Tap save to apply them.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUnsavedNotice(),
            AppButton(
              label: _isSaving
                  ? 'Saving...'
                  : (_existingSchedule != null
                  ? 'Update Schedule'
                  : 'Save Schedule'),
              icon: _isSaving ? null : Icons.check_rounded,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _saveSchedule,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.person_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Schedule for',
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
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.medication_rounded, color: AppColors.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.medicationName, style: AppTextStyles.titleMedium),
                  if (_existingSchedule != null)
                    Text(
                      'Existing schedule',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (_existingSchedule != null)
              Icon(
                Icons.edit_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),

      if (_frequencyType != 'as_needed' &&
          _frequencyType != 'every_x_hours') ...[
        _SectionHeader(
          icon: Icons.flash_on_rounded,
          title: 'Quick Setup',
          subtitle: 'Tap to apply a common schedule',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _schedulePresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = _schedulePresets[index];
              return _PresetCard(
                name: preset.name,
                description: preset.description,
                onTap: () => _applyPreset(preset),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],

      _SectionHeader(icon: Icons.repeat_rounded, title: 'How often?'),
      const SizedBox(height: 12),

      _FrequencyOption(
        label: 'Once a day',
        description: 'One dose per day',
        icon: Icons.wb_sunny_outlined,
        selected: _frequencyType == 'daily',
        onTap: () {
          _markAsChanged();
          setState(() {
            _frequencyType = 'daily';
            if (_times.length > 1) _times = [_times.first];
            if (_times.isEmpty) {
              _times = [const TimeOfDay(hour: 8, minute: 0)];
            }
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
          _markAsChanged();
          setState(() => _frequencyType = 'multiple_daily');
        },
      ),
      const SizedBox(height: 8),

      _FrequencyOption(
        label: 'Every X hours',
        description: 'Strict interval spacing',
        icon: Icons.timer_outlined,
        selected: _frequencyType == 'every_x_hours',
        onTap: () {
          _markAsChanged();
          setState(() => _frequencyType = 'every_x_hours');
        },
      ),
      const SizedBox(height: 8),

      _FrequencyOption(
        label: 'As needed',
        description: 'No fixed schedule',
        icon: Icons.medical_services_outlined,
        selected: _frequencyType == 'as_needed',
        onTap: () {
          _markAsChanged();
          setState(() => _frequencyType = 'as_needed');
        },
      ),

      if (_frequencyType == 'daily' || _frequencyType == 'multiple_daily') ...[
        const SizedBox(height: 24),
        _SectionHeader(
          icon: Icons.access_time_rounded,
          title: 'Reminder times',
          subtitle: '${_times.length} ${_times.length == 1 ? "time" : "times"} set',
        ),
        const SizedBox(height: 12),

        if (_frequencyType == 'multiple_daily' || _times.length < 2) ...[
          Text(
            'Quick add',
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timePresets.map((preset) {
              final alreadyAdded = _times.any(
                    (t) =>
                t.hour == preset.time.hour &&
                    t.minute == preset.time.minute,
              );

              return _TimePresetChip(
                label: preset.label,
                icon: preset.icon,
                time: preset.time,
                disabled: alreadyAdded,
                onTap: alreadyAdded ? null : () => _addTimePreset(preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        if (_times.isNotEmpty) ...[
          Text(
            'Selected times',
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ..._times.asMap().entries.map(
                (entry) => _TimeSlotTile(
              time: entry.value,
              canRemove:
              _times.length > 1 || _frequencyType == 'multiple_daily',
              onTap: () => _pickCustomTime(replaceIndex: entry.key),
              onRemove: () {
                _markAsChanged();
                setState(() => _times.removeAt(entry.key));
              },
            ),
          ),
        ],

        if (_frequencyType == 'multiple_daily' || _times.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _pickCustomTime,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add custom time'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
      ],

      if (_frequencyType == 'every_x_hours') ...[
        const SizedBox(height: 24),
        _SectionHeader(
          icon: Icons.timer_outlined,
          title: 'Interval',
          subtitle: 'Every ${_intervalHours.toInt()} hours',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_intervalHours.toInt()}',
                    style: AppTextStyles.h1.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'hours',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _intervalHours,
                min: 1,
                max: 24,
                divisions: 23,
                label: '${_intervalHours.toInt()}h',
                onChanged: (value) {
                  _markAsChanged();
                  setState(() => _intervalHours = value);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1h', style: AppTextStyles.bodySmall),
                  Text('24h', style: AppTextStyles.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ],

      if (_frequencyType != 'as_needed') ...[
        const SizedBox(height: 24),
        _SectionHeader(
          icon: Icons.calendar_today_rounded,
          title: 'Which days?',
          subtitle: _selectedDays.length == 7
              ? 'Every day'
              : '${_selectedDays.length} ${_selectedDays.length == 1 ? "day" : "days"} selected',
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _DayQuickChip(
                label: 'All days',
                selected: _selectedDays.length == 7,
                onTap: _selectAllDays,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DayQuickChip(
                label: 'Weekdays',
                selected: _selectedDays.length == 5 &&
                    _selectedDays.every((d) => d >= 1 && d <= 5),
                onTap: _selectWeekdays,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DayQuickChip(
                label: 'Weekends',
                selected: _selectedDays.length == 2 &&
                    _selectedDays.contains(0) &&
                    _selectedDays.contains(6),
                onTap: _selectWeekends,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            final selected = _selectedDays.contains(index);

            return InkWell(
              onTap: () {
                _markAsChanged();
                setState(() {
                  if (selected) {
                    if (_selectedDays.length > 1) _selectedDays.remove(index);
                  } else {
                    _selectedDays.add(index);
                  }
                });
              },
              borderRadius: BorderRadius.circular(50),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                      : null,
                ),
                child: Text(
                  _weekdays[index],
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }),
        ),
      ],

      const SizedBox(height: 28),

      if (_frequencyType != 'as_needed' &&
          (_times.isNotEmpty || _frequencyType == 'every_x_hours'))
        _ScheduleSummary(
          frequencyType: _frequencyType,
          times: _times,
          intervalHours: _intervalHours,
          selectedDays: _selectedDays,
          weekdays: _weekdays,
        ),

      const SizedBox(height: 24),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('Set Schedule')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('Set Schedule')),
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

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Set Schedule')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading schedule...'),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _handleBackButton();
          if (shouldPop && mounted) {
            Navigator.pop(context, _scheduleSaved);
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            _existingSchedule != null ? 'Edit Schedule' : 'Set Schedule',
          ),
          actions: [
            if (_hasUnsavedChanges && !_isSaving)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Unsaved',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                if (_hasUnsavedChanges) {
                  final shouldDiscard = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Skip Scheduling?'),
                      content: const Text(
                        'Your changes will be lost. Continue?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                  );

                  if (shouldDiscard == true && mounted) {
                    Navigator.pop(context, _scheduleSaved);
                  }
                } else {
                  Navigator.pop(context, _scheduleSaved);
                }
              },
              child: const Text('Skip'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: _buildContent(),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
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
            color: AppColors.primary.withValues(alpha: 0.15),
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
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final String name;
  final String description;
  final VoidCallback onTap;

  const _PresetCard({
    required this.name,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.15),
              AppColors.primary.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              name,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePresetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final TimeOfDay time;
  final bool disabled;
  final VoidCallback? onTap;

  const _TimePresetChip({
    required this.label,
    required this.icon,
    required this.time,
    required this.disabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: disabled ? AppColors.surfaceVariant : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: disabled
                ? AppColors.border
                : AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: disabled
                  ? AppColors.textSecondary
                  : AppColors.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: disabled
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              time.format(context),
              style: AppTextStyles.labelSmall.copyWith(
                color:
                disabled ? AppColors.textSecondary : AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (disabled) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayQuickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DayQuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? AppColors.secondary : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ScheduleSummary extends StatelessWidget {
  final String frequencyType;
  final List<TimeOfDay> times;
  final double intervalHours;
  final List<int> selectedDays;
  final List<String> weekdays;

  const _ScheduleSummary({
    required this.frequencyType,
    required this.times,
    required this.intervalHours,
    required this.selectedDays,
    required this.weekdays,
  });

  String _buildSummary(BuildContext context) {
    final buffer = StringBuffer();

    if (frequencyType == 'every_x_hours') {
      buffer.write('Every ${intervalHours.toInt()} hours');
    } else if (times.length == 1) {
      buffer.write('Once daily at ${times.first.format(context)}');
    } else {
      buffer.write('${times.length} times daily at ');
      buffer.write(times.map((t) => t.format(context)).join(', '));
    }

    if (selectedDays.length == 7) {
      buffer.write(' • Every day');
    } else if (selectedDays.length == 5 &&
        selectedDays.every((d) => d >= 1 && d <= 5)) {
      buffer.write(' • Weekdays');
    } else if (selectedDays.length == 2 &&
        selectedDays.contains(0) &&
        selectedDays.contains(6)) {
      buffer.write(' • Weekends');
    } else {
      final sortedDays = List<int>.from(selectedDays)..sort();
      buffer.write(' • ${sortedDays.map((d) => weekdays[d]).join(', ')}');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Schedule Summary',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildSummary(context),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.titleSmall.copyWith(
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

  IconData get _timeIcon {
    final hour = time.hour;
    if (hour >= 5 && hour < 12) return Icons.wb_sunny_rounded;
    if (hour >= 12 && hour < 17) return Icons.wb_sunny_outlined;
    if (hour >= 17 && hour < 21) return Icons.wb_twilight_rounded;
    return Icons.bedtime_rounded;
  }

  String get _timeLabel {
    final hour = time.hour;
    if (hour >= 5 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 21) return 'Evening';
    return 'Night';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _timeIcon,
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
                      time.format(context),
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _timeLabel,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                onPressed: onTap,
                tooltip: 'Change time',
              ),
              if (canRemove)
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                  onPressed: onRemove,
                  tooltip: 'Remove',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimePreset {
  final String label;
  final IconData icon;
  final TimeOfDay time;

  const _TimePreset(this.label, this.icon, this.time);
}

class _SchedulePreset {
  final String name;
  final String description;
  final List<TimeOfDay> times;

  const _SchedulePreset(this.name, this.description, this.times);
}