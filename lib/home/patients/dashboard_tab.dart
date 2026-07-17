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
import '../../gui/caretakers/manage_caretakers_screen.dart';
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
        _profile   = profile as Profile?;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleKey.currentState?.load();
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _doseKey(String scheduleId, DateTime scheduledTime) {
    final t = scheduledTime;
    return '$scheduleId|'
        '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}T'
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadStats() async {
    try {
      final today   = DateTime.now();
      final results = await Future.wait([
        ScheduleService.instance.getDosesForDate(today),
        DoseLogService.instance.getLoggedDoseKeys(today),
        MedicationService.instance.getMyMedications(),
      ]);

      if (!mounted) return;

      final doses  = results[0] as List<TodayDose>;
      final logged = results[1] as Set<String>;
      final meds   = results[2] as List;

      _cachedDoses  = doses;
      _cachedLogged = Set<String>.from(logged);

      _recomputeStats();
      setState(() => _activeMeds = meds.length);
      _scheduleUpcomingNotifications(doses, logged);
    } catch (e, st) {
      debugPrint('❌ Failed to load stats: $e\n$st');
    }
  }

  void _recomputeStats() {
    if (!mounted) return;

    final taken = _cachedDoses.where((d) =>
        _cachedLogged.contains(_doseKey(d.scheduleId, d.scheduledTime))).length;

    final upcoming = _cachedDoses.where((d) {
      final key = _doseKey(d.scheduleId, d.scheduledTime);
      return !_cachedLogged.contains(key) &&
          d.scheduledTime.isAfter(DateTime.now());
    }).length;

    setState(() {
      _totalToday    = _cachedDoses.length;
      _takenCount    = taken;
      _upcomingCount = upcoming;
    });
  }

  void _onDoseTaken(TodayDose dose) {
    final key = _doseKey(dose.scheduleId, dose.scheduledTime);
    _cachedLogged.add(key);
    _recomputeStats();
    _loadStats();
  }

  Future<void> _scheduleUpcomingNotifications(
      List<TodayDose> doses, Set<String> logged) async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      for (final dose in doses) {
        final key = _doseKey(dose.scheduleId, dose.scheduledTime);
        final isTaken = logged.contains(key);

        if (!isTaken && dose.scheduledTime.isAfter(DateTime.now())) {
          final effectivePatientId = dose.patientId ?? userId;
          if (effectivePatientId.trim().isEmpty) continue;

          await LocalNotificationService.instance.scheduleForDose(
            patientId: effectivePatientId, // ✅ NEW
            scheduleId: dose.scheduleId,
            medicationId: dose.medicationId,
            medicationName: dose.medicationName,
            dosageDisplay: dose.dosageDisplay,
            scheduledFor: dose.scheduledTime,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Notification scheduling error: $e');
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadProfile(), _loadStats()]);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleKey.currentState?.load();
    });
  }

  String get _greeting {
    final h = _now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _todayDate {
    const months   = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    const weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return '${weekdays[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}';
  }

  String get _currentTime {
    final h  = _now.hour;
    final m  = _now.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'PM' : 'AM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $ap';
  }

  double get _adherence => _totalToday == 0 ? 0 : _takenCount / _totalToday;

  String get _adherenceMessage {
    if (_totalToday == 0)           return 'No doses scheduled today';
    if (_takenCount == _totalToday) return 'Perfect day!';
    if (_adherence >= 0.75)         return 'Excellent progress';
    if (_adherence >= 0.5)          return 'Keep going strong';
    if (_adherence > 0)             return 'Getting started';
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
                Row(children: [
                  Expanded(child: _MiniStatCard(icon: Icons.check_circle_rounded, iconColor: AppColors.primary,   value: '$_takenCount',    label: 'Taken')),
                  const SizedBox(width: 12),
                  Expanded(child: _MiniStatCard(icon: Icons.schedule_rounded,      iconColor: AppColors.warning,   value: '$_upcomingCount', label: 'Upcoming')),
                  const SizedBox(width: 12),
                  Expanded(child: _MiniStatCard(icon: Icons.medication_rounded,    iconColor: AppColors.secondary, value: '$_activeMeds',    label: 'Active')),
                ]),
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
                  key:              _scheduleKey,
                  onAddPressed:     _navigateToAddMedication,
                  onViewAllPressed: _goToMedicationsTab,
                  onDoseTaken:      _onDoseTaken,
                  maxDoses:         2,
                ),
                const SizedBox(height: 32),
                const _SectionTitle('Quick Actions'),
                const SizedBox(height: 12),
                _QuickActionsGrid(
                  onAddMedication:    _navigateToAddMedication,
                  onViewMedications:  _goToMedicationsTab,
                  onManageCaretakers: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ManageCaretakersScreen())),
                ),
                // Extra bottom padding so SOS FAB doesn't overlap content
                const SizedBox(height: 100),
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
  final String greeting, name, todayDate, currentTime;
  const _HeroHeader({required this.greeting, required this.name, required this.todayDate, required this.currentTime});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.secondary, AppColors.secondaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: AppColors.secondary.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Stack(children: [
          const Positioned.fill(child: _HeroBubbles()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _Chip(background: Colors.white.withValues(alpha: 0.15), children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(todayDate, style: AppTextStyles.labelSmall.copyWith(color: Colors.white)),
                ]),
                const Spacer(),
                _Chip(
                  background: AppColors.primary.withValues(alpha: 0.20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.40)),
                  children: [
                    const Icon(Icons.access_time_rounded, size: 12, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(currentTime, style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ],
                ),
              ]),
              const SizedBox(height: 20),
              Text(greeting, style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 4),
              Text(name, style: AppTextStyles.displayMedium.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text('Stay on track with your health today', style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withValues(alpha: 0.70))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Color background;
  final Border? border;
  final List<Widget> children;
  const _Chip({required this.background, required this.children, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20), border: border),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HERO BUBBLES (unchanged)
// ══════════════════════════════════════════════════════════════
class _HeroBubbles extends StatelessWidget {
  const _HeroBubbles();
  @override
  Widget build(BuildContext context) => const IgnorePointer(child: CustomPaint(painter: _MedicalPainter()));
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
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.10)..style = PaintingStyle.fill;
    final cx = size.width - 65, cy = 45.0;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy - 22), width: 36, height: 14), const Radius.circular(3)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 5), width: 44, height: 50), const Radius.circular(6)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 5), width: 44, height: 18), const Radius.circular(2)),
        Paint()..color = Colors.white.withValues(alpha: 0.06)..style = PaintingStyle.fill);
  }

  void _drawSyrupBottle(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.08)..style = PaintingStyle.fill;
    final cx = size.width - 30, cy = size.height - 35;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy - 28), width: 20, height: 10), const Radius.circular(2)), paint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy - 20), width: 14, height: 6), paint);
    canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromCenter(center: Offset(cx, cy), width: 32, height: 42), topLeft: const Radius.circular(4), topRight: const Radius.circular(4), bottomLeft: const Radius.circular(8), bottomRight: const Radius.circular(8)), paint);
  }

  void _drawPill(Canvas canvas, Size size) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(size.width * 0.55, size.height * 0.5), width: 34, height: 16), const Radius.circular(10)),
        Paint()..color = Colors.white.withValues(alpha: 0.12)..style = PaintingStyle.fill);
  }

  void _drawCapsule(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width * 0.72, size.height * 0.75);
    canvas.rotate(-0.4);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 28, height: 12), const Radius.circular(6)),
        Paint()..color = Colors.white.withValues(alpha: 0.09)..style = PaintingStyle.fill);
    canvas.restore();
  }

  void _drawTinyDots(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.15)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.40, size.height * 0.25), 3,   p);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.85), 2.5, p);
    canvas.drawCircle(Offset(size.width * 0.60, size.height * 0.15), 2,   p);
    canvas.drawCircle(Offset(size.width * 0.50, size.height * 0.90), 3.5, p);
  }

  @override
  bool shouldRepaint(covariant _MedicalPainter _) => false;
}

