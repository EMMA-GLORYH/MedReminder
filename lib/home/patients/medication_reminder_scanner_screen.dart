// lib/screens/home/patients/medication_reminder_scanner_screen.dart

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/dose_log_service.dart';
import '../../services/medication_tts_service.dart';
import '../../services/schedule_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/snackbar/app_snackbar.dart';

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
    extends State<MedicationReminderScannerScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isPermissionGranted = false;
  bool _isVerified = false;
  bool _isMarkingTaken = false;

  @override
  void initState() {
    super.initState();
    _startTts();
    _initializeCamera();
  }

  Future<void> _startTts() async {
    await MedicationTtsService.instance.speakUntilStopped(
      message: 'It is time to take ${widget.dose.medicationName}. '
          'Dosage: ${widget.dose.dosageDisplay}. '
          'Please scan the medicine now.',
    );
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _isPermissionGranted = false);
      return;
    }

    setState(() => _isPermissionGranted = true);

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras[0], // Back camera
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  // Prevent user from closing screen until verified
  Future<bool> _onWillPop() async {
    if (_isVerified) return true;
    // Show warning if they try to leave before verification
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reminder Active'),
        content: const Text(
          'You must verify and mark this dose as taken before closing.\n\n'
              'Would you like to stop the reminder instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              MedicationTtsService.instance.stop();
              Navigator.pop(ctx, true);
            },
            child: const Text('Stop Reminder'),
          ),
        ],
      ),
    );

    return shouldLeave ?? false;
  }

  Future<void> _markAsTaken() async {
    setState(() => _isMarkingTaken = true);

    try {
      await DoseLogService.instance.markAsTaken(
        scheduleId: widget.dose.scheduleId,
        medicationId: widget.dose.medicationId,
        scheduledFor: widget.dose.scheduledTime,
      );

      if (!mounted) return;

      await MedicationTtsService.instance.stop();
      AppSnackbar.success(context, 'Dose marked as taken successfully');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Failed to mark dose. Please try again.');
      setState(() => _isMarkingTaken = false);
    }
  }

  void _stopReminder() {
    MedicationTtsService.instance.stop();
    _cameraController?.dispose();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dose = widget.dose;
    final hasImage = dose.pillImageUrl != null && dose.pillImageUrl!.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _stopReminder,
                    ),
                    const Expanded(
                      child: Text(
                        'Medication Reminder',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.volume_off, color: Colors.white),
                      onPressed: () => MedicationTtsService.instance.stop(),
                    ),
                  ],
                ),
              ),

              // Expected Medicine Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text(
                      'Take this medicine now',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dose.medicationName,
                      style: AppTextStyles.h2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      dose.dosageDisplay,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Expected Medicine Image
              if (hasImage)
                Container(
                  height: 140,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      dose.pillImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        size: 60,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  height: 140,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.medication_rounded,
                      size: 60,
                      color: Colors.white54,
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Live Camera Preview
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isVerified ? AppColors.primary : Colors.white24,
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: _buildCameraPreview(),
                  ),
                ),
              ),

              // Bottom Actions
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isVerified && !_isMarkingTaken
                            ? _markAsTaken
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isMarkingTaken
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'Mark as Taken',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _stopReminder,
                      child: Text(
                        'Stop Reminder',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white70,
                        ),
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
  }

  Widget _buildCameraPreview() {
    if (!_isPermissionGranted) {
      return const Center(
        child: Text(
          'Camera permission is required',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return CameraPreview(_cameraController!);
  }

}