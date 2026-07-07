// lib/screens/home/patients/widgets/todays_schedule.dart

import 'package:flutter/material.dart';
import '../../../services/dose_log_service.dart';
import '../../../services/schedule_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/loaders/skeleton_loader.dart';
import '../../../widgets/snackbar/app_snackbar.dart';

class TodaysSchedule extends StatefulWidget {
  final VoidCallback onAddPressed;
  final VoidCallback? onViewAllPressed;

  /// Set to 2 for dashboard preview.
  /// Set to 0 or a negative number to show ALL remaining doses for today.
  final int maxDoses;

  /// Fires whenever a dose is marked taken so dashboard/stat cards can update.
  final void Function(TodayDose dose)? onDoseTaken;

  const TodaysSchedule({
    super.key,
    required this.onAddPressed,
    this.onViewAllPressed,
    this.onDoseTaken,
    this.maxDoses = 2,
  });

  @override
  State<TodaysSchedule> createState() => TodaysScheduleState();
}

class TodaysScheduleState extends State<TodaysSchedule> {
  List<TodayDose> _allDoses = [];
  Set<String> _loggedKeys = {};
  final Set<String> _pendingKeys = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
  }

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

      if (!mounted) return;

      setState(() {
        _allDoses = doses;
        _loggedKeys = loggedKeys;

        // If a dose was pending and now appears in logged keys, clear pending.
        _pendingKeys.removeWhere((key) => _loggedKeys.contains(key));

        _isLoading = false;
      });

      debugPrint('✅ TodaysSchedule loaded ${_allDoses.length} doses');
      debugPrint('✅ TodaysSchedule loaded ${_loggedKeys.length} logged keys');
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
  // IMPORTANT:
  // Use LOCAL time here, not UTC.
  //
  // Mobile devices use local time. Your ScheduleService creates TodayDose
  // times in local device time. DoseLogService should also convert DB
  // scheduled_for back to local time before generating logged keys.
  //
  // This makes Web and Mobile behave the same.
  // ══════════════════════════════════════════════════════════════
  String _doseKey(TodayDose dose) {
    final t = dose.scheduledTime;
    return '${dose.scheduleId}|'
        '${t.year}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}T'
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  bool _isDoseTaken(TodayDose dose) => _loggedKeys.contains(_doseKey(dose));

  bool _isDosePending(TodayDose dose) => _pendingKeys.contains(_doseKey(dose));

  Future<void> _confirmAndMarkTaken(TodayDose dose) async {
    if (_isDosePending(dose)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Confirm Dose',
                style: AppTextStyles.titleMedium,
              ),
            ),
          ],
        ),
        content: Text(
          'Mark "${dose.medicationName}" (${dose.dosageDisplay}) '
              'scheduled for ${_formatTime(dose.scheduledTime)} as taken?',
          style: AppTextStyles.bodyMedium,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.secondary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Yes, Taken'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _markTaken(dose);
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $p';
  }

  Future<void> _markTaken(TodayDose dose) async {
    final key = _doseKey(dose);

    if (mounted) {
      setState(() => _pendingKeys.add(key));
    }

    try {
      await DoseLogService.instance.markAsTaken(
        scheduleId: dose.scheduleId,
        medicationId: dose.medicationId,
        scheduledFor: dose.scheduledTime,
      );

      debugPrint('✅ Dose log write completed for "${dose.medicationName}"');
      debugPrint('✅ Local dose key: $key');

      if (!mounted) return;

      setState(() {
        _loggedKeys.add(key);
        _pendingKeys.remove(key);
      });

      // Fire callback BEFORE snackbar so dashboard updates immediately on mobile.
      widget.onDoseTaken?.call(dose);

      AppSnackbar.success(context, '${dose.medicationName} marked as taken ✓');
    } catch (e, st) {
      debugPrint('❌ Failed to mark "${dose.medicationName}" as taken: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() => _pendingKeys.remove(key));

      final errorDetail = e.toString().replaceFirst('Exception: ', '');
      final shortError = errorDetail.length > 120
          ? '${errorDetail.substring(0, 120)}...'
          : errorDetail;

      AppSnackbar.error(context, 'Failed to log dose: $shortError');
    }
  }

  List<TodayDose> get _displayDoses {
    final untaken = _allDoses.where((d) => !_isDoseTaken(d)).toList();

    // If maxDoses <= 0, show ALL today's remaining schedules.
    if (widget.maxDoses <= 0) {
      untaken.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      return untaken;
    }

    final upcoming = untaken.where((d) => !d.isPast).toList();
    final missed = untaken.where((d) => d.isPast).toList();

    upcoming.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    missed.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    if (upcoming.length >= widget.maxDoses) {
      return upcoming.take(widget.maxDoses).toList();
    }

    final remainingSlots = widget.maxDoses - upcoming.length;

    final combined = [
      ...missed.reversed.take(remainingSlots),
      ...upcoming,
    ];

    combined.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return combined;
  }

  int get _hiddenCount {
    if (widget.maxDoses <= 0) return 0;

    final untaken = _allDoses.where((d) => !_isDoseTaken(d)).length;
    return (untaken - _displayDoses.length).clamp(0, 999).toInt();
  }

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
      return _EmptySchedule(onAddPressed: widget.onAddPressed);
    }

    final allTaken = _allDoses.every(_isDoseTaken);
    if (allTaken) return _AllDoneCard(count: _allDoses.length);

    final displayDoses = _displayDoses;

    return Column(
      children: [
        ...displayDoses.map(
              (dose) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DoseTile(
              dose: dose,
              isPending: _isDosePending(dose),
              onMarkTaken: () => _confirmAndMarkTaken(dose),
            ),
          ),
        ),
        if (_hiddenCount > 0)
          _MoreDosesTile(
            count: _hiddenCount,
            onTap: widget.onViewAllPressed,
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DOSE TILE — Bottle or Tablet based on dosage unit
// ══════════════════════════════════════════════════════════════
class _DoseTile extends StatelessWidget {
  final TodayDose dose;
  final bool isPending;
  final VoidCallback onMarkTaken;

  const _DoseTile({
    required this.dose,
    required this.onMarkTaken,
    this.isPending = false,
  });

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

  _MedicationForm get _form {
    final unit = dose.dosageUnit.toLowerCase();

    if (unit == 'ml') return _MedicationForm.syrup;
    if (unit == 'tablets') return _MedicationForm.tablet;
    if (unit == 'units') return _MedicationForm.injection;

    return _MedicationForm.bottle;
  }

  String get _timeText {
    final h = dose.scheduledTime.hour;
    final m = dose.scheduledTime.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $p';
  }

  Color get _statusColor {
    if (dose.isPast) return AppColors.error;
    if (dose.isDueSoon) return AppColors.warning;
    return AppColors.primary;
  }

  String get _statusLabel {
    if (dose.isPast) return 'Overdue';
    if (dose.isDueSoon) return 'Due Soon';
    return 'Upcoming';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dose.isPast
              ? AppColors.error.withValues(alpha: 0.3)
              : dose.isDueSoon
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: _statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              _MedicationVisual(
                form: _form,
                color: _medColor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.medicationName,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dose.dosageDisplay,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _timeText,
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusLabel,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: _statusColor,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: isPending ? null : onMarkTaken,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.secondary,
                disabledBackgroundColor:
                AppColors.primary.withValues(alpha: 0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: isPending
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.secondary,
                ),
              )
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                isPending ? 'Logging...' : 'Mark as Taken',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MEDICATION FORM ENUM
// ══════════════════════════════════════════════════════════════
enum _MedicationForm { bottle, tablet, syrup, injection }

// ══════════════════════════════════════════════════════════════
// MEDICATION VISUAL DISPATCHER
// ══════════════════════════════════════════════════════════════
class _MedicationVisual extends StatelessWidget {
  final _MedicationForm form;
  final Color color;

  const _MedicationVisual({
    required this.form,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 56,
      child: CustomPaint(
        painter: switch (form) {
          _MedicationForm.bottle => _BottlePainter(color: color),
          _MedicationForm.tablet => _TabletPainter(color: color),
          _MedicationForm.syrup => _SyrupPainter(color: color),
          _MedicationForm.injection => _InjectionPainter(color: color),
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// COLOR UTILITIES
// ══════════════════════════════════════════════════════════════
Color _lighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

// ══════════════════════════════════════════════════════════════
// PILL BOTTLE
// ══════════════════════════════════════════════════════════════
class _BottlePainter extends CustomPainter {
  final Color color;

  const _BottlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h - 2),
        width: w * 0.85,
        height: 4,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.15, 0, w * 0.7, h * 0.15),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()..color = color,
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.18, h * 0.02, w * 0.15, h * 0.05),
        topLeft: const Radius.circular(2),
        bottomLeft: const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    canvas.drawRect(
      Rect.fromLTWH(w * 0.15, h * 0.15, w * 0.7, h * 0.05),
      Paint()..color = _darken(color, 0.15),
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.08, h * 0.2, w * 0.84, h * 0.78),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
        bottomLeft: const Radius.circular(8),
        bottomRight: const Radius.circular(8),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _lighten(color, 0.1),
            color,
            _darken(color, 0.1),
          ],
        ).createShader(Rect.fromLTWH(0, h * 0.2, w, h * 0.8)),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.15, h * 0.4, w * 0.7, h * 0.35),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.22, h * 0.5),
      Offset(w * 0.78, h * 0.5),
      linePaint,
    );

    canvas.drawLine(
      Offset(w * 0.22, h * 0.58),
      Offset(w * 0.68, h * 0.58),
      linePaint,
    );

    final rxPaint = Paint()
      ..color = _darken(color, 0.2)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.28, h * 0.65),
      Offset(w * 0.28, h * 0.72),
      rxPaint,
    );

    canvas.drawLine(
      Offset(w * 0.28, h * 0.65),
      Offset(w * 0.34, h * 0.65),
      rxPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.12, h * 0.22, w * 0.1, h * 0.7),
        topLeft: const Radius.circular(3),
        bottomLeft: const Radius.circular(6),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.4),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromLTWH(w * 0.12, h * 0.22, w * 0.1, h * 0.7),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _BottlePainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
