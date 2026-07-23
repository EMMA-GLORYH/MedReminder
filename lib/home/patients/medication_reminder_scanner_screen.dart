// lib/screens/home/patients/medication_reminder_scanner_screen.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../localization/app_localizations.dart';
import '../../services/dose_log_service.dart';
import '../../services/local_notification_service.dart';
import '../../services/medication_tts_service.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/snackbar/app_snackbar.dart';

// ══════════════════════════════════════════════════════════════
// MEDICATION REMINDER SCREEN (offline-capable pill image)
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isMarkingTaken = false;
  bool _ttsStarted = false;
  bool _imageLoadStarted = false;
  bool _imageLoadFailed = false;
  bool _isScreenReady = false;

  ImageProvider? _imageProvider;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  Timer? _ttsRetryTimer;
  int _ttsRetryCount = 0;
  static const int _maxTtsRetries = 5;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 MedicationReminderScannerScreen - INIT');
    debugPrint('📋 Dose: ${widget.dose.medicationName}');
    debugPrint('📋 Scheduled Time: ${widget.dose.scheduledTime}');
    debugPrint('📋 Patient ID: ${widget.dose.patientId}');

    // Register as lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.35,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Force screen to be ready after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isScreenReady = true;
      });
      _startTts();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint('🔄 didChangeDependencies called');

    if (!_imageLoadStarted) {
      _imageLoadStarted = true;
      debugPrint('  ➡️ Loading pill image...');
      _loadPillImageOfflineFirst();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('🔄 App lifecycle state: $state');

    if (state == AppLifecycleState.resumed) {
      debugPrint('  ➡️ App resumed, restarting TTS if needed');
      _startTts();
    }
  }

  // ══════════════════════════════════════════════════════════════
  // FORCE START TTS WITH RETRY
  // ══════════════════════════════════════════════════════════════

  Future<void> _startTts() async {
    if (!_isScreenReady) {
      debugPrint('⏭️ Screen not ready yet, waiting...');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startTts();
      });
      return;
    }

    if (_ttsStarted) {
      debugPrint('⏭️ TTS already started, skipping');
      return;
    }

    if (_ttsRetryCount >= _maxTtsRetries) {
      debugPrint('❌ Max TTS retries reached (${_maxTtsRetries}), giving up');
      return;
    }

    _ttsRetryCount++;
    debugPrint('🎤 Force starting TTS for ${widget.dose.medicationName} (attempt $_ttsRetryCount/$_maxTtsRetries)');

    try {
      final loc = AppLocalizations.of(context);
      String message;

      try {
        message = loc.t(
          'ttsReminderMessage',
          <String, String>{
            'name': widget.dose.medicationName,
            'dosage': widget.dose.dosageDisplay,
          },
        );
      } catch (e) {
        // Fallback if localization fails
        message = 'Time to take ${widget.dose.medicationName}. '
            'Dosage: ${widget.dose.dosageDisplay}. '
            'Please confirm your medicine now.';
      }

      debugPrint('  📢 Message: $message');

      // First, stop any existing TTS from native
      await MedicationTtsService.instance.stop();
      debugPrint('  ✅ Previous TTS stopped');

      // Small delay to ensure clean state
      await Future.delayed(const Duration(milliseconds: 300));

      // Start Flutter-side TTS
      await MedicationTtsService.instance.speakUntilStopped(
        message: message,
      );

      _ttsStarted = true;
      _ttsRetryCount = 0;
      debugPrint('  ✅ TTS started successfully!');

    } catch (e) {
      debugPrint('❌ TTS start failed: $e');
      _ttsStarted = false;

      // Retry after delay
      if (_ttsRetryCount < _maxTtsRetries) {
        final delay = Duration(seconds: _ttsRetryCount * 2);
        debugPrint('  🔄 Retrying TTS in ${delay.inSeconds} seconds');

        _ttsRetryTimer?.cancel();
        _ttsRetryTimer = Timer(delay, () {
          if (mounted) {
            _startTts();
          }
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // OFFLINE-CAPABLE IMAGE LOADING
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadPillImageOfflineFirst() async {
    final url = widget.dose.pillImageUrl?.trim();
    debugPrint('📸 Loading pill image from URL: $url');

    if (url == null || url.isEmpty) {
      debugPrint('❌ No image URL available');
      if (mounted) setState(() => _imageLoadFailed = true);
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      debugPrint('❌ Invalid image URL: $url');
      if (mounted) setState(() => _imageLoadFailed = true);
      return;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      debugPrint('❌ Unsupported URL scheme: ${uri.scheme}');
      if (mounted) setState(() => _imageLoadFailed = true);
      return;
    }

    try {
      final file = await _getCachedImageFile(url);
      debugPrint('  - Cache file path: ${file.path}');

      if (await file.exists()) {
        debugPrint('  ✅ Image found in cache');
        if (mounted) {
          setState(() {
            _imageProvider = FileImage(file);
            _imageLoadFailed = false;
          });
        }
        return;
      }

      debugPrint('  ⬇️ Image not in cache, downloading...');
      final bytes = await _downloadBytes(uri).timeout(
        const Duration(seconds: 10),
      );
      debugPrint('  ✅ Image downloaded successfully (${bytes.length} bytes)');

      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      debugPrint('  ✅ Image saved to cache');

      if (mounted) {
        setState(() {
          _imageProvider = FileImage(file);
          _imageLoadFailed = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Image loading failed: $e');
      if (mounted) setState(() {
        _imageLoadFailed = true;
        _imageProvider = null;
      });
    }
  }

  Future<File> _getCachedImageFile(String url) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pill_images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ext = _inferFileExtension(url) ?? '.img';
    final name = url.hashCode.toString();

    return File('${dir.path}/$name$ext');
  }

  String? _inferFileExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (!last.contains('.')) return null;

      final dot = last.lastIndexOf('.');
      if (dot < 0 || dot == last.length - 1) return null;

      return last.substring(dot);
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _downloadBytes(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      return await response.fold<List<int>>(
        <int>[],
            (prev, chunk) => prev..addAll(chunk),
      );
    } finally {
      client.close(force: true);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // RETRY SCHEDULING
  // ══════════════════════════════════════════════════════════════

  Future<void> _scheduleRetryAfterStop() async {
    final patientId = widget.dose.patientId?.trim();
    debugPrint('⏰ Scheduling retry for patient: $patientId');

    if (patientId == null || patientId.isEmpty) {
      debugPrint('⚠️ Medication retry not scheduled: patientId is missing');
      return;
    }

    try {
      await LocalNotificationService.instance.scheduleDoseRetry(
        patientId: patientId,
        scheduleId: widget.dose.scheduleId,
        medicationId: widget.dose.medicationId,
        medicationName: widget.dose.medicationName,
        dosageDisplay: widget.dose.dosageDisplay,
        scheduledFor: widget.dose.scheduledTime,
        pillImageUrl: widget.dose.pillImageUrl,
      );
      debugPrint('✅ Retry scheduled successfully');
    } catch (error, stack) {
      debugPrint('⚠️ Could not schedule medication retry: $error');
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // STOP REMINDER
  // ══════════════════════════════════════════════════════════════

  Future<void> _stopReminder() async {
    debugPrint('🛑 Stopping reminder for ${widget.dose.medicationName}');

    // Stop TTS
    await MedicationTtsService.instance.stop();
    _ttsStarted = false;
    _ttsRetryTimer?.cancel();
    debugPrint('  ✅ TTS stopped');

    await _scheduleRetryAfterStop();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BACK-PRESS GUARD
  // ══════════════════════════════════════════════════════════════

  Future<bool> _onWillPop() async {
    final loc = AppLocalizations.of(context);
    debugPrint('🔙 Back pressed, showing confirmation dialog');

    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2232),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            loc.t('reminderActiveTitle'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            loc.t('reminderActiveBody'),
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, false);
                }
              },
              child: Text(
                loc.t('cancel'),
                style: const TextStyle(
                  color: Colors.white54,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: Text(
                loc.t('stopReminder'),
              ),
            ),
          ],
        );
      },
    );

    return leave ?? false;
  }

  // ══════════════════════════════════════════════════════════════
  // MARK AS TAKEN
  // ══════════════════════════════════════════════════════════════

  Future<void> _markAsTaken() async {
    if (_isMarkingTaken) return;

    final loc = AppLocalizations.of(context);
    debugPrint('✅ Marking as taken: ${widget.dose.medicationName}');

    setState(() {
      _isMarkingTaken = true;
    });

    try {
      await DoseLogService.instance.markAsTaken(
        scheduleId: widget.dose.scheduleId,
        medicationId: widget.dose.medicationId,
        scheduledFor: widget.dose.scheduledTime,
        patientId: widget.dose.patientId,
      );

      // Stop everything
      await MedicationTtsService.instance.stop();
      _ttsStarted = false;
      _ttsRetryTimer?.cancel();

      if (!mounted) return;

      AppSnackbar.success(context, loc.t('doseMarkedTaken'));
      Navigator.pop(context, true);
    } catch (error, stack) {
      debugPrint('❌ Failed to mark medication dose as taken: $error');
      debugPrint('$stack');

      if (!mounted) return;

      AppSnackbar.error(context, loc.t('failedToMarkDose'));
      setState(() {
        _isMarkingTaken = false;
      });
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 MedicationReminderScannerScreen - DISPOSE');
    debugPrint('  - TTS Started: $_ttsStarted');

    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Stop everything
    if (_ttsStarted) {
      MedicationTtsService.instance.stop();
      _ttsStarted = false;
      debugPrint('  ✅ TTS stopped on dispose');
    }

    _ttsRetryTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🏗️ Building MedicationReminderScannerScreen');

    final dose = widget.dose;
    final imageUrl = dose.pillImageUrl?.trim();

    final canShowImage = _imageProvider != null;
    final hasUrl = imageUrl != null && imageUrl.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (
          bool didPop,
          Object? result,
          ) async {
        if (didPop) return;

        final shouldLeave = await _onWillPop();
        if (shouldLeave && mounted) {
          await _stopReminder();
        }
      },
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) {
          final pulseValue = _pulseAnimation.value;

          return Scaffold(
            backgroundColor: const Color(0xFF0A0F14),
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                SafeArea(
                  child: Column(
                    children: <Widget>[
                      _ScannerHeader(
                        onClose: () async {
                          final shouldLeave = await _onWillPop();
                          if (shouldLeave && mounted) {
                            await _stopReminder();
                          }
                        },
                        onMute: () {
                          debugPrint('🔇 Mute button pressed');
                          MedicationTtsService.instance.stop();
                          _ttsStarted = false;
                        },
                      ),
                      _MedicineInfoCard(dose: dose, pulseValue: pulseValue),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppColors.primary.withValues(
                                  alpha: 0.25 + (0.55 * pulseValue),
                                ),
                                width: 4,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12 + (0.25 * pulseValue),
                                  ),
                                  blurRadius: 18 + (18 * pulseValue),
                                  spreadRadius: 2 + (5 * pulseValue),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: _buildImageChild(
                                key: ValueKey(_imageProvider != null),
                                canShowImage: canShowImage,
                                hasUrl: hasUrl,
                                loading: _imageProvider == null && hasUrl,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _BottomPanel(
                        isMarkingTaken: _isMarkingTaken,
                        onMarkTaken: _markAsTaken,
                        onStopReminder: _stopReminder,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageChild({
    required Key key,
    required bool canShowImage,
    required bool hasUrl,
    required bool loading,
  }) {
    if (canShowImage) {
      return Image(
        key: key,
        image: _imageProvider!,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    }

    if (loading) {
      return Container(
        key: key,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Loading medicine image…',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return const _NoImagePlaceholder(key: ValueKey('no-image'));
  }
}

// ══════════════════════════════════════════════════════════════
// UI COMPONENTS
// ══════════════════════════════════════════════════════════════

class _ScannerHeader extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onMute;

  const _ScannerHeader({
    required this.onClose,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0F14),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 26,
            ),
            onPressed: onClose,
            tooltip: 'Stop Reminder',
          ),
          Expanded(
            child: Text(
              'Medication Reminder',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.volume_off_rounded,
              color: Colors.white70,
              size: 24,
            ),
            onPressed: onMute,
            tooltip: 'Mute',
          ),
        ],
      ),
    );
  }
}

class _MedicineInfoCard extends StatelessWidget {
  final TodayDose dose;
  final double pulseValue;

  const _MedicineInfoCard({
    required this.dose,
    required this.pulseValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(
            alpha: 0.22 + (0.35 * pulseValue),
          ),
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(
              alpha: 0.08 + (0.12 * pulseValue),
            ),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.medication_rounded,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  dose.medicationName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dose.dosageDisplay,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                _formatTime(dose.scheduledTime),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dose.isPast ? 'Overdue' : 'Due Soon',
                style: TextStyle(
                  color: dose.isPast
                      ? Colors.redAccent
                      : Colors.greenAccent,
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

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

class _NoImagePlaceholder extends StatelessWidget {
  const _NoImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.medication_rounded,
              color: Colors.white38,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No image available',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: isMarkingTaken ? null : onMarkTaken,
              icon: isMarkingTaken
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
                  : const Icon(
                Icons.check_circle_rounded,
                size: 20,
              ),
              label: Text(
                isMarkingTaken ? 'Saving...' : 'Mark as Taken',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                AppColors.primary.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onStopReminder,
            child: Text(
              'Stop Reminder',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}