// ══════════════════════════════════════════════════════════════
// TODAY PROGRESS CARD
// ══════════════════════════════════════════════════════════════
class _TodayProgressCard extends StatelessWidget {
  final double adherence;
  final String message;
  final int takenCount, totalCount;
  const _TodayProgressCard({required this.adherence, required this.message, required this.takenCount, required this.totalCount});

  int get _pct => (adherence * 100).round();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))]),
      child: Row(children: [
        SizedBox(width: 80, height: 80,
          child: Stack(alignment: Alignment.center, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: adherence.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(value: v, strokeWidth: 8, backgroundColor: AppColors.surfaceVariant,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
            ),
            Text('$_pct%', style: AppTextStyles.h2.copyWith(color: AppColors.secondary)),
          ]),
        ),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Today's adherence", style: AppTextStyles.labelSmall),
          const SizedBox(height: 4),
          Text(message, style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text(totalCount == 0 ? 'Add medications to track your health' : '$takenCount of $totalCount doses taken',
              style: AppTextStyles.bodySmall),
        ])),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECTION TITLE / VIEW ALL
// ══════════════════════════════════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Text(title, style: AppTextStyles.h3);
}

class _ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewAllButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Text('View All', style: AppTextStyles.labelMedium.copyWith(color: AppColors.secondary)),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.secondary),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MINI STAT CARD
// ══════════════════════════════════════════════════════════════
class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value, label;
  const _MiniStatCard({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: iconColor)),
        const SizedBox(height: 10),
        Text(value, style: AppTextStyles.h2),
        Text(label,  style: AppTextStyles.bodySmall),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// QUICK ACTIONS  — "Scan Bottle" removed