// TABLET
// ══════════════════════════════════════════════════════════════
class _TabletPainter extends CustomPainter {
  final Color color;

  const _TabletPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h - 2),
        width: w * 0.9,
        height: 4,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    _drawTablet(
      canvas,
      Offset(w * 0.28, h * 0.30),
      w * 0.44,
      h * 0.30,
      color,
    );

    _drawTablet(
      canvas,
      Offset(w * 0.56, h * 0.42),
      w * 0.44,
      h * 0.30,
      color,
    );

    _drawTablet(
      canvas,
      Offset(w * 0.42, h * 0.58),
      w * 0.48,
      h * 0.34,
      color,
    );
  }

  void _drawTablet(
      Canvas canvas,
      Offset topLeft,
      double width,
      double height,
      Color baseColor,
      ) {
    final rect = Rect.fromLTWH(topLeft.dx, topLeft.dy, width, height);
    final tabletRect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(height / 2),
    );

    canvas.drawRRect(
      tabletRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _lighten(baseColor, 0.15),
            baseColor,
            _darken(baseColor, 0.15),
          ],
        ).createShader(rect),
    );

    canvas.drawLine(
      Offset(rect.center.dx, rect.top + 3),
      Offset(rect.center.dx, rect.bottom - 3),
      Paint()
        ..color = _darken(baseColor, 0.25).withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left + 3,
          rect.top + 2,
          rect.width - 6,
          rect.height * 0.35,
        ),
        Radius.circular(height / 2),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.4),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _TabletPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
