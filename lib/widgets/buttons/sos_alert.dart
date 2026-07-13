// lib/widgets/buttons/sos_alert.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../main.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

// ══════════════════════════════════════════════════════════════
// PUBLIC WIDGET — drop this anywhere in a Stack
// ══════════════════════════════════════════════════════════════
class SosAlertButton extends StatefulWidget {
  const SosAlertButton({super.key});

  @override
  State<SosAlertButton> createState() => _SosAlertButtonState();
}

class _SosAlertButtonState extends State<SosAlertButton>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 3);
  static const _buttonSize   = 72.0;

  // ── Ring fill (0 → 1 over 3 s) ──
  late final AnimationController _fillCtrl;

  // ── Radio wave pulses — 3 ripple rings ──
  late final AnimationController _waveCtrl;
  late final Animation<double>   _wave1;
  late final Animation<double>   _wave2;
  late final Animation<double>   _wave3;

  bool _isPressing = false;
  bool _isSending  = false;

  @override
  void initState() {
    super.initState();

    // Fill ring
    _fillCtrl = AnimationController(vsync: this, duration: _holdDuration);
    _fillCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _triggerSos();
    });

    // Radio waves — staggered repeating
    _waveCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1400),
    );

    _wave1 = CurvedAnimation(
      parent: _waveCtrl,
      curve:  const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _wave2 = CurvedAnimation(
      parent: _waveCtrl,
      curve:  const Interval(0.2, 0.9, curve: Curves.easeOut),
    );
    _wave3 = CurvedAnimation(
      parent: _waveCtrl,
      curve:  const Interval(0.4, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _fillCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  // ── Press handlers ───────────────────────────────────────────
  void _onDown(_) {
    if (_isSending) return;
    HapticFeedback.mediumImpact();
    setState(() => _isPressing = true);
    _fillCtrl.forward();
    _waveCtrl.repeat();
  }

  void _onUp(_) {
    if (_isSending) return;
    if (_fillCtrl.status != AnimationStatus.completed) {
      _fillCtrl.reverse();
      _waveCtrl.stop();
      _waveCtrl.reset();
    }
    setState(() => _isPressing = false);
  }

  // ── Fire SOS ─────────────────────────────────────────────────
  Future<void> _triggerSos() async {
    if (_isSending) return;
    HapticFeedback.heavyImpact();
    _waveCtrl.stop();
    _waveCtrl.reset();
    setState(() { _isSending = true; _isPressing = false; });

    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final latestLog = await supabase
          .from('dose_logs')
          .select('id')
          .eq('patient_id', userId)
          .order('logged_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latestLog == null) {
        _showResult(
          success: false,
          message: 'No dose history found.\nLog at least one dose before using SOS.',
        );
        return;
      }

      await supabase.from('escalation_events').insert({
        'dose_log_id':     latestLog['id'],
        'patient_id':      userId,
        'escalation_step': 1,
        'channel':         'alarm',
        'sent_to':         null,
        'delivery_status': 'sent',
        'resolved':        false,
      });

      _showResult(
        success: true,
        message: 'Your caretaker has been notified.\nHelp is on the way.',
      );
    } catch (e) {
      debugPrint('❌ SOS error: $e');
      _showResult(
        success: false,
        message: 'Could not send SOS.\nPlease try again or call for help directly.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _fillCtrl.reset();
      }
    }
  }

  void _showResult({required bool success, required String message}) {
    if (!mounted) return;
    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (_) => _SosResultDialog(success: success, message: message),
    );
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   _onDown,
      onTapUp:     _onUp,
      onTapCancel: () => _onUp(null),
      child: AnimatedBuilder(
        animation: Listenable.merge([_fillCtrl, _waveCtrl]),
        builder: (context, _) {
          return SizedBox(
            // Extra room for the outermost radio wave ring
            width:  _buttonSize + 80,
            height: _buttonSize + 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── Radio wave rings (only while pressing) ──
                if (_isPressing || _isSending) ...[
                  _RadioWave(progress: _wave1.value, baseSize: _buttonSize, maxExtra: 70),
                  _RadioWave(progress: _wave2.value, baseSize: _buttonSize, maxExtra: 55),
                  _RadioWave(progress: _wave3.value, baseSize: _buttonSize, maxExtra: 38),
                ],

                // ── Fill ring ──
                SizedBox(
                  width:  _buttonSize + 12,
                  height: _buttonSize + 12,
                  child: CircularProgressIndicator(
                    value:           _fillCtrl.value,
                    strokeWidth:     5,
                    valueColor:      const AlwaysStoppedAnimation(Colors.white),
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                  ),
                ),

                // ── Button body ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width:  _isPressing ? _buttonSize - 6 : _buttonSize,
                  height: _isPressing ? _buttonSize - 6 : _buttonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isSending ? Colors.orange : const Color(0xFFCC0000),
                    boxShadow: [
                      BoxShadow(
                        color:      const Color(0xFFCC0000)
                            .withValues(alpha: _isPressing ? 0.75 : 0.50),
                        blurRadius:   _isPressing ? 32 : 18,
                        spreadRadius: _isPressing ? 6  : 1,
                      ),
                    ],
                  ),
                  child: _isSending
                      ? const Center(
                    child: SizedBox(
                      width:  26,
                      height: 26,
                      child:  CircularProgressIndicator(
                        color:       Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                      : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sos_rounded,
                          color: Colors.white, size: 28),
                      const SizedBox(height: 2),
                      Text(
                        _isPressing ? 'HOLD…' : 'HOLD',
                        style: const TextStyle(
                          color:         Colors.white,
                          fontSize:      9,
                          fontWeight:    FontWeight.w900,
                          letterSpacing: 1.8,
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
    );
  }
}

// ── Single radio-wave ring ─────────────────────────────────────
class _RadioWave extends StatelessWidget {
  final double progress;   // 0.0 → 1.0
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

    final size   = baseSize + maxExtra * progress;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFCC0000).withValues(alpha: opacity * 0.6),
          width: 2.5,
        ),
      ),
    );
  }
}

// ── Result dialog ─────────────────────────────────────────────
class _SosResultDialog extends StatelessWidget {
  final bool   success;
  final String message;
  const _SosResultDialog({required this.success, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF00C853) : AppColors.error;
    final icon  = success
        ? Icons.check_circle_rounded
        : Icons.error_rounded;
    final title = success ? 'SOS Sent!' : 'SOS Failed';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color:        const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(24),
          border:       Border.all(color: color.withValues(alpha: 0.4), width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 40),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Animated icon container
          Container(
            width:  72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: 40),
          ),

          const SizedBox(height: 18),

          Text(title,
              style:     AppTextStyles.h2.copyWith(color: Colors.white),
              textAlign: TextAlign.center),

          const SizedBox(height: 10),

          Text(message,
              style:     AppTextStyles.bodyMedium
                  .copyWith(color: Colors.white70),
              textAlign: TextAlign.center),

          const SizedBox(height: 28),

          SizedBox(
            width:  double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}