// ══════════════════════════════════════════════════════════════
class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onAddMedication;
  final VoidCallback onViewMedications;
  final VoidCallback onManageCaretakers;
  const _QuickActionsGrid({
    required this.onAddMedication,
    required this.onViewMedications,
    required this.onManageCaretakers,
  });

  void _comingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.construction_rounded, color: AppColors.warning)),
          const SizedBox(width: 12),
          const Text('Coming Soon'),
        ]),
        content: Text('$feature is coming soon!'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(child: _ActionTile(
          icon: Icons.add_circle_rounded, iconColor: AppColors.primary,
          label: 'Add Manually', subtitle: 'Type details',
          onTap: onAddMedication,
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile(
          icon: Icons.medication_rounded, iconColor: AppColors.secondary,
          label: 'My Meds', subtitle: 'View all',
          onTap: onViewMedications,
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _ActionTile(
          icon: Icons.people_rounded, iconColor: AppColors.warning,
          label: 'Caretakers', subtitle: 'Manage',
          onTap: onManageCaretakers,
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile(
          icon: Icons.bar_chart_rounded, iconColor: AppColors.info,
          label: 'Reports', subtitle: 'View history',
          onTap: () => _comingSoon(context, 'Reports'),
        )),
      ]),
    ]);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, subtitle;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.iconColor, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 22, color: iconColor)),
          const SizedBox(height: 12),
          Text(label,    style: AppTextStyles.titleSmall),
          Text(subtitle, style: AppTextStyles.bodySmall),
        ]),
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
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.secondary, AppColors.secondaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkeletonBox(width: 120, height: 24, borderRadius: 20),
          SizedBox(height: 16),
          SkeletonBox(width: 100, height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 220, height: 28),
          SizedBox(height: 12),
          SkeletonBox(width: 180, height: 12),
        ]),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.all(20), children: const [
        SkeletonBox(height: 110, borderRadius: 24),
        SizedBox(height: 24),
        SkeletonBox(height: 20, width: 180),
        SizedBox(height: 12),
        Row(children: [
          Expanded(child: SkeletonBox(height: 90, borderRadius: 16)),
          SizedBox(width: 12),
          Expanded(child: SkeletonBox(height: 90, borderRadius: 16)),
          SizedBox(width: 12),
          Expanded(child: SkeletonBox(height: 90, borderRadius: 16)),
        ]),
      ])),
    ]);
  }
}