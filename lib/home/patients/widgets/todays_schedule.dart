// lib/screens/home/patients/widgets/todays_schedule.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../localization/app_localizations.dart';
import '../../../services/auth_service.dart';
import '../../../services/dose_log_service.dart';
import '../../../services/schedule_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/loaders/skeleton_loader.dart';
import '../../../widgets/snackbar/app_snackbar.dart';
import '../medication_reminder_scanner_screen.dart';

class TodaysSchedule extends StatefulWidget {
  final VoidCallback onAddPressed;
  final VoidCallback? onViewAllPressed;
  final int maxDoses;
  final void Function(TodayDose dose)? onDoseTaken;

  const TodaysSchedule({
    super.key,
    required this.onAddPressed,
    this.onViewAllPressed,
    this.onDoseTaken,
    this.maxDoses = 0,
  });

  @override
  State<TodaysSchedule> createState() =>
      TodaysScheduleState();
}

class TodaysScheduleState extends State<TodaysSchedule> {
  final Set<String> _loggedKeys = <String>{};

  late final PageController _pageController;

  List<TodayDose> _allDoses = <TodayDose>[];

  bool _isLoading = true;
  String? _error;
  int _currentDoseIndex = 0;

  RealtimeChannel? _scheduleChannel;
  RealtimeChannel? _doseLogChannel;

  Timer? _realtimeDebounce;
  bool _realtimeReloadInProgress = false;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(
      viewportFraction: 0.88,
    );

    load();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();

    final scheduleChannel = _scheduleChannel;
    if (scheduleChannel != null) {
      unawaited(
        Supabase.instance.client.removeChannel(
          scheduleChannel,
        ),
      );
    }

    final doseLogChannel = _doseLogChannel;
    if (doseLogChannel != null) {
      unawaited(
        Supabase.instance.client.removeChannel(
          doseLogChannel,
        ),
      );
    }

    _pageController.dispose();

    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // REALTIME
  // ══════════════════════════════════════════════════════════════

  void _subscribeToRealtime() {
    final patientId =
        AuthService.instance.currentUser?.id;

    if (patientId == null ||
        patientId.trim().isEmpty) {
      debugPrint(
        '⚠️ TodaysSchedule: no patient ID; '
            'Realtime was not subscribed',
      );
      return;
    }

    try {
      _scheduleChannel = Supabase.instance.client
          .channel(
        'todays_schedule_$patientId',
      )
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'medication_schedules',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'patient_id',
          value: patientId,
        ),
        callback: (payload) {
          debugPrint(
            '📡 Schedule change received: '
                '${payload.eventType}',
          );

          _queueRealtimeReload();
        },
      )
          .subscribe(
            (status, error) {
          debugPrint(
            '📡 Schedule Realtime status: '
                '$status'
                '${error == null ? '' : ' — $error'}',
          );
        },
      );

