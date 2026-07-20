// lib/home/caretaker/alerts_tab.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/sos_service.dart';
import '../../services/sos_speech_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key, required String patientId, required String patientName});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  List<Map<String, dynamic>> _alerts = [];

  final Set<String> _processingAlertIds = <String>{};

  RealtimeChannel? _channel;
  Timer? _realtimeDebounce;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _refreshQueued = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _loadAlerts();
    _subscribeToAlerts();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();

    final channel = _channel;
    if (channel != null) {
      unawaited(
        Supabase.instance.client.removeChannel(channel),
      );
    }

    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // REALTIME / WEBSOCKET
  // ══════════════════════════════════════════════════════════════

  void _subscribeToAlerts() {
    try {
      _channel = SosService.instance.subscribeToCaretakerAlerts(
            (payload) {
          if (!mounted) return;

          if (payload.eventType == PostgresChangeEvent.insert) {
            HapticFeedback.heavyImpact();
          }

          if (payload.eventType == PostgresChangeEvent.update) {
            final status =
            payload.newRecord['status']?.toString();

            // Stop the native TTS, looping SOS sound, and vibration
            // if this alert has been closed from another screen/device.
            if (status == 'resolved' || status == 'cancelled') {
              unawaited(
                SosSpeechService.instance.stop(),
              );
            }
          }

          _realtimeDebounce?.cancel();

          _realtimeDebounce = Timer(
            const Duration(milliseconds: 300),
                () {
              if (mounted) {
                _loadAlerts(silent: true);
              }
            },
          );
        },
      );
    } catch (error, stack) {
      debugPrint(
        '❌ SOS Realtime subscription failed: $error',
      );
      debugPrint('$stack');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LOAD ALERTS
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadAlerts({
    bool silent = false,
  }) async {
    if (_isRefreshing) {
      _refreshQueued = true;
      return;
    }

    _isRefreshing = true;

    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final alerts =
      await SosService.instance.getCaretakerAlerts();

      if (!mounted) return;

      setState(() {
        _alerts = alerts;
        _isLoading = false;
        _error = null;
      });
    } catch (error, stack) {
      debugPrint('❌ Failed to load SOS alerts: $error');
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _error = 'Could not load emergency alerts';
        _isLoading = false;
      });
    } finally {
      _isRefreshing = false;

      if (_refreshQueued && mounted) {
        _refreshQueued = false;

        unawaited(
          _loadAlerts(silent: true),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ACKNOWLEDGE ALERT
  // ══════════════════════════════════════════════════════════════

  Future<void> _acknowledge(String alertId) async {
    if (_processingAlertIds.contains(alertId)) return;

    setState(() => _processingAlertIds.add(alertId));

    try {
      await SosService.instance.acknowledgeAlert(alertId);

      // Acknowledgement means the caretaker has seen the SOS.
      // Stop the spoken message, caretaker_sos.mp3, and vibration.
      await SosSpeechService.instance.stop();

      if (!mounted) return;

      _showMessage(
        'SOS acknowledged. Contact the patient immediately.',
        color: AppColors.warning,
      );

      await _loadAlerts(silent: true);
    } catch (error, stack) {
      debugPrint('❌ Could not acknowledge alert: $error');
      debugPrint('$stack');

      if (!mounted) return;

      _showMessage(
        error.toString().replaceAll('Exception: ', ''),
        color: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() => _processingAlertIds.remove(alertId));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // RESOLVE ALERT
  // ══════════════════════════════════════════════════════════════

  Future<void> _resolve(String alertId) async {
    if (_processingAlertIds.contains(alertId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Resolve SOS?',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Only resolve this alert after confirming that the patient is safe.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            icon: const Icon(
              Icons.check_circle_rounded,
              size: 18,
            ),
            label: const Text('Mark Resolved'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.secondary,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _processingAlertIds.add(alertId));

    try {
      await SosService.instance.resolveAlert(alertId);
      await SosSpeechService.instance.stop();

      if (!mounted) return;

      _showMessage(
        'SOS marked as resolved',
        color: AppColors.primary,
      );

      await _loadAlerts(silent: true);
    } catch (error, stack) {
      debugPrint('❌ Could not resolve alert: $error');
      debugPrint('$stack');

      if (!mounted) return;

      _showMessage(
        error.toString().replaceAll('Exception: ', ''),
        color: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() => _processingAlertIds.remove(alertId));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CALL PATIENT
  // ══════════════════════════════════════════════════════════════

  Future<void> _callPatient(String? phoneNumber) async {
    final phone = phoneNumber?.trim();

    if (phone == null || phone.isEmpty) {
      _showMessage(
        'Patient has no phone number saved',
        color: AppColors.warning,
      );
      return;
    }

    final launched = await launchUrl(
      Uri(
        scheme: 'tel',
        path: phone,
      ),
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      _showMessage(
        'Could not open the phone dialer',
        color: AppColors.error,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // OPEN PATIENT LOCATION
  // ══════════════════════════════════════════════════════════════

  Future<void> _openPatientLocation({
    required double? latitude,
    required double? longitude,
  }) async {
    if (latitude == null || longitude == null) {
      _showMessage(
        'The patient location was unavailable.',
        color: AppColors.warning,
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
          '&query=$latitude,$longitude',
    );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      _showMessage(
        'Could not open Maps',
        color: AppColors.error,
      );
    }
  }

  void _showMessage(
      String message, {
        required Color color,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _AlertsSkeleton();
    }

    if (_error != null && _alerts.isEmpty) {
      return _ErrorState(
        message: _error!,
        onRetry: () => _loadAlerts(),
      );
    }

    if (_alerts.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _loadAlerts(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            _EmptyAlerts(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _loadAlerts(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          18,
          16,
          100,
        ),
        itemCount: _alerts.length,
        separatorBuilder: (_, __) {
          return const SizedBox(height: 12);
        },
        itemBuilder: (context, index) {
          final alert = _alerts[index];
          final alertId = alert['id']?.toString() ?? '';

          return _SosAlertCard(
            key: ValueKey(alertId),
            alert: alert,
            isProcessing:
            _processingAlertIds.contains(alertId),
            onCall: _callPatient,
            onOpenLocation: ({
              required double? latitude,
              required double? longitude,
            }) {
              return _openPatientLocation(
                latitude: latitude,
                longitude: longitude,
              );
            },
            onAcknowledge: _acknowledge,
            onResolve: _resolve,
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SOS ALERT CARD
// ══════════════════════════════════════════════════════════════

class _SosAlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final bool isProcessing;

  final Future<void> Function(String? phoneNumber) onCall;

  final Future<void> Function({
  required double? latitude,
  required double? longitude,
  }) onOpenLocation;

  final Future<void> Function(String alertId) onAcknowledge;
  final Future<void> Function(String alertId) onResolve;

  const _SosAlertCard({
    super.key,
    required this.alert,
    required this.isProcessing,
    required this.onCall,
    required this.onOpenLocation,
    required this.onAcknowledge,
    required this.onResolve,
  });

  String get _status {
    return alert['status']?.toString() ?? 'sent';
  }

  Color get _statusColor {
    switch (_status) {
      case 'acknowledged':
        return AppColors.warning;
      case 'resolved':
        return const Color(0xFF17834D);
      case 'cancelled':
        return AppColors.textSecondary;
      default:
        return AppColors.error;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case 'acknowledged':
        return 'ACKNOWLEDGED';
      case 'resolved':
        return 'RESOLVED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return 'EMERGENCY';
    }
  }

  double? _readDouble(String key) {
    final value = alert[key];

    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '');
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return 'Unknown time';

    final date =
    DateTime.tryParse(raw.toString())?.toLocal();

    if (date == null) return 'Unknown time';

    final hour = date.hour;
    final minute =
    date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
    hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '${date.day}/${date.month}/${date.year} · '
        '$displayHour:$minute $period';
  }

  String _accuracyText(double? accuracy) {
    if (accuracy == null) {
      return 'Location shared';
    }

    return 'Approx. ±${accuracy.toStringAsFixed(0)} meters';
  }

  @override
  Widget build(BuildContext context) {
    final patient = alert['patient'] is Map
        ? Map<String, dynamic>.from(
      alert['patient'] as Map,
    )
        : <String, dynamic>{};

    final alertId = alert['id']?.toString() ?? '';

    final savedPatientName =
    alert['patient_name']?.toString().trim();

    final profilePatientName =
    patient['full_name']?.toString().trim();

    final patientName =
    savedPatientName != null &&
        savedPatientName.isNotEmpty
        ? savedPatientName
        : profilePatientName != null &&
        profilePatientName.isNotEmpty
        ? profilePatientName
        : 'Patient';

    final patientPhone =
    patient['phone_number']?.toString();

    final message = alert['message']?.toString() ??
        'Patient requested urgent assistance';

    final latitude = _readDouble('latitude');
    final longitude = _readDouble('longitude');
    final accuracy =
    _readDouble('location_accuracy_m');

    final hasLocation =
        latitude != null && longitude != null;

    final canAcknowledge = _status == 'sent';

    final canResolve = _status == 'sent' ||
        _status == 'acknowledged';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
          _statusColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color:
            _statusColor.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (isProcessing)
            const LinearProgressIndicator(
              minHeight: 3,
              color: AppColors.primary,
            ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
              _statusColor.withValues(alpha: 0.10),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sos_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: AppTextStyles.titleMedium
                            .copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatDateTime(
                          alert['created_at'],
                        ),
                        style:
                        AppTextStyles.bodySmall.copyWith(
                          color:
                          AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(
                      alpha: 0.14,
                    ),
                    borderRadius:
                    BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel,
                    style:
                    AppTextStyles.labelSmall.copyWith(
                      color: _statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 14),

                _LocationPanel(
                  hasLocation: hasLocation,
                  latitude: latitude,
                  longitude: longitude,
                  accuracyText:
                  _accuracyText(accuracy),
                  capturedAt: _formatDateTime(
                    alert['location_captured_at'],
                  ),
                  onOpen: () {
                    return onOpenLocation(
                      latitude: latitude,
                      longitude: longitude,
                    );
                  },
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isProcessing
                            ? null
                            : () => onCall(patientPhone),
                        icon: const Icon(
                          Icons.call_rounded,
                          size: 18,
                        ),
                        label: const Text('Call'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                          AppColors.secondary,
                          side: BorderSide(
                            color: AppColors.secondary
                                .withValues(alpha: 0.40),
                          ),
                          padding:
                          const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isProcessing
                            ? null
                            : () => onOpenLocation(
                          latitude: latitude,
                          longitude: longitude,
                        ),
                        icon: Icon(
                          hasLocation
                              ? Icons.location_on_rounded
                              : Icons.location_off_rounded,
                          size: 18,
                        ),
                        label: Text(
                          hasLocation
                              ? 'Location'
                              : 'Unavailable',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: hasLocation
                              ? AppColors.secondary
                              : AppColors.textSecondary,
                          padding:
                          const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (canAcknowledge) ...[
                  const SizedBox(height: 9),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () =>
                          onAcknowledge(alertId),
                      icon: const Icon(
                        Icons.visibility_rounded,
                        size: 18,
                      ),
                      label: const Text(
                        'Acknowledge SOS',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        AppColors.warning,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],

                if (canResolve) ...[
                  const SizedBox(height: 9),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () => onResolve(alertId),
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                      ),
                      label: const Text(
                        'Mark Patient Safe',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        AppColors.primary,
                        foregroundColor:
                        AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LOCATION PANEL
// ══════════════════════════════════════════════════════════════

class _LocationPanel extends StatelessWidget {
  final bool hasLocation;
  final double? latitude;
  final double? longitude;
  final String accuracyText;
  final String capturedAt;
  final Future<void> Function() onOpen;

  const _LocationPanel({
    required this.hasLocation,
    required this.latitude,
    required this.longitude,
    required this.accuracyText,
    required this.capturedAt,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasLocation
        ? AppColors.secondary
        : AppColors.textSecondary;

    return InkWell(
      onTap: hasLocation ? onOpen : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasLocation
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
                color: color,
                size: 23,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    hasLocation
                        ? 'Patient location available'
                        : 'Patient location unavailable',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasLocation
                        ? '$accuracyText · $capturedAt'
                        : 'The SOS was delivered without coordinates.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${latitude!.toStringAsFixed(5)}, '
                          '${longitude!.toStringAsFixed(5)}',
                      style:
                      AppTextStyles.labelSmall.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasLocation)
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: AppColors.secondary,
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

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(
                  alpha: 0.12,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.health_and_safety_rounded,
                size: 52,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No emergency alerts',
              style: AppTextStyles.h2.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'SOS alerts from your patients will '
                  'appear here instantly.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SKELETON
// ══════════════════════════════════════════════════════════════

class _AlertsSkeleton extends StatelessWidget {
  const _AlertsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(
          height: 250,
          borderRadius: 18,
        ),
        SizedBox(height: 12),
        SkeletonBox(
          height: 250,
          borderRadius: 18,
        ),
        SizedBox(height: 12),
        SkeletonBox(
          height: 250,
          borderRadius: 18,
        ),
      ],
    );
  }
}