// SYRUP BOTTLE
// ══════════════════════════════════════════════════════════════
class _SyrupPainter extends CustomPainter {
  final Color color;

  const _SyrupPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h - 2),
        width: w * 0.75,
        height: 4,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.30, 0, w * 0.4, h * 0.08),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      ),
      Paint()..color = _darken(color, 0.3),
    );

    canvas.drawRect(
      Rect.fromLTWH(w * 0.35, h * 0.08, w * 0.3, h * 0.08),
      Paint()..color = Colors.grey.shade300,
    );

    final bodyRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.15, h * 0.16, w * 0.7, h * 0.82),
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );

    canvas.drawRRect(
      bodyRect,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final liquidRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.17, h * 0.45, w * 0.66, h * 0.51),
      bottomLeft: const Radius.circular(9),
      bottomRight: const Radius.circular(9),
    );

    canvas.drawRRect(
      liquidRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _lighten(color, 0.1),
            color,
            _darken(color, 0.15),
          ],
        ).createShader(Rect.fromLTWH(0, h * 0.45, w, h * 0.5)),
    );

    canvas.drawOval(
      Rect.fromLTWH(w * 0.18, h * 0.43, w * 0.64, h * 0.05),
      Paint()..color = _lighten(color, 0.2),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.2, h * 0.55, w * 0.6, h * 0.25),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.25, h * 0.63),
      Offset(w * 0.75, h * 0.63),
      linePaint,
    );

    canvas.drawLine(
      Offset(w * 0.25, h * 0.72),
      Offset(w * 0.65, h * 0.72),
      linePaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.18, h * 0.2, w * 0.08, h * 0.7),
        topLeft: const Radius.circular(4),
        bottomLeft: const Radius.circular(8),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.5),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromLTWH(w * 0.18, h * 0.2, w * 0.08, h * 0.7),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _SyrupPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
