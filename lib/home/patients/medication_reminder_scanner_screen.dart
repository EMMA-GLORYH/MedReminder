// lib/screens/home/patients/medication_reminder_scanner_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
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
  bool _isLoadingReference = true;
  bool _referenceReady = false;

  bool _isScanning = false;
  bool _isProcessingFrame = false;
  bool _isVerified = false;
  bool _isMarkingTaken = false;

  double _matchConfidence = 0.0;
  String _scanStatus = 'Preparing scanner...';

  _ImageSignature? _referenceSignature;

  DateTime _lastFrameProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _consecutiveMatches = 0;

  // Tune these if matching is too strict or too loose.
  static const double _matchThreshold = 0.62;
  static const int _requiredConsecutiveMatches = 3;
  static const Duration _frameInterval = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    _startTts();
    _prepareScanner();
  }

  Future<void> _startTts() async {
    await MedicationTtsService.instance.speakUntilStopped(
      message: 'It is time to take ${widget.dose.medicationName}. '
          'Dosage: ${widget.dose.dosageDisplay}. '
          'Please scan the medicine now.',
    );
  }

  Future<void> _prepareScanner() async {
    await _loadReferenceImage();
    await _initializeCamera();

    if (_referenceReady && _isCameraInitialized && mounted) {
      _startRealTimeMatching();
    }
  }

  Future<void> _loadReferenceImage() async {
    final imageUrl = widget.dose.pillImageUrl;

    if (imageUrl == null || imageUrl.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoadingReference = false;
        _referenceReady = false;
        _scanStatus = 'No reference image found for this medicine';
      });
      return;
    }

    try {
      setState(() {
        _isLoadingReference = true;
        _scanStatus = 'Loading saved medicine image...';
      });

      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Could not load reference image');
      }

      final decoded = img.decodeImage(response.bodyBytes);
      if (decoded == null) {
        throw Exception('Invalid medicine image');
      }

      final signature = _ImageMatcher.signatureFromImage(decoded);

      if (!mounted) return;

      setState(() {
        _referenceSignature = signature;
        _referenceReady = true;
        _isLoadingReference = false;
        _scanStatus = 'Reference image loaded. Preparing camera...';
      });
    } catch (e) {
      debugPrint('❌ Failed to load reference image: $e');
      if (!mounted) return;

      setState(() {
        _referenceReady = false;
        _isLoadingReference = false;
        _scanStatus = 'Could not load medicine reference image';
      });
    }
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();

    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _isPermissionGranted = false;
        _scanStatus = 'Camera permission is required';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isPermissionGranted = true;
      _scanStatus = 'Starting camera...';
    });

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (!mounted) return;
      setState(() => _scanStatus = 'No camera found');
      return;
    }

    final backCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _scanStatus = 'Position the medicine inside the frame';
      });
    } catch (e) {
      debugPrint('❌ Camera initialization error: $e');
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = false;
        _scanStatus = 'Could not start camera';
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (_isVerified) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reminder Active'),
        content: const Text(
          'You have not verified this medicine yet.\n\n'
              'Do you want to stop the reminder?',
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

  Future<void> _startRealTimeMatching() async {
    if (_isScanning) return;
    if (!_referenceReady || _referenceSignature == null) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isScanning = true;
      _scanStatus = 'AI scanning live camera feed...';
      _matchConfidence = 0.0;
      _consecutiveMatches = 0;
    });

    try {
      await _cameraController!.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('❌ Could not start image stream: $e');
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanStatus = 'Could not start AI scanner';
      });
    }
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (!_isScanning || _isVerified) return;
    if (_isProcessingFrame) return;

    final now = DateTime.now();
    if (now.difference(_lastFrameProcessedAt) < _frameInterval) return;

    _lastFrameProcessedAt = now;
    _isProcessingFrame = true;

    try {
      final liveSignature = _ImageMatcher.signatureFromCameraImage(image);
      final score = _ImageMatcher.compare(
        _referenceSignature!,
        liveSignature,
      );

      final confidence = (score * 100).clamp(0.0, 100.0);

      if (!mounted) return;

      setState(() {
        _matchConfidence = confidence;

        if (score >= _matchThreshold) {
          _consecutiveMatches++;
          _scanStatus =
          'Potential match detected ($_consecutiveMatches/$_requiredConsecutiveMatches)';
        } else {
          _consecutiveMatches = 0;
          _scanStatus = 'Scanning... align the medicine with the frame';
        }
      });

      if (_consecutiveMatches >= _requiredConsecutiveMatches) {
        await _verifyMedicine(confidence);
      }
    } catch (e) {
      debugPrint('⚠️ Frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _verifyMedicine(double confidence) async {
    if (_isVerified) return;

    try {
      if (_cameraController?.value.isStreamingImages == true) {
        await _cameraController?.stopImageStream();
      }
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _isVerified = true;
      _isScanning = false;
      _matchConfidence = confidence;
      _scanStatus = 'Medicine verified';
    });

    await MedicationTtsService.instance.speakUntilStopped(
      message:
      'Medicine verified. You can now mark ${widget.dose.medicationName} as taken.',
    );
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

  Future<void> _stopReminder() async {
    await MedicationTtsService.instance.stop();

    try {
      if (_cameraController?.value.isStreamingImages == true) {
        await _cameraController?.stopImageStream();
      }
    } catch (_) {}

    await _cameraController?.dispose();

    if (mounted) Navigator.pop(context);
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
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F14),
        body: SafeArea(
          child: Column(
            children: [
              _HeaderBar(
                onClose: _stopReminder,
                onMute: () => MedicationTtsService.instance.stop(),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text(
                      dose.medicationName,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dose.dosageDisplay,
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              if (hasImage)
                _ReferenceImageCard(imageUrl: dose.pillImageUrl!),

              const SizedBox(height: 16),

              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isVerified
                          ? AppColors.primary
                          : _isScanning
                          ? AppColors.primary.withValues(alpha: 0.65)
                          : Colors.white30,
                      width: 4,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildCameraPreview(),
                ),
              ),

              _BottomPanel(
                isLoadingReference: _isLoadingReference,
                referenceReady: _referenceReady,
                isScanning: _isScanning,
                isVerified: _isVerified,
                isMarkingTaken: _isMarkingTaken,
                confidence: _matchConfidence,
                scanStatus: _scanStatus,
                onStartScan: _startRealTimeMatching,
                onMarkTaken: _markAsTaken,
                onStopReminder: _stopReminder,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isPermissionGranted) {
      return const _ScannerMessage(
        icon: Icons.camera_alt_rounded,
        title: 'Camera permission required',
        subtitle: 'Allow camera access to verify your medicine.',
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),

        // Center guide frame
        Center(
          child: Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _isVerified
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.85),
                width: 3,
              ),
            ),
          ),
        ),

        // scanning overlay
        if (_isScanning)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.18),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'AI analyzing live feed...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        if (_isVerified)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 90,
                      color: AppColors.primary,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Medicine Verified',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// IMAGE MATCHING ENGINE
