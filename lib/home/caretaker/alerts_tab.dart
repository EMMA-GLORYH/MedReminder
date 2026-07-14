// lib/home/caretaker/alerts_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/sos_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/loaders/skeleton_loader.dart';

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  List<Map<String, dynamic>> _alerts = [];

  RealtimeChannel? _channel;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;

  Set<String> _knownAlertIds = {};

  @override
  void initState() {
    super.initState();

    _loadAlerts();
    _subscribeToAlerts();
  }

  @override
  void dispose() {
    final channel = _channel;

    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }

    super.dispose();
  }

  void _subscribeToAlerts() {
    try {
      _channel = SosService.instance.subscribeToCaretakerAlerts(
            (payload) {
          if (!mounted) return;

          if (payload.eventType == PostgresChangeEvent.insert) {
            HapticFeedback.heavyImpact();
          }

          _loadAlerts(silent: true);
        },
      );
    } catch (error) {
      debugPrint('❌ SOS Realtime subscription failed: $error');
    }
  }

  Future<void> _loadAlerts({
    bool silent = false,
  }) async {
    if (_isRefreshing) return;

    _isRefreshing = true;

    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final alerts = await SosService.instance.getCaretakerAlerts();

      final incomingIds = alerts
          .map((alert) => alert['id']?.toString())
          .whereType<String>()
          .toSet();

      final newIds = incomingIds.difference(_knownAlertIds);

      if (!mounted) return;

      setState(() {
        _alerts = alerts;
        _knownAlertIds = incomingIds;
        _isLoading = false;
        _error = null;
      });

      if (silent && newIds.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            content: const Row(
              children: [
                Icon(
                  Icons.sos_rounded,
                  color: Colors.white,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'New emergency SOS received',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
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
    }
  }

  Future<void> _acknowledge(String alertId) async {
    try {
      await SosService.instance.acknowledgeAlert(alertId);
      await _loadAlerts(silent: true);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not acknowledge alert'),
        ),
      );
    }
  }

  Future<void> _resolve(String alertId) async {
    try {
      await SosService.instance.resolveAlert(alertId);
      await _loadAlerts(silent: true);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resolve alert'),
        ),
      );
    }
  }

  Future<void> _callPatient(String? phoneNumber) async {
    final phone = phoneNumber?.trim();

    if (phone == null || phone.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient has no phone number saved'),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the phone dialer'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _AlertsSkeleton();
    }

    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: _loadAlerts,
      );
    }

    if (_alerts.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadAlerts,
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
      onRefresh: _loadAlerts,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
        itemCount: _alerts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final alert = _alerts[index];

          return _SosAlertCard(
            alert: alert,
            onCall: _callPatient,
            onAcknowledge: _acknowledge,
            onResolve: _resolve,
          );
        },
      ),
    );
  }
}

class _SosAlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;

  final Future<void> Function(String? phoneNumber) onCall;
  final Future<void> Function(String alertId) onAcknowledge;
  final Future<void> Function(String alertId) onResolve;

  const _SosAlertCard({
    required this.alert,
    required this.onCall,
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
        return AppColors.primary;
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

  String _formatDateTime(dynamic raw) {
    if (raw == null) return 'Unknown time';

    final date = DateTime.tryParse(raw.toString())?.toLocal();

    if (date == null) return 'Unknown time';

    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
    hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '${date.day}/${date.month}/${date.year} · '
        '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final patient = alert['patient'] is Map
        ? Map<String, dynamic>.from(alert['patient'] as Map)
        : <String, dynamic>{};

    final alertId = alert['id']?.toString() ?? '';
    final patientName =
        patient['full_name']?.toString() ?? 'Patient';
    final patientPhone = patient['phone_number']?.toString();
    final message = alert['message']?.toString() ??
        'Patient requested urgent assistance';

    final canAcknowledge = _status == 'sent';
    final canResolve =
        _status == 'sent' || _status == 'acknowledged';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _statusColor.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
              ),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatDateTime(alert['created_at']),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
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
                    color: _statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel,
                    style: AppTextStyles.labelSmall.copyWith(
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: AppTextStyles.bodyMedium,
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onCall(patientPhone),
                        icon: const Icon(
                          Icons.call_rounded,
                          size: 18,
                        ),
                        label: const Text('Call'),
                      ),
                    ),

                    if (canAcknowledge) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => onAcknowledge(alertId),
                          icon: const Icon(
                            Icons.visibility_rounded,
                            size: 18,
                          ),
                          label: const Text('Acknowledge'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                if (canResolve) ...[
                  const SizedBox(height: 9),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => onResolve(alertId),
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
                color: AppColors.primary.withValues(alpha: 0.12),
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
              style: AppTextStyles.h2,
            ),
            const SizedBox(height: 7),
            Text(
              'SOS alerts from your patients will appear here instantly.',
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

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function({
  bool silent,
  }) onRetry;

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
              style: AppTextStyles.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => onRetry(silent: false),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertsSkeleton extends StatelessWidget {
  const _AlertsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(
          height: 170,
          borderRadius: 18,
        ),
        SizedBox(height: 12),
        SkeletonBox(
          height: 170,
          borderRadius: 18,
        ),
        SizedBox(height: 12),
        SkeletonBox(
          height: 170,
          borderRadius: 18,
        ),
      ],
    );
  }
}