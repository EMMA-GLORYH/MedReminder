// lib/screens/home/patients/medication_reminder_scanner_screen.dart

import 'package:flutter/material.dart';

import '../../localization/app_localizations.dart';
import '../../services/dose_log_service.dart';
import '../../services/medication_tts_service.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/snackbar/app_snackbar.dart';

// ══════════════════════════════════════════════════════════════
// SCREEN — shows the medicine image (from medications.pill_image_url)
// and marks the dose as taken directly. This is now the single place
// in the app that performs the "mark as taken" action; the schedule
// list only navigates here.
// ══════════════════════════════════════════════════════════════

class MedicationReminderScannerScreen extends StatefulWidget {
  final TodayDose dose;

  const MedicationReminderScannerScreen({
    super.key,
    required this.dose,
  });

  @override
  State<MedicationReminderScannerScreen> createState() =>
      _MedicationReminderScannerScreenState();
}

class _MedicationReminderScannerScreenState
    extends State<MedicationReminderScannerScreen>
    with SingleTickerProviderStateMixin {
  bool _isMarkingTaken = false;
  bool _ttsStarted = false;

  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Localized TTS message needs BuildContext (for AppLocalizations), so
    // it's started here rather than initState.
    if (!_ttsStarted) {
      _ttsStarted = true;
      _startTts();
    }
  }

  // ── TTS ──────────────────────────────────────────────────
  Future<void> _startTts() async {
    final loc = AppLocalizations.of(context);
    await MedicationTtsService.instance.speakUntilStopped(
      message: loc.t('ttsReminderMessage', {
        'name': widget.dose.medicationName,
        'dosage': widget.dose.dosageDisplay,
      }),
    );
  }

  // ── Back-press guard ─────────────────────────────────────
  Future<bool> _onWillPop() async {
    final loc = AppLocalizations.of(context);

    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2232),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          loc.t('reminderActiveTitle'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          loc.t('reminderActiveBody'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              MedicationTtsService.instance.stop();
              Navigator.pop(ctx, true);
            },
            child: Text(loc.t('stopReminder')),
          ),
        ],
      ),
    );

    return leave ?? false;
  }

  // ── Mark as taken ────────────────────────────────────────
  // Same DoseLogService call the schedule list's old button used to make —
  // this is now the only place in the app that performs it.
  Future<void> _markAsTaken() async {
    final loc = AppLocalizations.of(context);
    setState(() => _isMarkingTaken = true);

    try {
      await DoseLogService.instance.markAsTaken(
        scheduleId:   widget.dose.scheduleId,
        medicationId: widget.dose.medicationId,
        scheduledFor: widget.dose.scheduledTime,
      );

      if (!mounted) return;
      await MedicationTtsService.instance.stop();
      AppSnackbar.success(context, loc.t('doseMarkedTaken'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, loc.t('failedToMarkDose'));
      setState(() => _isMarkingTaken = false);
    }
  }

  // ── Stop reminder ────────────────────────────────────────
  Future<void> _stopReminder() async {
    await MedicationTtsService.instance.stop();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dose     = widget.dose;
    final hasImage = dose.pillImageUrl?.isNotEmpty == true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final ok = await _onWillPop();
          if (ok && mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F14),
        body: SafeArea(
          child: Column(
            children: [
              _ScannerHeader(
                onClose: _stopReminder,
                onMute:  () => MedicationTtsService.instance.stop(),
              ),

              _MedicineInfoCard(dose: dose),

              const SizedBox(height: 20),

              // ── Medicine image (from medications.pill_image_url) ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.primary
                                .withValues(alpha: _pulseAnimation.value),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: hasImage
                            ? _MedicineImage(imageUrl: dose.pillImageUrl!)
                            : const _NoImagePlaceholder(),
                      );
                    },
                  ),
                ),
              ),

              _BottomPanel(
                isMarkingTaken: _isMarkingTaken,
                onMarkTaken:    _markAsTaken,
                onStopReminder: _stopReminder,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// UI COMPONENTS
// ══════════════════════════════════════════════════════════════

class _ScannerHeader extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onMute;
  const _ScannerHeader({required this.onClose, required this.onMute});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      color:   const Color(0xFF0A0F14),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Row(
        children: [
          IconButton(
            icon:      const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            onPressed: onClose,
            tooltip:   loc.t('stopReminder'),
          ),
          Expanded(
            child: Text(
              loc.t('medicationReminder'),
              style: const TextStyle(
                color:      Colors.white,
                fontSize:   18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon:      const Icon(Icons.volume_off_rounded,
                color: Colors.white70, size: 24),
            onPressed: onMute,
          ),
        ],
      ),
    );
  }
}

class _MedicineInfoCard extends StatelessWidget {
  final TodayDose dose;
  const _MedicineInfoCard({required this.dose});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color:        const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width:  46,
            height: 46,
            decoration: BoxDecoration(
              color:        AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.medication_rounded,
                color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.medicationName,
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dose.dosageDisplay,
                  style: TextStyle(
                    color:    AppColors.primary,
                    fontSize: 14,
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
                _formatTime(dose.scheduledTime),
                style: const TextStyle(
                  color:      Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize:   15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dose.isPast ? loc.t('overdue') : loc.t('dueSoon'),
                style: TextStyle(
                  color:    dose.isPast ? Colors.redAccent : Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h  = dt.hour   % 12 == 0 ? 12 : dt.hour   % 12;
    final m  = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

class _MedicineImage extends StatelessWidget {
  final String imageUrl;
  const _MedicineImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const _NoImagePlaceholder(),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded /
                progress.expectedTotalBytes!
                : null,
            color: AppColors.primary,
          ),
        );
      },
    );
  }
}

class _NoImagePlaceholder extends StatelessWidget {
  const _NoImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.medication_rounded, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(loc.t('noImageAvailable'),
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.white54),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final bool isMarkingTaken;
  final VoidCallback onMarkTaken;
  final VoidCallback onStopReminder;

  const _BottomPanel({
    required this.isMarkingTaken,
    required this.onMarkTaken,
    required this.onStopReminder,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        children: [
          SizedBox(
            width:  double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: isMarkingTaken ? null : onMarkTaken,
              icon: isMarkingTaken
                  ? const SizedBox(
                width:  18,
                height: 18,
                child:  CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white),
              )
                  : const Icon(Icons.check_circle_rounded, size: 20),
              label: Text(
                isMarkingTaken ? loc.t('saving') : loc.t('markAsTaken'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onStopReminder,
            child: Text(
              loc.t('stopReminder'),
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}