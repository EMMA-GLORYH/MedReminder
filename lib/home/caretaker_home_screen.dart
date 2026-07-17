// lib/home/caretaker_home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mar/gui/splash_screen.dart';
import 'package:mar/home/caretaker/alerts_tab.dart';
import 'package:mar/home/caretaker/caretaker_dashboard_tab.dart';
import 'package:mar/home/caretaker/caretaker_profile_tab.dart';
import 'package:mar/home/caretaker/patients_tab.dart';
import 'package:mar/models/profile.dart';
import 'package:mar/services/auth_service.dart';
import 'package:mar/services/care_relationship_service.dart';
import 'package:mar/services/sos_realtime_service.dart';
import 'package:mar/services/sos_service.dart';
import 'package:mar/services/sos_speech_service.dart';
import 'package:mar/theme/app_colors.dart';
import 'package:mar/theme/app_text_styles.dart';
import 'package:mar/widgets/dialogs/confirm_dialog.dart';
import 'package:mar/widgets/snackbar/app_snackbar.dart';

class CaretakerHomeScreen extends StatefulWidget {
  const CaretakerHomeScreen({super.key});

  @override
  State<CaretakerHomeScreen> createState() =>
      _CaretakerHomeScreenState();
}

class _CaretakerHomeScreenState
    extends State<CaretakerHomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  Profile? _profile;

  int _patientCount = 0;
  int _openAlertCount = 0;
  int _pendingInviteCount = 0;

  bool _isLoadingSummary = true;
  bool _isRefreshing = false;
  bool _refreshQueued = false;

  RealtimeChannel? _relationshipChannel;
  RealtimeChannel? _sosChannel;

  Timer? _refreshDebounce;

  final Set<String> _announcedSosIds = <String>{};

  final List<String> _titles = const [
    'Overview',
    'My Patients',
    'Alerts',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSummary();
    _subscribeToRealtime();
    _startNativeSosMonitor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshDebounce?.cancel();

    final relationshipChannel = _relationshipChannel;
    if (relationshipChannel != null) {
      unawaited(
        Supabase.instance.client.removeChannel(
          relationshipChannel,
        ),
      );
    }

    final sosChannel = _sosChannel;
    if (sosChannel != null) {
      unawaited(
        Supabase.instance.client.removeChannel(
          sosChannel,
        ),
      );
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSummary(silent: true);
      _startNativeSosMonitor(); // pushes a fresh token if it changed
    }
  }

  void _startNativeSosMonitor() {
    final id = AuthService.instance.currentUser?.id;
    if (id != null && id.isNotEmpty) {
      SosRealtimeNativeService.instance.startForCurrentCaretaker(caregiverId: id);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // REALTIME SUBSCRIPTIONS (Flutter UI layer fallback)
  //
  // This Flutter subscription updates badge counts and shows
  // snackbars when the app is visible.
  //
  // The native SosRealtimeService handles the actual alarm when the
  // app is backgrounded or the phone is locked.
  // ══════════════════════════════════════════════════════════════

  void _subscribeToRealtime() {
    try {
      _relationshipChannel =
          CareRelationshipService.instance
              .subscribeToMyInvites(() {
            _queueSummaryRefresh();
          });
    } catch (error, stack) {
      debugPrint(
        '❌ Care relationship Realtime subscription failed: '
            '$error',
      );
      debugPrint('$stack');
    }

    try {
      _sosChannel =
          SosService.instance.subscribeToCaretakerAlerts(
            _handleSosRealtimeChange,
          );
    } catch (error, stack) {
      debugPrint(
        '❌ SOS Realtime subscription failed: $error',
      );
      debugPrint('$stack');
    }
  }

  void _handleSosRealtimeChange(PostgresChangePayload payload) {
    if (!mounted) return;

    // The native SosRealtimeService plays the alarm + caretaker_sos.mp3.
    // Here we only refresh the UI (badge / list).
    if (payload.eventType == PostgresChangeEvent.insert) {
      final record = Map<String, dynamic>.from(payload.newRecord);
      final status = record['status']?.toString() ?? 'sent';
      if (status == 'sent') {
        final name = (record['patient_name']?.toString() ?? 'A patient').trim();
        AppSnackbar.error(context, 'URGENT: ${name.isEmpty ? 'A patient' : name} sent an SOS');
      }
    }

    if (payload.eventType == PostgresChangeEvent.update) {
      final status = payload.newRecord['status']?.toString();
      if (status == 'resolved' || status == 'cancelled') {
        // Native stops itself when a new alert supersedes; nothing to do here.
      }
    }

    _queueSummaryRefresh();
  }

  void _queueSummaryRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 350),
          () {
        if (mounted) _loadSummary(silent: true);
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SUMMARY COUNTS
  // ══════════════════════════════════════════════════════════════

  Future<int> _getOpenAlertCount() async {
    final caregiverId =
        AuthService.instance.currentUser?.id;

    if (caregiverId == null) return 0;

    try {
      final response = await Supabase.instance.client
          .from('sos_alerts')
          .select('id')
          .eq('caregiver_id', caregiverId)
          .inFilter('status', const [
        'sent',
        'acknowledged',
      ]).count(CountOption.exact);

      return response.count;
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to count open SOS alerts: $error',
      );
      debugPrint('$stack');
      return _openAlertCount;
    }
  }

  Future<void> _loadSummary({
    bool silent = false,
  }) async {
    if (_isRefreshing) {
      _refreshQueued = true;
      return;
    }

    _isRefreshing = true;

    if (!silent && mounted) {
      setState(() => _isLoadingSummary = true);
    }

    try {
      final results = await Future.wait<Object?>([
        AuthService.instance.getCurrentProfile(),
        CareRelationshipService.instance
            .getActivePatientCount(),
        CareRelationshipService.instance
            .getPendingInviteCount(),
        _getOpenAlertCount(),
      ]);

      final profile = results[0] as Profile?;
      final patientCount = results[1] as int;
      final pendingInviteCount = results[2] as int;
      final openAlertCount = results[3] as int;

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _patientCount = patientCount;
        _pendingInviteCount = pendingInviteCount;
        _openAlertCount = openAlertCount;
        _isLoadingSummary = false;
      });
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to load caretaker summary: $error',
      );
      debugPrint('$stack');

      if (mounted) {
        setState(() => _isLoadingSummary = false);
      }
    } finally {
      _isRefreshing = false;

      if (_refreshQueued && mounted) {
        _refreshQueued = false;
        unawaited(_loadSummary(silent: true));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // NAVIGATION
  // ══════════════════════════════════════════════════════════════

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      if (index == 0 || index == 1 || index == 2) {
        _loadSummary(silent: true);
      }
      return;
    }

    setState(() => _selectedIndex = index);

    if (index == 0 || index == 1 || index == 2) {
      _loadSummary(silent: true);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LOGOUT
  // ══════════════════════════════════════════════════════════════

  Future<void> _handleLogout() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Sign Out?',
      message:
      'You will need to sign in again to check on your patients.',
      confirmText: 'Sign Out',
      type: ConfirmDialogType.warning,
    );

    if (confirmed != true || !mounted) return;

    try {
      // ✅ Stop the SOS alarm sound if it is currently playing.
      await SosSpeechService.instance.stop();

      // ✅ NEW: Stop the native background WebSocket service so
      // SOS alerts are no longer received after logout.
      await SosRealtimeNativeService.instance.stop();

      await AuthService.instance.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const SplashScreen(
            showBranding: false,
          ),
        ),
            (route) => false,
      );
    } catch (error, stack) {
      debugPrint(
        '❌ Caretaker logout failed: $error',
      );
      debugPrint('$stack');

      if (mounted) {
        AppSnackbar.error(
          context,
          'Failed to sign out',
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          _titles[_selectedIndex],
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_isLoadingSummary)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Center(
                child: SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(
              Icons.power_settings_new_rounded,
              color: AppColors.secondary,
            ),
            onPressed: _handleLogout,
            tooltip: 'Sign Out',
          ),
        ],
      ),

      body: Column(
        children: [
          _CaretakerHero(
            caretakerName:
            _profile?.fullName ?? 'Caretaker',
            patientCount: _patientCount,
            openAlertCount: _openAlertCount,
            pendingInviteCount: _pendingInviteCount,
            isLoading: _isLoadingSummary,
            onPatients: () => _selectTab(1),
            onAlerts: () => _selectTab(2),
            onRefresh: () => _loadSummary(),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                CaretakerDashboardTab(),
                PatientsTab(),
                AlertsTab(),
                CaretakerProfileTab(),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary
            .withValues(alpha: 0.20),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(
              Icons.dashboard_rounded,
              color: AppColors.secondary,
            ),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _patientCount > 0,
              label: Text('$_patientCount'),
              child: const Icon(
                Icons.people_outline_rounded,
              ),
            ),
            selectedIcon: Badge(
              isLabelVisible: _patientCount > 0,
              label: Text('$_patientCount'),
              child: const Icon(
                Icons.people_rounded,
                color: AppColors.secondary,
              ),
            ),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _openAlertCount > 0,
              backgroundColor: AppColors.error,
              label: Text('$_openAlertCount'),
              child: const Icon(
                Icons.notifications_outlined,
              ),
            ),
            selectedIcon: Badge(
              isLabelVisible: _openAlertCount > 0,
              backgroundColor: AppColors.error,
              label: Text('$_openAlertCount'),
              child: const Icon(
                Icons.notifications_rounded,
                color: AppColors.secondary,
              ),
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(
              Icons.person_rounded,
              color: AppColors.secondary,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PROFESSIONAL OVERVIEW HERO
// ══════════════════════════════════════════════════════════════

class _CaretakerHero extends StatelessWidget {
  final String caretakerName;
  final int patientCount;
  final int openAlertCount;
  final int pendingInviteCount;
  final bool isLoading;
  final VoidCallback onPatients;
  final VoidCallback onAlerts;
  final VoidCallback onRefresh;

  const _CaretakerHero({
    required this.caretakerName,
    required this.patientCount,
    required this.openAlertCount,
    required this.pendingInviteCount,
    required this.isLoading,
    required this.onPatients,
    required this.onAlerts,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(34),
        bottomRight: Radius.circular(34),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          20,
          18,
          20,
          24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.secondary,
              AppColors.secondaryLight,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(
                alpha: 0.18,
              ),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HeroDecorationPainter(),
                ),
              ),
            ),
            Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Welcome, $caretakerName',
                        style: AppTextStyles.h2.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: onRefresh,
                      tooltip: 'Refresh overview',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white
                            .withValues(alpha: 0.13),
                        foregroundColor: Colors.white,
                      ),
                      icon: isLoading
                          ? const SizedBox(
                        width: 19,
                        height: 19,
                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(
                        Icons.refresh_rounded,
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Monitor your patients and respond quickly '
                      'when urgent assistance is needed.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white
                        .withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        value: '$patientCount',
                        label: 'Patients',
                        icon: Icons.people_rounded,
                        color: AppColors.primary,
                        onTap: onPatients,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroStat(
                        value: '$openAlertCount',
                        label: 'Urgent alerts',
                        icon: Icons.sos_rounded,
                        color: AppColors.error,
                        onTap: onAlerts,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroStat(
                        value: '$pendingInviteCount',
                        label: 'Invites',
                        icon: Icons.mail_rounded,
                        color: AppColors.warning,
                        onTap: onPatients,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HeroStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
            Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppTextStyles.h2.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style:
              AppTextStyles.labelSmall.copyWith(
                color: Colors.white
                    .withValues(alpha: 0.74),
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroDecorationPainter extends CustomPainter {
  const _HeroDecorationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final softPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    final accentPaint = Paint()
      ..color =
      AppColors.primary.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width - 30, 24),
      65,
      softPaint,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.68,
        size.height - 10,
      ),
      45,
      accentPaint,
    );

    canvas.drawCircle(
      Offset(15, size.height * 0.55),
      24,
      softPaint,
    );
  }

  @override
  bool shouldRepaint(
      covariant _HeroDecorationPainter oldDelegate,
      ) =>
      false;
}