// ══════════════════════════════════════════════════════════════

class _ImageSignature {
  final double r;
  final double g;
  final double b;
  final double brightness;
  final List<double> histogram;

  const _ImageSignature({
    required this.r,
    required this.g,
    required this.b,
    required this.brightness,
    required this.histogram,
  });
}

class _ImageMatcher {
  static const int _histSize = 64;

  static _ImageSignature signatureFromImage(img.Image source) {
    final image = img.copyResize(
      source,
      width: 180,
      height: 180,
      interpolation: img.Interpolation.average,
    );

    final hist = List<double>.filled(_histSize, 0);
    double rSum = 0;
    double gSum = 0;
    double bSum = 0;
    double brightnessSum = 0;
    int count = 0;

    final startX = image.width ~/ 5;
    final endX = image.width - startX;
    final startY = image.height ~/ 5;
    final endY = image.height - startY;

    for (int y = startY; y < endY; y += 3) {
      for (int x = startX; x < endX; x += 3) {
        final p = image.getPixel(x, y);

        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();

        _accumulate(hist, r, g, b);

        rSum += r;
        gSum += g;
        bSum += b;
        brightnessSum += (r + g + b) / 3.0;
        count++;
      }
    }

    return _normalizeSignature(
      hist: hist,
      rSum: rSum,
      gSum: gSum,
      bSum: bSum,
      brightnessSum: brightnessSum,
      count: count,
    );
  }

  static _ImageSignature signatureFromCameraImage(CameraImage image) {
    final hist = List<double>.filled(_histSize, 0);

    double rSum = 0;
    double gSum = 0;
    double bSum = 0;
    double brightnessSum = 0;
    int count = 0;

    final width = image.width;
    final height = image.height;

    final startX = width ~/ 4;
    final endX = width - startX;
    final startY = height ~/ 4;
    final endY = height - startY;

    if (image.format.group == ImageFormatGroup.yuv420) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final yRowStride = yPlane.bytesPerRow;
      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (int y = startY; y < endY; y += 12) {
        for (int x = startX; x < endX; x += 12) {
          final yIndex = y * yRowStride + x;
          final uvIndex =
              (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          if (yIndex >= yBytes.length ||
              uvIndex >= uBytes.length ||
              uvIndex >= vBytes.length) {
            continue;
          }

          final yy = yBytes[yIndex].toDouble();
          final uu = uBytes[uvIndex].toDouble() - 128.0;
          final vv = vBytes[uvIndex].toDouble() - 128.0;

          final r = (yy + 1.402 * vv).clamp(0.0, 255.0);
          final g = (yy - 0.344136 * uu - 0.714136 * vv).clamp(0.0, 255.0);
          final b = (yy + 1.772 * uu).clamp(0.0, 255.0);

          _accumulate(hist, r, g, b);

          rSum += r;
          gSum += g;
          bSum += b;
          brightnessSum += (r + g + b) / 3.0;
          count++;
        }
      }
    } else {
      // Unsupported camera format fallback.
      // Returning a weak neutral signature keeps scanner stable.
      return _ImageSignature(
        r: 128,
        g: 128,
        b: 128,
        brightness: 128,
        histogram: List<double>.filled(_histSize, 1 / _histSize),
      );
    }

    return _normalizeSignature(
      hist: hist,
      rSum: rSum,
      gSum: gSum,
      bSum: bSum,
      brightnessSum: brightnessSum,
      count: count,
    );
  }

