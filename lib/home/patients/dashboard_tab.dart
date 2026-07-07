// lib/screens/home/patient/dashboard_tab.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../services/dose_log_service.dart';
import '../../services/local_notification_service.dart';
import '../../services/medication_service.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';
import '../../gui/medications/add_medication_screen.dart';
import 'widgets/todays_schedule.dart';

class DashboardTab extends StatefulWidget {
  final void Function(int index)? onNavigateToTab;

  const DashboardTab({super.key, this.onNavigateToTab});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Profile? _profile;
  bool _isLoading = true;
  final _scheduleKey = GlobalKey<TodaysScheduleState>();

  int _takenCount    = 0;
  int _upcomingCount = 0;
  int _activeMeds    = 0;
  int _totalToday    = 0;

  // Cached dose list + logged keys so we can update counts instantly
  // without waiting for a DB round-trip every time a dose is tapped.
  List<TodayDose> _cachedDoses  = [];
  Set<String>     _cachedLogged = {};

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initData();
    _startClock();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clockTimer = null;
    super.dispose();
  }

  // ── init ───────────────────────────────────────────────────
  Future<void> _initData() async {
    await _loadProfile();
    await _loadStats();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await AuthService.instance.getCurrentProfile();
      if (!mounted) return;
      setState(() {
        _profile   = profile;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleKey.currentState?.load();
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── normalized key (must match TodaysSchedule + DoseLogService) ──
  String _doseKey(String scheduleId, DateTime scheduledTime) {
    final t = scheduledTime;
    return '$scheduleId|'
        '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}T'
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  // ── full DB stats load ─────────────────────────────────────
  Future<void> _loadStats() async {
    try {
      final today = DateTime.now();
      final results = await Future.wait([
        ScheduleService.instance.getDosesForDate(today),
        DoseLogService.instance.getLoggedDoseKeys(today),
        MedicationService.instance.getMyMedications(),
      ]);

      if (!mounted) return;

      final doses  = results[0] as List<TodayDose>;
      final logged = results[1] as Set<String>;
      final meds   = results[2] as List;

      // Cache so onDoseTaken can update instantly
      _cachedDoses  = doses;
      _cachedLogged = Set<String>.from(logged);

      _recomputeStats();

      setState(() => _activeMeds = meds.length);

      // Schedule local notifications for all upcoming doses
      _scheduleUpcomingNotifications(doses, logged);

    } catch (e, st) {
      debugPrint('❌ Failed to load stats: $e');
      debugPrint('$st');
    }
  }

  // ── recompute taken/upcoming from cache ────────────────────
  // Called both after full DB load AND after each dose is tapped
  // so counters update instantly with zero DB latency.
  void _recomputeStats() {
    if (!mounted) return;

    final taken = _cachedDoses.where((d) {
      return _cachedLogged.contains(_doseKey(d.scheduleId, d.scheduledTime));
    }).length;

    final upcoming = _cachedDoses.where((d) {
      final key     = _doseKey(d.scheduleId, d.scheduledTime);
      final isLogged = _cachedLogged.contains(key);
      return !isLogged && d.scheduledTime.isAfter(DateTime.now());
    }).length;

    setState(() {
      _totalToday    = _cachedDoses.length;
      _takenCount    = taken;
      _upcomingCount = upcoming;
    });
  }

  // ── called by TodaysSchedule when a dose is marked taken ──
  // Updates the local cache INSTANTLY, then syncs from DB.
  void _onDoseTaken(TodayDose dose) {
    // 1. Instantly update local cache — zero latency
    final key = _doseKey(dose.scheduleId, dose.scheduledTime);
    _cachedLogged.add(key);
    _recomputeStats();

    // 2. Sync from DB in background to stay accurate
    _loadStats();
  }

  // ── schedule local notifications for upcoming doses ───────
  Future<void> _scheduleUpcomingNotifications(
      List<TodayDose> doses,
      Set<String> logged,
      ) async {
    try {
      for (final dose in doses) {
        final key      = _doseKey(dose.scheduleId, dose.scheduledTime);
        final isTaken  = logged.contains(key);
        final isFuture = dose.scheduledTime.isAfter(DateTime.now());

        if (!isTaken && isFuture) {
          await LocalNotificationService.instance.scheduleForDose(
            scheduleId:     dose.scheduleId,
            medicationId:   dose.medicationId,
            medicationName: dose.medicationName,
            dosageDisplay:  dose.dosageDisplay,
            scheduledFor:   dose.scheduledTime,
          );
        }
      }
      debugPrint('🔔 Notifications scheduled for upcoming doses');
    } catch (e) {
      debugPrint('⚠️ Could not schedule notifications: $e');
    }
  }

  // ── full refresh (pull-to-refresh + after adding meds) ────
  Future<void> _refreshAll() async {
    await Future.wait([_loadProfile(), _loadStats()]);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleKey.currentState?.load();
    });
  }

  // ── display helpers ────────────────────────────────────────
  String get _greeting {
    final hour = _now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _todayDate {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return '${weekdays[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}';
  }

  String get _currentTime {
    final hour        = _now.hour;
    final minute      = _now.minute.toString().padLeft(2, '0');
    final period      = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  double get _adherence {
    if (_totalToday == 0) return 0;
    return _takenCount / _totalToday;
  }

  String get _adherenceMessage {
    if (_totalToday == 0)            return 'No doses scheduled today';
    if (_takenCount == _totalToday)  return 'Perfect day!';
    if (_adherence >= 0.75)          return 'Excellent progress';
    if (_adherence >= 0.5)           return 'Keep going strong';
    if (_adherence > 0)              return 'Getting started';
    return 'Great start!';
  }

  Future<void> _navigateToAddMedication() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicationScreen()),
    );
    if (result == true && mounted) _refreshAll();
  }

  void _goToMedicationsTab() => widget.onNavigateToTab?.call(1);

  // ── build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _DashboardSkeleton();

    return Column(
      children: [
        _HeroHeader(
          greeting:    _greeting,
          name:        _profile?.fullName ?? 'there',
          todayDate:   _todayDate,
          currentTime: _currentTime,
        ),
        Expanded(
          child: RefreshIndicator(
            color:     AppColors.primary,
            onRefresh: _refreshAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                _TodayProgressCard(
                  adherence:  _adherence,
                  message:    _adherenceMessage,
                  takenCount: _takenCount,
                  totalCount: _totalToday,
                ),
                const SizedBox(height: 24),
                const _SectionTitle('Today at a glance'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStatCard(
                        icon:      Icons.check_circle_rounded,
                        iconColor: AppColors.primary,
                        value:     '$_takenCount',
                        label:     'Taken',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniStatCard(
                        icon:      Icons.schedule_rounded,
                        iconColor: AppColors.warning,
                        value:     '$_upcomingCount',
                        label:     'Upcoming',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniStatCard(
                        icon:      Icons.medication_rounded,
                        iconColor: AppColors.secondary,
                        value:     '$_activeMeds',
                        label:     'Active',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionTitle("Today's Schedule"),
                    _ViewAllButton(onTap: _goToMedicationsTab),
                  ],
                ),
                const SizedBox(height: 12),
                TodaysSchedule(
                  key:             _scheduleKey,
                  onAddPressed:    _navigateToAddMedication,
                  onViewAllPressed: _goToMedicationsTab,
                  // ✅ Passes the full TodayDose object so we can
                  //    update the cache instantly without a DB round-trip
                  onDoseTaken: _onDoseTaken,
                  maxDoses: 2,
                ),
                const SizedBox(height: 32),
                const _SectionTitle('Quick Actions'),
                const SizedBox(height: 12),
                _QuickActionsGrid(
                  onAddMedication:  _navigateToAddMedication,
                  onViewMedications: _goToMedicationsTab,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HERO HEADER
// ══════════════════════════════════════════════════════════════
class _HeroHeader extends StatelessWidget {
  final String greeting;
  final String name;
  final String todayDate;
  final String currentTime;

  const _HeroHeader({
    required this.greeting,
    required this.name,
    required this.todayDate,
    required this.currentTime,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft:  Radius.circular(32),
        bottomRight: Radius.circular(32),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.secondary, AppColors.secondaryLight],
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color:      AppColors.secondary.withValues(alpha: 0.15),
              blurRadius: 12,
              offset:     const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _HeroBubbles()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Chip(
                        background: Colors.white.withValues(alpha: 0.15),
                        children: [
                          Container(
                            width:  6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            todayDate,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _Chip(
                        background: AppColors.primary.withValues(alpha: 0.20),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.40),
                        ),
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size:  12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            currentTime,
                            style: AppTextStyles.labelSmall.copyWith(
                              color:      AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    greeting,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style:    AppTextStyles.displayMedium.copyWith(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stay on track with your health today',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SMALL REUSABLE CHIP
// ══════════════════════════════════════════════════════════════
class _Chip extends StatelessWidget {
  final Color          background;
  final Border?        border;
  final List<Widget>   children;

  const _Chip({
    required this.background,
    required this.children,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        background,
        borderRadius: BorderRadius.circular(20),
        border:       border,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DECORATIVE MEDICAL ITEMS
// ══════════════════════════════════════════════════════════════
class _HeroBubbles extends StatelessWidget {
  const _HeroBubbles();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(painter: _MedicalPainter()),
    );
  }
}

class _MedicalPainter extends CustomPainter {
  const _MedicalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _drawPillBottle(canvas, size);
    _drawSyrupBottle(canvas, size);
    _drawPill(canvas, size);
    _drawCapsule(canvas, size);
    _drawTinyDots(canvas, size);
  }

  void _drawPillBottle(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    final centerX = size.width - 65;
    final centerY = 45.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, centerY - 22), width: 36, height: 14),
        const Radius.circular(3),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, centerY + 5), width: 44, height: 50),
        const Radius.circular(6),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, centerY + 5), width: 44, height: 18),
        const Radius.circular(2),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawSyrupBottle(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final centerX = size.width - 30;
    final centerY = size.height - 35;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, centerY - 28), width: 20, height: 10),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(centerX, centerY - 20), width: 14, height: 6),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset(centerX, centerY), width: 32, height: 42),
        topLeft:     const Radius.circular(4),
        topRight:    const Radius.circular(4),
        bottomLeft:  const Radius.circular(8),
        bottomRight: const Radius.circular(8),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset(centerX, centerY + 8), width: 32, height: 26),
        bottomLeft:  const Radius.circular(8),
        bottomRight: const Radius.circular(8),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawPill(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final centerX = size.width * 0.55;
    final centerY = size.height * 0.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, centerY), width: 34, height: 16),
        const Radius.circular(10),
      ),
      paint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - 8),
      Offset(centerX, centerY + 8),
      Paint()
        ..color      = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = 1,
    );
  }

  void _drawCapsule(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(size.width * 0.72, size.height * 0.75);
    canvas.rotate(-0.4);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 28, height: 12),
        const Radius.circular(6),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(center: const Offset(-7, 0), width: 14, height: 12),
        topLeft:    const Radius.circular(6),
        bottomLeft: const Radius.circular(6),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  void _drawTinyDots(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.4,  size.height * 0.25), 3,   paint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.85), 2.5, paint);
    canvas.drawCircle(Offset(size.width * 0.6,  size.height * 0.15), 2,   paint);
    canvas.drawCircle(Offset(size.width * 0.5,  size.height * 0.9),  3.5, paint);
  }

  @override
  bool shouldRepaint(covariant _MedicalPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════
// TODAY PROGRESS CARD
// ══════════════════════════════════════════════════════════════
class _TodayProgressCard extends StatelessWidget {
  final double adherence;
  final String message;
  final int    takenCount;
  final int    totalCount;

  const _TodayProgressCard({
    required this.adherence,
    required this.message,
    required this.takenCount,
    required this.totalCount,
  });

  int get _percentage => (adherence * 100).round();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border:       Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width:  80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width:  80,
                  height: 80,
                  child: TweenAnimationBuilder<double>(
                    tween:    Tween(begin: 0, end: adherence.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 800),
                    curve:    Curves.easeOutCubic,
                    builder:  (context, value, _) {
                      return CircularProgressIndicator(
                        value:           value,
                        strokeWidth:     8,
                        backgroundColor: AppColors.surfaceVariant,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      );
                    },
                  ),
                ),
                Text(
                  '$_percentage%',
                  style: AppTextStyles.h2.copyWith(color: AppColors.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's adherence", style: AppTextStyles.labelSmall),
                const SizedBox(height: 4),
                Text(message, style: AppTextStyles.titleMedium),
                const SizedBox(height: 8),
                Text(
                  totalCount == 0
                      ? 'Add medications to track your health'
                      : '$takenCount of $totalCount doses taken',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECTION TITLE
// ══════════════════════════════════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Text(title, style: AppTextStyles.h3);
}

// ══════════════════════════════════════════════════════════════
// VIEW ALL BUTTON
// ══════════════════════════════════════════════════════════════
class _ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Text(
              'View All',
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.secondary),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MINI STAT CARD
// ══════════════════════════════════════════════════════════════
class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   value;
  final String   label;

  const _MiniStatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color:        iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(value, style: AppTextStyles.h2),
          Text(label,  style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// QUICK ACTIONS
// ══════════════════════════════════════════════════════════════
class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onAddMedication;
  final VoidCallback onViewMedications;

  const _QuickActionsGrid({
    required this.onAddMedication,
    required this.onViewMedications,
  });

  void _showUnderConstruction(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:        AppColors.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.construction_rounded, color: AppColors.warning),
            ),
            const SizedBox(width: 12),
            const Text('Under Construction'),
          ],
        ),
        content: const Text(
          'The AI bottle scanner is coming soon!\n\n'
              'For now, please add your medications manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon:      Icons.camera_alt_rounded,
                iconColor: AppColors.info,
                label:     'Scan Bottle',
                subtitle:  'Coming soon',
                onTap:     () => _showUnderConstruction(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon:      Icons.add_circle_rounded,
                iconColor: AppColors.primary,
                label:     'Add Manually',
                subtitle:  'Type details',
                onTap:     onAddMedication,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon:      Icons.medication_rounded,
                iconColor: AppColors.secondary,
                label:     'My Meds',
                subtitle:  'View all',
                onTap:     onViewMedications,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon:      Icons.people_rounded,
                iconColor: AppColors.warning,
                label:     'Caretakers',
                subtitle:  'Manage',
                onTap:     () => _showUnderConstruction(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData     icon;
  final Color        iconColor;
  final String       label;
  final String       subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(label,    style: AppTextStyles.titleSmall),
            Text(subtitle, style: AppTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SKELETON
// ══════════════════════════════════════════════════════════════
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width:   double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.secondary, AppColors.secondaryLight],
              begin:  Alignment.topLeft,
              end:    Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft:  Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 24, borderRadius: 20),
              SizedBox(height: 16),
              SkeletonBox(width: 100, height: 14),
              SizedBox(height: 8),
              SkeletonBox(width: 220, height: 28),
              SizedBox(height: 12),
              SkeletonBox(width: 180, height: 12),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              SkeletonBox(height: 110, borderRadius: 24),
              SizedBox(height: 24),
              SkeletonBox(height: 20, width: 180),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: SkeletonBox(height: 90, borderRadius: 16)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 90, borderRadius: 16)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 90, borderRadius: 16)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}