      _doseLogChannel = Supabase.instance.client
          .channel(
        'todays_dose_logs_$patientId',
      )
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'dose_logs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'patient_id',
          value: patientId,
        ),
        callback: (payload) {
          debugPrint(
            '📡 Dose-log change received: '
                '${payload.eventType}',
          );

          _queueRealtimeReload();
        },
      )
          .subscribe(
            (status, error) {
          debugPrint(
            '📡 Dose-log Realtime status: '
                '$status'
                '${error == null ? '' : ' — $error'}',
          );
        },
      );
    } catch (error, stack) {
      debugPrint(
        '❌ TodaysSchedule Realtime error: $error',
      );
      debugPrint('$stack');
    }
  }

  void _queueRealtimeReload() {
    if (!mounted) return;

    _realtimeDebounce?.cancel();

    _realtimeDebounce = Timer(
      const Duration(milliseconds: 350),
          () {
        if (!mounted ||
            _realtimeReloadInProgress) {
          return;
        }

        unawaited(
          _reloadAfterRealtimeEvent(),
        );
      },
    );
  }

  Future<void> _reloadAfterRealtimeEvent() async {
    if (_realtimeReloadInProgress) return;

    _realtimeReloadInProgress = true;

    try {
      // Silent reload keeps the current schedule visible while refreshing.
      await load(silent: true);
    } finally {
      _realtimeReloadInProgress = false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LOAD SCHEDULES
  // ══════════════════════════════════════════════════════════════

  Future<void> load({
    bool silent = false,
  }) async {
    if (mounted && !silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final today = DateTime.now();

      final results = await Future.wait<Object>([
        ScheduleService.instance.getDosesForDate(today),
        DoseLogService.instance.getLoggedDoseKeys(today),
      ]);

      final doses =
      List<TodayDose>.from(
        results[0] as List<TodayDose>,
      );

      final loggedKeys =
      Set<String>.from(
        results[1] as Set<String>,
      );

      doses.sort(
            (first, second) =>
            first.scheduledTime.compareTo(
              second.scheduledTime,
            ),
      );

      if (!mounted) return;

      setState(() {
        /*
         * Preserve optimistic doses during a silent realtime reload if
         * the database has not returned them yet.
         */
        final pendingDoses = _allDoses
            .where((dose) => dose.isPending)
            .toList();

        _allDoses = <TodayDose>[
          ...doses,
          ...pendingDoses.where(
                (pending) => !doses.any(
                  (saved) =>
              saved.medicationId ==
                  pending.medicationId &&
                  saved.scheduledTime
                      .isAtSameMomentAs(
                    pending.scheduledTime,
                  ),
            ),
          ),
        ];

        _loggedKeys
          ..clear()
          ..addAll(loggedKeys);

        _normalizeCurrentIndex(
          _displayDoses.length,
        );

        _isLoading = false;
        _error = null;
      });

      _jumpToCurrentPage();

      debugPrint(
        '✅ TodaysSchedule loaded '
            '${_allDoses.length} dose(s)',
      );
    } catch (error, stack) {
      debugPrint(
        '❌ TodaysSchedule.load() failed: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _error = 'Could not load schedule';
        _isLoading = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  // OPTIMISTIC DOSE SUPPORT
  // ══════════════════════════════════════════════════════════════

  void addOptimisticDoses(
      List<TodayDose> doses,
      ) {
    if (!mounted || doses.isEmpty) return;

    setState(() {
      for (final newDose in doses) {
        _allDoses.removeWhere(
              (existing) =>
          existing.isPending &&
              existing.medicationId ==
                  newDose.medicationId &&
              existing.scheduledTime
                  .isAtSameMomentAs(
                newDose.scheduledTime,
              ),
        );
      }

      _allDoses.addAll(doses);

      _allDoses.sort(
            (first, second) =>
            first.scheduledTime.compareTo(
              second.scheduledTime,
            ),
      );

      _normalizeCurrentIndex(
        _displayDoses.length,
      );
    });

    _jumpToCurrentPage();
  }

  void confirmOptimisticDoses() {
    unawaited(
      load(silent: true),
    );
  }

  void removeOptimisticDoses(
      String medicationId,
      String errorMessage,
      ) {
    if (!mounted) return;

    setState(() {
      _allDoses.removeWhere(
            (dose) =>
        dose.isPending &&
            dose.medicationId == medicationId,
      );

      _normalizeCurrentIndex(
        _displayDoses.length,
      );
    });

    AppSnackbar.error(
      context,
      errorMessage,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DOSE HELPERS
  // ══════════════════════════════════════════════════════════════

  void _normalizeCurrentIndex(int itemCount) {
    if (itemCount <= 0) {
      _currentDoseIndex = 0;
      return;
    }

    if (_currentDoseIndex >= itemCount) {
      _currentDoseIndex = itemCount - 1;
    }

    if (_currentDoseIndex < 0) {
      _currentDoseIndex = 0;
    }
  }

  void _jumpToCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_pageController.hasClients) {
        return;
      }

      try {
        _pageController.jumpToPage(
          _currentDoseIndex,
        );
      } catch (_) {}
    });
  }

  String _doseKey(TodayDose dose) {
    final time = dose.scheduledTime;

    return '${dose.scheduleId}|'
        '${time.year}-'
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}T'
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  bool _isDoseTaken(TodayDose dose) {
    return _loggedKeys.contains(
      _doseKey(dose),
    );
  }

  bool _isDoseDue(TodayDose dose) {
    return !DateTime.now().isBefore(
      dose.scheduledTime,
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute =
    dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
    hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '$displayHour:$minute $period';
  }

  List<TodayDose> get _displayDoses {
    final doses = _allDoses
        .where((dose) => !_isDoseTaken(dose))
        .toList();

    doses.sort(
          (first, second) =>
          first.scheduledTime.compareTo(
            second.scheduledTime,
          ),
    );

    return doses;
  }

  // ══════════════════════════════════════════════════════════════
  // OPEN DOSE
  // ══════════════════════════════════════════════════════════════

  Future<void> _openDose(
      TodayDose dose,
      ) async {
    if (dose.isPending) {
      AppSnackbar.error(
        context,
        'This dose is still being saved. Please wait…',
      );
      return;
    }

    final localization =
    AppLocalizations.of(context);

    if (!_isDoseDue(dose)) {
      AppSnackbar.error(
        context,
        localization.t(
          'notDueSnackbar',
          <String, String>{
            'time': _formatTime(
              dose.scheduledTime,
            ),
          },
        ),
      );
      return;
    }

    final result =
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) =>
            MedicationReminderScannerScreen(
              dose: dose,
            ),
      ),
    );

    if (result != true || !mounted) {
      return;
    }

    setState(() {
      _loggedKeys.add(
        _doseKey(dose),
      );

      _normalizeCurrentIndex(
        _displayDoses.length,
      );
    });

    _jumpToCurrentPage();

    widget.onDoseTaken?.call(dose);
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _ScheduleSkeleton();
    }

    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: () => load(),
      );
    }

    if (_allDoses.isEmpty) {
      return _EmptySchedule(
        onAddPressed: widget.onAddPressed,
      );
    }

    final displayDoses = _displayDoses;

    if (displayDoses.isEmpty ||
        _allDoses.every(_isDoseTaken)) {
      return _AllDoneCard(
        count: _allDoses.length,
      );
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 420,
          child: PageView.builder(
            controller: _pageController,
            itemCount: displayDoses.length,
            padEnds: false,
            onPageChanged: (index) {
              if (!mounted) return;

              setState(() {
                _currentDoseIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final dose = displayDoses[index];

              return Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 6,
                  right: 8,
                ),
                child: _DoseTile(
                  dose: dose,
                  isDue: _isDoseDue(dose),
                  onTap: () => _openDose(dose),
                ),
              );
            },
          ),
        ),
        if (displayDoses.length > 1) ...[
          const SizedBox(height: 14),
          _CarouselIndicator(
            itemCount: displayDoses.length,
            currentIndex: _currentDoseIndex,
          ),
          const SizedBox(height: 7),
          Text(
            '${_currentDoseIndex + 1} of '
                '${displayDoses.length}',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DOSE CARD
// ══════════════════════════════════════════════════════════════

class _DoseTile extends StatelessWidget {
  final TodayDose dose;
  final bool isDue;
  final VoidCallback onTap;

  const _DoseTile({
    required this.dose,
    required this.isDue,
    required this.onTap,
  });

  bool get _hasImage {
    return dose.pillImageUrl != null &&
        dose.pillImageUrl!.trim().isNotEmpty;
  }

  Color get _statusColor {
    if (dose.isPending) {
      return AppColors.warning;
    }

    if (dose.isPast) {
      return AppColors.error;
    }

    if (dose.isDueSoon) {
      return AppColors.warning;
    }

    return AppColors.primary;
  }

  String _statusLabel(
      AppLocalizations localization,
      ) {
    if (dose.isPending) {
      return 'Saving…';
    }

    if (dose.isPast) {
      return localization.t('overdue');
    }

    if (dose.isDueSoon) {
      return localization.t('dueSoon');
    }

    return localization.t('upcoming');
  }

  String get _timeText {
    final hour = dose.scheduledTime.hour;
    final minute =
    dose.scheduledTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
    hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final localization =
    AppLocalizations.of(context);

    return Opacity(
      opacity: dose.isPending ? 0.72 : 1,
      child: Material(
        color: AppColors.surface,
        elevation: isDue && !dose.isPending ? 3 : 1,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _statusColor.withValues(
                  alpha: dose.isPending ? 0.55 : 0.35,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _DoseImage(
                        imageUrl: dose.pillImageUrl,
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _StatusBadge(
                          label: _statusLabel(
                            localization,
                          ),
                          color: _statusColor,
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor:
                          Colors.white.withValues(
                            alpha: 0.90,
                          ),
                          child: Icon(
                            _hasImage
                                ? Icons.image_rounded
                                : Icons.medication_rounded,
                            size: 18,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      14,
                      16,
                      6,
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          dose.medicationName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium
                              .copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dose.dosageDisplay,
                                style: AppTextStyles.titleMedium
                                    .copyWith(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              _timeText,
                              style: AppTextStyles.bodySmall
                                  .copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    14,
                  ),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: dose.isPending
                          ? AppColors.warning.withValues(
                        alpha: 0.10,
                      )
                          : isDue
                          ? AppColors.primary.withValues(
                        alpha: 0.13,
                      )
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: dose.isPending
                        ? Row(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Saving…',
                          style: AppTextStyles.bodySmall
                              .copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                        : Row(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        Icon(
                          isDue
                              ? Icons.touch_app_rounded
                              : Icons.lock_clock_rounded,
                          size: 17,
                          color: isDue
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          isDue
                              ? localization.t(
                            'tapToMarkTaken',
                          )
                              : localization.t(
                            'availableAt',
                            <String, String>{
                              'time': _timeText,
                            },
                          ),
                          style: AppTextStyles.bodySmall
                              .copyWith(
                            color: isDue
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
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
}

// ══════════════════════════════════════════════════════════════
// IMAGE
// ══════════════════════════════════════════════════════════════

class _DoseImage extends StatelessWidget {
  final String? imageUrl;

  const _DoseImage({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();

    if (url == null || url.isEmpty) {
      return const _FallbackDoseImage();
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        return const _FallbackDoseImage();
      },
      loadingBuilder: (
          context,
          child,
          progress,
          ) {
        if (progress == null) {
          return child;
        }

        return const ColoredBox(
          color: AppColors.surfaceVariant,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FallbackDoseImage extends StatelessWidget {
  const _FallbackDoseImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.medication_rounded,
          size: 76,
          color: AppColors.secondary,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CAROUSEL INDICATOR
// ══════════════════════════════════════════════════════════════

class _CarouselIndicator extends StatelessWidget {
  final int itemCount;
  final int currentIndex;

  const _CarouselIndicator({
    required this.itemCount,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        itemCount,
            (index) {
          final selected = index == currentIndex;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: selected ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary
                  : AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STATES
// ══════════════════════════════════════════════════════════════

class _AllDoneCard extends StatelessWidget {
  final int count;

  const _AllDoneCard({
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.40),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 48,
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            loc.t('allDoneTitle'),
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            loc.t(
              'allDoneBody',
              <String, String>{
                'count': '$count',
              },
            ),
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  final VoidCallback onAddPressed;

  const _EmptySchedule({
    required this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.event_note_rounded,
            size: 52,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            loc.t('nothingScheduled'),
            style: AppLocalizations.of(context) != null
                ? AppTextStyles.titleMedium
                : AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.add_rounded),
            label: Text(loc.t('addMedication')),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 42,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ScheduleSkeleton extends StatelessWidget {
  const _ScheduleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SkeletonBox(
          height: 400,
          borderRadius: 18,
        ),
        const SizedBox(height: 12),
        SkeletonBox(
          height: 8,
          width: 70,
          borderRadius: 10,
        ),
      ],
    );
  }
}