// lib/screens/home/patients/widgets/todays_schedule.dart

import 'package:flutter/material.dart';

import '../../../localization/app_localizations.dart';
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
  final Set<String> _loggedKeys = {};
  late final PageController _pageController;

  List<TodayDose> _allDoses = [];

  bool _isLoading = true;
  String? _error;
  int _currentDoseIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // LOAD FROM DATABASE
  // ══════════════════════════════════════════════════════════════

  Future<void> load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final today = DateTime.now();

      final results = await Future.wait([
        ScheduleService.instance.getDosesForDate(today),
        DoseLogService.instance.getLoggedDoseKeys(today),
      ]);

      final doses = results[0] as List<TodayDose>;
      final loggedKeys = results[1] as Set<String>;

      doses.sort(
            (a, b) =>
            a.scheduledTime.compareTo(b.scheduledTime),
      );

      final remainingCount = doses
          .where((d) => !loggedKeys.contains(_doseKey(d)))
          .length;

      if (!mounted) return;

      setState(() {
        _allDoses = doses;
        _loggedKeys
          ..clear()
          ..addAll(loggedKeys);
        _normalizeCurrentIndex(remainingCount);
        _isLoading = false;
      });

      _jumpToCurrentPage();
    } catch (e, st) {
      debugPrint('❌ TodaysSchedule.load() failed: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _error = 'Could not load schedule';
        _isLoading = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  // OPTIMISTIC DOSE MANAGEMENT
  // ══════════════════════════════════════════════════════════════

  /// Immediately adds doses to the UI with `isPending = true`.
  /// Called right after the user taps Save, before the DB write.
  void addOptimisticDoses(List<TodayDose> doses) {
    if (!mounted) return;

    setState(() {
      // Remove any previous optimistic doses for the same
      // medication so we don't duplicate.
      _allDoses.removeWhere(
            (existing) =>
        existing.isPending &&
            doses.any(
                  (newDose) =>
              newDose.medicationId ==
                  existing.medicationId,
            ),
      );

      _allDoses.addAll(doses);

      _allDoses.sort(
            (a, b) =>
            a.scheduledTime.compareTo(b.scheduledTime),
      );

      _normalizeCurrentIndex(
        _displayDoses.length,
      );
    });

    _jumpToCurrentPage();
  }

  /// Replaces optimistic doses with real data from the database
  /// after the background save completes.
  void confirmOptimisticDoses() {
    // Reload from database to get the real schedule IDs and data.
    load();
  }

  /// Removes optimistic doses if the background save fails.
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

      _normalizeCurrentIndex(_displayDoses.length);
    });

    AppSnackbar.error(context, errorMessage);
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════

  void _normalizeCurrentIndex(int itemCount) {
    if (itemCount <= 0) {
      _currentDoseIndex = 0;
      return;
    }

    if (_currentDoseIndex >= itemCount) {
      _currentDoseIndex = itemCount - 1;
    }

    if (_currentDoseIndex < 0) _currentDoseIndex = 0;
  }

  void _jumpToCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;

      try {
        _pageController.jumpToPage(_currentDoseIndex);
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

  bool _isDoseTaken(TodayDose dose) =>
      _loggedKeys.contains(_doseKey(dose));

  bool _isDoseDue(TodayDose dose) =>
      !DateTime.now().isBefore(dose.scheduledTime);

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute =
    dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
    hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  Future<void> _openDose(TodayDose dose) async {
    // Pending doses cannot be confirmed yet.
    if (dose.isPending) {
      AppSnackbar.error(
        context,
        'This dose is still being saved. Please wait…',
      );
      return;
    }

    final localization = AppLocalizations.of(context);

    if (!_isDoseDue(dose)) {
      AppSnackbar.error(
        context,
        localization.t(
          'notDueSnackbar',
          {'time': _formatTime(dose.scheduledTime)},
        ),
      );
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            MedicationReminderScannerScreen(dose: dose),
      ),
    );

    if (result != true || !mounted) return;

    setState(() {
      _loggedKeys.add(_doseKey(dose));
      _normalizeCurrentIndex(
        _allDoses
            .where((item) => !_isDoseTaken(item))
            .length,
      );
    });

    _jumpToCurrentPage();
    widget.onDoseTaken?.call(dose);
  }

  List<TodayDose> get _displayDoses {
    final untaken = _allDoses
        .where((dose) => !_isDoseTaken(dose))
        .toList();

    untaken.sort(
          (a, b) =>
          a.scheduledTime.compareTo(b.scheduledTime),
    );

    return untaken;
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _ScheduleSkeleton();

    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: load,
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
      return _AllDoneCard(count: _allDoses.length);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 420,
          child: PageView.builder(
            controller: _pageController,
            itemCount: displayDoses.length,
            padEnds: false,
            onPageChanged: (index) {
              if (!mounted) return;
              setState(() => _currentDoseIndex = index);
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
    final url = dose.pillImageUrl;
    return url != null && url.trim().isNotEmpty;
  }

  bool get _hasDifferentGenericName {
    return dose.genericName.trim().toLowerCase() !=
        dose.medicationName.trim().toLowerCase();
  }

  Color get _medColor {
    switch (dose.pillColor?.toLowerCase()) {
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

  IconData get _fallbackIcon {
    switch (dose.dosageUnit.toLowerCase()) {
      case 'ml':
        return Icons.medication_liquid_rounded;
      case 'units':
        return Icons.vaccines_rounded;
      default:
        return Icons.medication_rounded;
    }
  }

  Color get _statusColor {
    if (dose.isPending) return AppColors.warning;
    if (dose.isPast) return AppColors.error;
    if (dose.isDueSoon) return AppColors.warning;
    return AppColors.primary;
  }

  String _statusLabel(AppLocalizations loc) {
    if (dose.isPending) return 'Saving…';
    if (dose.isPast) return loc.t('overdue');
    if (dose.isDueSoon) return loc.t('dueSoon');
    return loc.t('upcoming');
  }

  String get _timeText {
    final hour = dose.scheduledTime.hour;
    final minute = dose.scheduledTime.minute
        .toString()
        .padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
    hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Opacity(
      // Pending doses are slightly faded to indicate they are saving.
      opacity: dose.isPending ? 0.72 : 1.0,
      child: Material(
        color: AppColors.surface,
        elevation: isDue && !dose.isPending ? 3 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: dose.isPending
                    ? AppColors.warning
                    .withValues(alpha: 0.50)
                    : dose.isPast
                    ? AppColors.error
                    .withValues(alpha: 0.35)
                    : dose.isDueSoon
                    ? AppColors.warning
                    .withValues(alpha: 0.45)
                    : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                // ────────────────────────────────────
                // MEDICINE IMAGE
                // ────────────────────────────────────
                SizedBox(
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _DoseImage(
                        imageUrl: dose.pillImageUrl,
                        fallbackColor: _medColor,
                        fallbackIcon: _fallbackIcon,
                      ),

                      // Gradient depth
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin:
                                Alignment.topCenter,
                                end: Alignment
                                    .bottomCenter,
                                colors: [
                                  Colors.black
                                      .withValues(
                                      alpha: 0.03),
                                  Colors.transparent,
                                  Colors.black
                                      .withValues(
                                      alpha: 0.22),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Status badge (top-left)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: dose.isPending
                            ? _PendingBadge()
                            : _DoseStatusBadge(
                          label:
                          _statusLabel(loc),
                          color: _statusColor,
                        ),
                      ),

                      // Image type icon (top-right)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withValues(alpha: 0.90),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(
                                    alpha: 0.10),
                                blurRadius: 6,
                                offset:
                                const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            _hasImage
                                ? Icons.image_rounded
                                : Icons
                                .medication_rounded,
                            size: 18,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ────────────────────────────────────
                // MEDICATION INFO
                // ────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 14, 16, 6),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          dose.medicationName,
                          style: AppTextStyles
                              .titleMedium
                              .copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_hasDifferentGenericName) ...[
                          const SizedBox(height: 3),
                          Text(
                            dose.genericName,
                            style: AppTextStyles
                                .bodySmall
                                .copyWith(
                              color:
                              AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow
                                .ellipsis,
                          ),
                        ],
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dose.dosageDisplay,
                                style: AppTextStyles
                                    .titleMedium
                                    .copyWith(
                                  color: AppColors
                                      .secondary,
                                  fontWeight:
                                  FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow
                                    .ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.access_time_rounded,
                              size: 16,
                              color:
                              AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _timeText,
                              style: AppTextStyles
                                  .bodySmall
                                  .copyWith(
                                color: AppColors
                                    .textSecondary,
                                fontWeight:
                                FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ────────────────────────────────────
                // ACTION AREA
                // ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      16, 8, 16, 14),
                  child: AnimatedContainer(
                    duration:
                    const Duration(milliseconds: 300),
                    height: 42,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12),
                    decoration: BoxDecoration(
                      color: dose.isPending
                          ? AppColors.warning
                          .withValues(alpha: 0.10)
                          : isDue
                          ? AppColors.primary
                          .withValues(alpha: 0.13)
                          : AppColors.surfaceVariant,
                      borderRadius:
                      BorderRadius.circular(12),
                      border: Border.all(
                        color: dose.isPending
                            ? AppColors.warning
                            .withValues(alpha: 0.35)
                            : isDue
                            ? AppColors.primary
                            .withValues(
                            alpha: 0.28)
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        if (dose.isPending) ...[
                          SizedBox(
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
                            'Saving to your schedule…',
                            style: AppTextStyles
                                .bodySmall
                                .copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else ...[
                          Icon(
                            isDue
                                ? Icons.touch_app_rounded
                                : Icons
                                .lock_clock_rounded,
                            size: 17,
                            color: isDue
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              isDue
                                  ? loc.t('tapToMarkTaken')
                                  : loc.t(
                                'availableAt',
                                {'time': _timeText},
                              ),
                              style: AppTextStyles
                                  .bodySmall
                                  .copyWith(
                                color: isDue
                                    ? AppColors.primary
                                    : AppColors
                                    .textSecondary,
                                fontWeight:
                                FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow:
                              TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
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
// PENDING BADGE (animated "Saving…" shimmer)
// ══════════════════════════════════════════════════════════════

class _PendingBadge extends StatefulWidget {
  @override
  State<_PendingBadge> createState() =>
      _PendingBadgeState();
}

class _PendingBadgeState extends State<_PendingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(
              alpha: 0.85 * _animation.value,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Saving…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MEDICINE IMAGE
// ══════════════════════════════════════════════════════════════

class _DoseImage extends StatelessWidget {
  final String? imageUrl;
  final Color fallbackColor;
  final IconData fallbackIcon;

  const _DoseImage({
    required this.imageUrl,
    required this.fallbackColor,
    required this.fallbackIcon,
  });

  bool get _hasImage =>
      imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasImage) {
      return _FallbackDoseImage(
        color: fallbackColor,
        icon: fallbackIcon,
      );
    }

    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;

        return Container(
          color: AppColors.surfaceVariant,
          child: const Center(
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
      errorBuilder: (_, __, ___) => _FallbackDoseImage(
        color: fallbackColor,
        icon: fallbackIcon,
      ),
    );
  }
}

class _FallbackDoseImage extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _FallbackDoseImage({
    required this.color,
    required this.icon,
  });

  bool get _isLight =>
      color == Colors.white ||
          color == Colors.yellow ||
          color == const Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _lighten(color, 0.10),
            color,
            _darken(color, 0.10),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 76,
          color: _isLight
              ? AppColors.secondary
              : Colors.white,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STATUS BADGE
// ══════════════════════════════════════════════════════════════

class _DoseStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _DoseStatusBadge({
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 10,
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
    return SizedBox(
      height: 10,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(itemCount, (index) {
            final selected = index == currentIndex;

            return AnimatedContainer(
              duration:
              const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              margin:
              const EdgeInsets.symmetric(horizontal: 4),
              width: selected ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// COLOR UTILITIES
// ══════════════════════════════════════════════════════════════

Color _lighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness(
      (hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor();
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness(
      (hsl.lightness - amount).clamp(0.0, 1.0))
      .toColor();
}

// ══════════════════════════════════════════════════════════════
// ALL DONE CARD
// ══════════════════════════════════════════════════════════════

class _AllDoneCard extends StatelessWidget {
  final int count;
  const _AllDoneCard({required this.count});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.20),
            AppColors.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary
              .withValues(alpha: 0.40),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 32,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            loc.t('allDoneTitle'),
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            loc.t('allDoneBody', {'count': '$count'}),
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════

class _EmptySchedule extends StatelessWidget {
  final VoidCallback onAddPressed;
  const _EmptySchedule({required this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 40,
        horizontal: 24,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_note_rounded,
              size: 36,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            loc.t('nothingScheduled'),
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            loc.t('nothingScheduledBody'),
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(loc.t('addMedication')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              backgroundColor: AppColors.primary
                  .withValues(alpha: 0.20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ERROR STATE
// ══════════════════════════════════════════════════════════════

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
          AppColors.error.withValues(alpha: 0.40),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 32,
            color: AppColors.error,
          ),
          const SizedBox(height: 8),
          Text(
            message.isNotEmpty
                ? message
                : loc.t('couldNotLoadSchedule'),
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 16,
            ),
            label: Text(loc.t('retry')),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SKELETON
// ══════════════════════════════════════════════════════════════

class _ScheduleSkeleton extends StatelessWidget {
  const _ScheduleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SkeletonBox(height: 400, borderRadius: 18),
        const SizedBox(height: 12),
        SkeletonBox(
            height: 8, width: 70, borderRadius: 10),
      ],
    );
  }
}