// lib/widgets/buttons/sos_alert.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mar/services/auth_service.dart';
import 'package:mar/services/sos_service.dart';
import 'package:mar/theme/app_colors.dart';
import 'package:mar/theme/app_text_styles.dart';
import 'package:url_launcher/url_launcher.dart';

class SosAlertButton extends StatefulWidget {
  const SosAlertButton({super.key});

  @override
  State<SosAlertButton> createState() => _SosAlertButtonState();
}

class _SosAlertButtonState extends State<SosAlertButton>
    with TickerProviderStateMixin {
  static const Duration _holdDuration = Duration(seconds: 5);
  static const double _buttonSize = 72;

  final GlobalKey _buttonKey = GlobalKey();

  late final AnimationController _fillController;
  late final AnimationController _waveController;

  late final Animation<double> _wave1;
  late final Animation<double> _wave2;
  late final Animation<double> _wave3;

  OverlayEntry? _radiationOverlay;

  Timer? _holdTimer;
  Timer? _holdHapticTimer;
  Stopwatch? _holdStopwatch;

  bool _isPressing = false;
  bool _isSending = false;
  bool _triggeredThisHold = false;

  @override
  void initState() {
    super.initState();

    _fillController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _wave1 = CurvedAnimation(
      parent: _waveController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _wave2 = CurvedAnimation(
      parent: _waveController,
      curve: const Interval(0.2, 0.9, curve: Curves.easeOut),
    );

    _wave3 = CurvedAnimation(
      parent: _waveController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _holdHapticTimer?.cancel();
    _holdStopwatch?.stop();
    _removeRadiationOverlay();
    _fillController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _beginHold() {
    if (_isSending || _isPressing) return;

    HapticFeedback.mediumImpact();

    _holdTimer?.cancel();
    _holdHapticTimer?.cancel();
    _holdStopwatch?.stop();

    _triggeredThisHold = false;
    _holdStopwatch = Stopwatch()..start();

    setState(() => _isPressing = true);

    _showRadiationOverlay();

    _fillController.forward(from: 0);

    _waveController
      ..reset()
      ..repeat();

    _holdHapticTimer = Timer.periodic(
      const Duration(milliseconds: 850),
          (_) {
        if (_isPressing && !_isSending) {
          HapticFeedback.selectionClick();
        }
      },
    );

    _armHoldTimer(_holdDuration);
  }

  void _armHoldTimer(Duration delay) {
    _holdTimer?.cancel();

    _holdTimer = Timer(delay, () {
      if (!_isPressing || _isSending || _triggeredThisHold) return;

      final elapsed = _holdStopwatch?.elapsed ?? Duration.zero;

      if (elapsed < _holdDuration) {
        _armHoldTimer(_holdDuration - elapsed);
        return;
      }

      _triggeredThisHold = true;
      _holdStopwatch?.stop();
      _triggerSos();
    });
  }

  void _releaseHold() {
    if (!_isPressing || _isSending) return;

    _holdTimer?.cancel();
    _holdHapticTimer?.cancel();
    _holdStopwatch?.stop();

    setState(() => _isPressing = false);

    _waveController
      ..stop()
      ..reset();

    if (!_triggeredThisHold) {
      _fillController
          .animateBack(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      )
          .then((_) {
        if (!mounted) return;
        if (!_isPressing && !_isSending) {
          _removeRadiationOverlay();
        }
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isPressing || _isSending) return;

    final renderObject = _buttonKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bounds = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      renderObject.size.width,
      renderObject.size.height,
    ).inflate(12);

    if (!bounds.contains(event.position)) {
      _releaseHold();
    }
  }

  void _showRadiationOverlay() {
    _removeRadiationOverlay();

    final renderObject = _buttonKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final buttonCenter =
    renderObject.localToGlobal(renderObject.size.center(Offset.zero));

    final overlayState = Overlay.of(context, rootOverlay: true);

    _radiationOverlay = OverlayEntry(
      builder: (_) {
        return Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _fillController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _ScreenRadiationPainter(
                    origin: buttonCenter,
                    progress: _fillController.value,
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    overlayState.insert(_radiationOverlay!);
  }

  void _removeRadiationOverlay() {
    _radiationOverlay?.remove();
    _radiationOverlay = null;
  }

  void _finishRadiation() {
    _removeRadiationOverlay();
    if (_fillController.isAnimating) _fillController.stop();
    _fillController.reset();
  }

  // ══════════════════════════════════════════════════════════════
  // SOS DISPATCH — alarm plays ONLY on the caretaker's phone,
  // NOT on the patient's phone. The caretaker receives the SOS
  // via SosRealtimeService.kt (native WebSocket) which fires
  // TtsSpeakService directly.
  // ══════════════════════════════════════════════════════════════
  Future<void> _triggerSos() async {
    if (_isSending) return;

    _holdTimer?.cancel();
    _holdHapticTimer?.cancel();
    _holdStopwatch?.stop();

    HapticFeedback.heavyImpact();

    _waveController
      ..stop()
      ..reset();

    _fillController
      ..stop()
      ..value = 1;

    if (mounted) {
      setState(() {
        _isSending = true;
        _isPressing = false;
      });
    }

    try {
      final result = await SosService.instance.sendSos();

      if (!mounted) return;

      final caretakerCount = result.caretakerCount;
      final callableCaretaker = result.firstCallableCaretaker;

      // ❌ REMOVED: The SOS alarm no longer plays on the patient's phone.
      // The caretaker's phone receives the SOS via the native WebSocket
      // service and plays caretaker_sos.mp3 there.

      _finishRadiation();

      _showResult(
        success: true,
        title: 'SOS Sent!',
        message: caretakerCount == 1
            ? 'Your caretaker has been alerted.\nPlease stay where you are.'
            : '$caretakerCount caretakers have been alerted.\nPlease stay where you are.',
        callContact: callableCaretaker,
      );
    } on SosDispatchException catch (error) {
      if (!mounted) return;
      _finishRadiation();
      _showResult(
        success: false,
        title: 'SOS Not Sent',
        message: error.message,
      );
    } catch (error, stack) {
      debugPrint('❌ SOS button error: $error');
      debugPrint('$stack');

      if (!mounted) return;
      _finishRadiation();
      _showResult(
        success: false,
        title: 'SOS Failed',
        message: 'Could not send the SOS.\n'
            'Please try again or call for help directly.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _callCaretaker(SosCaretakerContact caretaker) async {
    final phone = caretaker.phoneNumber?.trim();
    if (phone == null || phone.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showResult({
    required bool success,
    required String title,
    required String message,
    SosCaretakerContact? callContact,
  }) {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _SosResultDialog(
          success: success,
          title: title,
          message: message,
          caretakerName: callContact?.name,
          onCall: callContact == null ? null : () => _callCaretaker(callContact),
          onDismiss: () {
            // No need to stop SosSpeechService since it was never started
            // on the patient's phone.
          },
        );
      },
    );
  }

  int get _remainingSeconds {
    if (!_isPressing) return 5;
    final remaining = (1 - _fillController.value) * _holdDuration.inSeconds;
    return math.max(1, remaining.ceil());
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Emergency SOS. Press and hold for five seconds.',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _beginHold(),
        onPointerMove: _handlePointerMove,
        onPointerUp: (_) => _releaseHold(),
        onPointerCancel: (_) => _releaseHold(),
        child: AnimatedBuilder(
          animation: Listenable.merge([_fillController, _waveController]),
          builder: (context, _) {
            return SizedBox(
              key: _buttonKey,
              width: _buttonSize + 80,
              height: _buttonSize + 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isPressing || _isSending) ...[
                    _RadioWave(
                      progress: _wave1.value,
                      baseSize: _buttonSize,
                      maxExtra: 70,
                    ),
                    _RadioWave(
                      progress: _wave2.value,
                      baseSize: _buttonSize,
                      maxExtra: 55,
                    ),
                    _RadioWave(
                      progress: _wave3.value,
                      baseSize: _buttonSize,
                      maxExtra: 38,
                    ),
                  ],
                  SizedBox(
                    width: _buttonSize + 12,
                    height: _buttonSize + 12,
                    child: CircularProgressIndicator(
                      value: _fillController.value,
                      strokeWidth: 5,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: _isPressing ? _buttonSize - 6 : _buttonSize,
                    height: _isPressing ? _buttonSize - 6 : _buttonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isSending
                          ? Colors.orange
                          : const Color(0xFFCC0000),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFCC0000).withValues(
                            alpha: _isPressing ? 0.75 : 0.50,
                          ),
                          blurRadius: _isPressing ? 32 : 18,
                          spreadRadius: _isPressing ? 6 : 1,
                        ),
                      ],
                    ),
                    child: _isSending
                        ? const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                        : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.sos_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isPressing
                              ? '${_remainingSeconds}S'
                              : 'HOLD 5S',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// FULL-SCREEN RADIATION PAINTER
// ══════════════════════════════════════════════════════════════

class _ScreenRadiationPainter extends CustomPainter {
  final Offset origin;
  final double progress;

  const _ScreenRadiationPainter({
    required this.origin,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final linearProgress = progress.clamp(0.0, 1.0);

    final corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];

    double maximumRadius = 0;
    for (final corner in corners) {
      maximumRadius =
          math.max(maximumRadius, (corner - origin).distance);
    }

    final currentRadius = maximumRadius * linearProgress;

    final radiationPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFCC0000).withValues(alpha: 0.30),
          const Color(0xFFCC0000).withValues(alpha: 0.17),
          const Color(0xFFCC0000).withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.78, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: origin,
          radius: math.max(currentRadius, 1),
        ),
      );

    canvas.drawCircle(origin, currentRadius, radiationPaint);

    final screenTint = Paint()
      ..color = const Color(0xFFCC0000).withValues(
        alpha: 0.08 * linearProgress,
      );

    canvas.drawRect(Offset.zero & size, screenTint);

    for (int index = 0; index < 4; index++) {
      final delay = index * 0.14;
      final denominator = 1 - delay;
      final phase = denominator <= 0
          ? 0.0
          : ((linearProgress - delay) / denominator).clamp(0.0, 1.0);

      if (phase <= 0) continue;

      final ringRadius = maximumRadius * Curves.easeOut.transform(phase);
      final opacity = (1 - phase).clamp(0.0, 1.0);

      canvas.drawCircle(
        origin,
        ringRadius,
        Paint()
          ..color = const Color(0xFFFF3030).withValues(alpha: opacity * 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenRadiationPainter oldDelegate) {
    return oldDelegate.origin != origin || oldDelegate.progress != progress;
  }
}

// ══════════════════════════════════════════════════════════════
// LOCAL BUTTON RADIO WAVE
// ══════════════════════════════════════════════════════════════

class _RadioWave extends StatelessWidget {
  final double progress;
  final double baseSize;
  final double maxExtra;

  const _RadioWave({
    required this.progress,
    required this.baseSize,
    required this.maxExtra,
  });

  @override
  Widget build(BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();

    final size = baseSize + maxExtra * progress;
    final opacity = (1 - progress).clamp(0.0, 1.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFCC0000).withValues(alpha: opacity * 0.60),
          width: 2.5,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SOS RESULT DIALOG
// ══════════════════════════════════════════════════════════════

class _SosResultDialog extends StatelessWidget {
  final bool success;
  final String title;
  final String message;
  final String? caretakerName;
  final VoidCallback? onCall;
  final VoidCallback? onDismiss;

  const _SosResultDialog({
    required this.success,
    required this.title,
    required this.message,
    this.caretakerName,
    this.onCall,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF00C853) : AppColors.error;
    final icon = success ? Icons.check_circle_rounded : Icons.error_rounded;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.withValues(alpha: 0.40),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 40,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.40)),
              ),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: AppTextStyles.h2.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            if (onCall != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call_rounded),
                  label: Text(
                    caretakerName == null
                        ? 'Call Caretaker'
                        : 'Call $caretakerName',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.30),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  onDismiss?.call();
                  Navigator.pop(context);
                },
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}