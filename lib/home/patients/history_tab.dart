// lib/screens/home/patient/history_tab.dart

import 'package:flutter/material.dart';
import 'package:mar/services/dose_log_service.dart';
import 'package:mar/theme/app_colors.dart';
import 'package:mar/theme/app_text_styles.dart';
import 'package:mar/widgets/loaders/skeleton_loader.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await DoseLogService.instance.getDoseHistory();
      if (mounted) {
        setState(() {
          _history = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load history';
          _isLoading = false;
        });
      }
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupHistoryByDate() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final log in _history) {
      final scheduledDate = DateTime.parse(log['scheduled_for'] as String).toLocal();
      final dateString = _formatGroupHeader(scheduledDate);
      if (grouped[dateString] == null) {
        grouped[dateString] = [];
      }
      grouped[dateString]!.add(log);
    }
    return grouped;
  }

  String _formatGroupHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) return 'Today';
    if (checkDate == yesterday) return 'Yesterday';

    const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return '${weekdays[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}';
  }

  // ── One Scaffold for every state — loading, error, empty, and loaded ──
  // all share the same AppBar and background, so nothing pops in/out or
  // renders on an unstyled background as the screen transitions between
  // states.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dose Log History'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const _HistorySkeleton();

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadHistory,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.error_outline_rounded,
                          size: 44, color: AppColors.error),
                    ),
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: AppTextStyles.titleMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loadHistory,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_history.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadHistory,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.history_rounded,
                          size: 44, color: AppColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    Text('No history yet', style: AppTextStyles.h2),
                    const SizedBox(height: 8),
                    Text(
                      'Your verified dose history will appear here.',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final grouped = _groupHistoryByDate();
    final dateKeys = grouped.keys.toList();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadHistory,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: dateKeys.length,
        itemBuilder: (context, index) {
          final dateKey = dateKeys[index];
          final logs = grouped[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateSectionHeader(label: dateKey, count: logs.length),
              const SizedBox(height: 8),
              ...logs.map((log) => _HistoryCard(log: log)),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DATE SECTION HEADER
// ══════════════════════════════════════════════════════════════
class _DateSectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _DateSectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: AppColors.border, height: 1)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HISTORICAL LOG CARD
// ══════════════════════════════════════════════════════════════
class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> log;

  const _HistoryCard({required this.log});

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'taken':
        return AppColors.primary;
      case 'late':
        return AppColors.warning;
      case 'skipped':
        return Colors.blueGrey;
      case 'missed':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'taken':
        return Icons.check_circle_rounded;
      case 'late':
        return Icons.schedule_rounded;
      case 'skipped':
        return Icons.remove_circle_outline_rounded;
      case 'missed':
        return Icons.cancel_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  String _formatLogTime(String scheduledString, String? loggedString, String status) {
    final scheduled = DateTime.parse(scheduledString).toLocal();
    final h = scheduled.hour;
    final m = scheduled.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final scheduledTimeStr = '$dh:$m $p';

    if (loggedString == null || status == 'missed') {
      return 'Scheduled for $scheduledTimeStr';
    }

    final logged = DateTime.parse(loggedString).toLocal();
    final lh = logged.hour;
    final lm = logged.minute.toString().padLeft(2, '0');
    final lp = lh >= 12 ? 'PM' : 'AM';
    final ldh = lh == 0 ? 12 : (lh > 12 ? lh - 12 : lh);

    return 'Taken at $ldh:$lm $lp · Sched $scheduledTimeStr';
  }

  @override
  Widget build(BuildContext context) {
    final status = log['status'] as String? ?? 'taken';
    final genericName = log['generic_name'] as String? ?? 'Medication';
    final brandName = log['brand_name'] as String?;
    final displayName = brandName != null && brandName.isNotEmpty ? brandName : genericName;
    final dosageAmount = log['dosage_amount'] as num? ?? 0;
    final dosageUnit = log['dosage_unit'] as String? ?? '';
    final pillColorStr = log['pill_color'] as String?;
    final pillImageUrl = log['pill_image_url'] as String?;

    final dosageDisplay = '${dosageAmount % 1 == 0 ? dosageAmount.toInt() : dosageAmount} $dosageUnit';
    final statusColor = _getStatusColor(status);

    final deviation = log['deviation_minutes'] as int?;
    String? deviationText;
    if (deviation != null && status == 'late') {
      deviationText = '${deviation.abs()}m late';
    } else if (deviation != null && deviation < -5 && status == 'taken') {
      deviationText = '${deviation.abs()}m early';
    }

    final hasNotes = log['notes'] != null && (log['notes'] as String).trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Medicine image or fallback color avatar ──
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: pillImageUrl != null && pillImageUrl.isNotEmpty
                    ? Image.network(
                  pillImageUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _FallbackAvatar(colorStr: pillColorStr),
                )
                    : _FallbackAvatar(colorStr: pillColorStr),
              ),
              const SizedBox(width: 14),

              // ── Name, dosage, timing ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: AppTextStyles.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dosageDisplay,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatLogTime(
                          log['scheduled_for'] as String, log['logged_at'] as String?, status),
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ── Status badge ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getStatusIcon(status), size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status[0].toUpperCase() + status.substring(1).toLowerCase(),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (deviationText != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      deviationText,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          // ── Notes — full text, wraps instead of being clipped ──
          if (hasNotes) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (log['notes'] as String).trim(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  final String? colorStr;

  const _FallbackAvatar({required this.colorStr});

  Color _getColor() {
    switch (colorStr?.toLowerCase()) {
      case 'white':
        return Colors.white;
      case 'blue':
        return const Color(0xFF4A90E2);
      case 'red':
        return const Color(0xFFE53935);
      case 'yellow':
        return const Color(0xFFFFC107);
      case 'green':
        return AppColors.primary;
      case 'orange':
        return const Color(0xFFFF9800);
      case 'pink':
        return const Color(0xFFEC407A);
      case 'purple':
        return const Color(0xFF9C27B0);
      case 'brown':
        return const Color(0xFF795548);
      default:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      width: 52,
      height: 52,
      color: color,
      alignment: Alignment.center,
      child: Icon(
        Icons.medication_rounded,
        size: 24,
        color: color == Colors.white ? AppColors.secondary : Colors.white,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SKELETON LOADER — no separate Scaffold; renders inside the shared one
// ══════════════════════════════════════════════════════════════
class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(height: 20, width: 90, borderRadius: 6),
        SizedBox(height: 12),
        SkeletonBox(height: 84, borderRadius: 16),
        SizedBox(height: 10),
        SkeletonBox(height: 84, borderRadius: 16),
        SizedBox(height: 24),
        SkeletonBox(height: 20, width: 70, borderRadius: 6),
        SizedBox(height: 12),
        SkeletonBox(height: 84, borderRadius: 16),
      ],
    );
  }
}