// INJECTION / SYRINGE
// ══════════════════════════════════════════════════════════════
class _InjectionPainter extends CustomPainter {
  final Color color;

  const _InjectionPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h - 2),
        width: w * 0.85,
        height: 4,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.3);
    canvas.translate(-w / 2, -h / 2);

    canvas.drawRect(
      Rect.fromLTWH(w * 0.48, h * 0.05, w * 0.04, h * 0.2),
      Paint()..color = Colors.grey.shade400,
    );

    canvas.drawRect(
      Rect.fromLTWH(w * 0.42, h * 0.22, w * 0.16, h * 0.05),
      Paint()..color = Colors.grey.shade600,
    );

    final barrelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.35, h * 0.27, w * 0.30, h * 0.5),
      const Radius.circular(3),
    );

    canvas.drawRRect(
      barrelRect,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    canvas.drawRRect(
      barrelRect,
      Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final liquidRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.37, h * 0.32, w * 0.26, h * 0.43),
      const Radius.circular(2),
    );

    canvas.drawRRect(
      liquidRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _lighten(color, 0.1),
            color,
            _darken(color, 0.1),
          ],
        ).createShader(
          Rect.fromLTWH(w * 0.37, h * 0.32, w * 0.26, h * 0.43),
        ),
    );

    final tickPaint = Paint()
      ..color = Colors.grey.shade500
      ..strokeWidth = 0.8;

    for (int i = 1; i < 4; i++) {
      final y = h * 0.32 + (h * 0.43 / 4) * i;
      canvas.drawLine(
        Offset(w * 0.63, y),
        Offset(w * 0.68, y),
        tickPaint,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(w * 0.33, h * 0.77, w * 0.34, h * 0.06),
      Paint()..color = Colors.grey.shade600,
    );

    canvas.drawRect(
      Rect.fromLTWH(w * 0.47, h * 0.83, w * 0.06, h * 0.15),
      Paint()..color = Colors.grey.shade500,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InjectionPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════
// ALL DONE CARD
// ══════════════════════════════════════════════════════════════
class _AllDoneCard extends StatelessWidget {
  final int count;

  const _AllDoneCard({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.2),
            AppColors.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
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
            'All done for today!',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            "You've taken all $count of your doses. Great job!",
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MORE DOSES INDICATOR
// ══════════════════════════════════════════════════════════════
class _MoreDosesTile extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _MoreDosesTile({
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '+$count more ${count == 1 ? 'dose' : 'doses'} today',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
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
            'Nothing scheduled today',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Once you add medications with schedules,\nyour daily doses will appear here.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Medication'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.4),
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
            message,
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 16,
            ),
            label: const Text('Retry'),
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
        SkeletonBox(height: 80, borderRadius: 16),
        const SizedBox(height: 10),
        SkeletonBox(height: 80, borderRadius: 16),
      ],
    );
  }
}