  static void _accumulate(List<double> hist, double r, double g, double b) {
    final rb = (r ~/ 64).clamp(0, 3);
    final gb = (g ~/ 64).clamp(0, 3);
    final bb = (b ~/ 64).clamp(0, 3);

    final index = rb * 16 + gb * 4 + bb;
    hist[index] += 1;
  }

  static _ImageSignature _normalizeSignature({
    required List<double> hist,
    required double rSum,
    required double gSum,
    required double bSum,
    required double brightnessSum,
    required int count,
  }) {
    if (count <= 0) {
      return _ImageSignature(
        r: 128,
        g: 128,
        b: 128,
        brightness: 128,
        histogram: List<double>.filled(_histSize, 1 / _histSize),
      );
    }

    for (int i = 0; i < hist.length; i++) {
      hist[i] = hist[i] / count;
    }

    return _ImageSignature(
      r: rSum / count,
      g: gSum / count,
      b: bSum / count,
      brightness: brightnessSum / count,
      histogram: hist,
    );
  }

  static double compare(_ImageSignature a, _ImageSignature b) {
    final histScore = _cosineSimilarity(a.histogram, b.histogram);

    final colorDistance = math.sqrt(
      math.pow(a.r - b.r, 2) +
          math.pow(a.g - b.g, 2) +
          math.pow(a.b - b.b, 2),
    );

    final colorScore = (1.0 - (colorDistance / 441.67)).clamp(0.0, 1.0);

    final brightnessDiff = (a.brightness - b.brightness).abs();
    final brightnessScore = (1.0 - (brightnessDiff / 255.0)).clamp(0.0, 1.0);

    return (histScore * 0.55) +
        (colorScore * 0.35) +
        (brightnessScore * 0.10);
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}

// ══════════════════════════════════════════════════════════════
// UI COMPONENTS
// ══════════════════════════════════════════════════════════════

class _HeaderBar extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onMute;

  const _HeaderBar({
    required this.onClose,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0F14),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: onClose,
          ),
          const Expanded(
            child: Text(
              'AI Medicine Verification',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.volume_off, color: Colors.white),
            onPressed: onMute,
          ),
        ],
      ),
    );
  }
}

class _ReferenceImageCard extends StatelessWidget {
  final String imageUrl;

  const _ReferenceImageCard({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 135,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final bool isLoadingReference;
  final bool referenceReady;
  final bool isScanning;
  final bool isVerified;
  final bool isMarkingTaken;
  final double confidence;
  final String scanStatus;
  final VoidCallback onStartScan;
  final VoidCallback onMarkTaken;
  final VoidCallback onStopReminder;

  const _BottomPanel({
    required this.isLoadingReference,
    required this.referenceReady,
    required this.isScanning,
    required this.isVerified,
    required this.isMarkingTaken,
    required this.confidence,
    required this.scanStatus,
    required this.onStartScan,
    required this.onMarkTaken,
    required this.onStopReminder,
  });

  @override
  Widget build(BuildContext context) {
    final canStart = !isLoadingReference && referenceReady && !isScanning;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            scanStatus,
            style: TextStyle(
              color: isVerified ? AppColors.primary : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),

          if (isScanning || isVerified) ...[
            const SizedBox(height: 8),
            Text(
              'Match Confidence: ${confidence.toStringAsFixed(1)}%',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],

          const SizedBox(height: 14),

          if (!isVerified)
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: canStart ? onStartScan : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isScanning
                    ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('AI Scanning Live...'),
                  ],
                )
                    : const Text(
                  'Start Real-Time AI Scan',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          if (isVerified)
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: isMarkingTaken ? null : onMarkTaken,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isMarkingTaken
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  'Mark as Taken',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: onStopReminder,
            child: const Text(
              'Stop Reminder',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ScannerMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 58),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}