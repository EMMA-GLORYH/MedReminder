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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _HistorySkeleton();

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error!, style: AppTextStyles.titleMedium),
            TextButton(onPressed: _loadHistory, child: const Text('Retry')),
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
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.history_rounded, size: 48, color: AppColors.secondary),
                  ),
                  const SizedBox(height: 16),
                  Text('No history yet', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  Text(
                    'Your verified dose history will appear here.',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final grouped = _groupHistoryByDate();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dose Log History'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadHistory,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: grouped.keys.length,
          itemBuilder: (context, index) {
            final dateKey = grouped.keys.elementAt(index);
            final logs = grouped[dateKey]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  child: Text(
                    dateKey,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...logs.map((log) => _HistoryCard(log: log)),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
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

    return 'Taken at $ldh:$lm $lp (Sched: $scheduledTimeStr)';
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Medicine Image or Fallback Color Dot
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

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTextStyles.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _formatLogTime(log['scheduled_for'] as String, log['logged_at'] as String?, status),
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
                if (log['notes'] != null && (log['notes'] as String).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ${log['notes']}',
                    style: AppTextStyles.bodySmall.copyWith(fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Status & Deviation Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ),
              if (deviationText != null) ...[
                const SizedBox(height: 4),
                Text(
                  deviationText,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]
            ],
          ),
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
      child: Icon(
        Icons.medication_rounded,
        size: 24,
        color: color == Colors.white ? AppColors.secondary : Colors.white,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SKELETON LOADER
// ══════════════════════════════════════════════════════════════
class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBox(height: 24, width: 140),
          SizedBox(height: 12),
          SkeletonBox(height: 80, borderRadius: 16),
          SizedBox(height: 10),
          SkeletonBox(height: 80, borderRadius: 16),
          SizedBox(height: 24),
          SkeletonBox(height: 24, width: 100),
          SizedBox(height: 12),
          SkeletonBox(height: 80, borderRadius: 16),
        ],
      ),
    );
  }
}