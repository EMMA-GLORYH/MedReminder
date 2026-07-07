// lib/screens/gui/medications/widgets/medications_list_view.dart

import 'package:flutter/material.dart';
import 'dart:async';
import '../../../models/medication.dart';
import '../../../services/medication_service.dart';
import '../../../services/schedule_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/loaders/skeleton_loader.dart';
import '../add_medication_screen.dart';
import '../add_schedule_screen.dart';
import '../medication_detail_screen.dart';
import 'medication_card.dart';
import 'medication_hero.dart';
import 'medication_search_delegate.dart';

class MedicationsListView extends StatefulWidget {
  const MedicationsListView({super.key});

  @override
  State<MedicationsListView> createState() => _MedicationsListViewState();
}

class _MedicationsListViewState extends State<MedicationsListView> {
  List<Medication> _medications = [];
  List<Medication> _filteredMedications = [];
  Map<String, bool> _hasScheduleMap = {};
  bool _isLoading = true;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final meds = await MedicationService.instance.getMyMedications();
      final schedules = await ScheduleService.instance.getMySchedules();

      final scheduleMap = <String, bool>{};
      for (final med in meds) {
        scheduleMap[med.id] = schedules.any((s) => s.medicationId == med.id);
      }

      if (mounted) {
        setState(() {
          _medications = meds;
          _hasScheduleMap = scheduleMap;
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load medications';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _applyFilters);
  }

  void _applyFilters() {
    final query = _searchController.text.trim();

    setState(() {
      if (query.isEmpty) {
        _filteredMedications = List.from(_medications);
      } else {
        final results = MedicationSearchAlgorithm.search<Medication>(
          items: _medications,
          query: query,
          getBrandName: (med) => med.displayName,
          getGenericName: (med) => med.genericName,
          getNotes: (med) => med.notes,
        );
        _filteredMedications = results.map((r) => r.item).toList();
      }
    });
  }

  Future<void> _openDetail(Medication med) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MedicationDetailScreen(medication: med)),
    );
    if (result == true) _load();
  }

  Future<void> _addSchedule(Medication med) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleScreen(
          medicationId: med.id,
          medicationName: med.displayName,
        ),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _addMedication() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicationScreen()),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Hero with search bar stacked inside
          MedicationHero(
            totalMedications: _medications.length,
            scheduledCount: _medications
                .where((m) => _hasScheduleMap[m.id] == true)
                .length,
            searchController: _searchController,
            onClearSearch: () => _searchController.clear(),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMedication,
        backgroundColor: AppColors.primary,
        elevation: 6,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const _LoadingSkeleton();
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
    if (_medications.isEmpty) return _EmptyView(onAdd: _addMedication);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: _filteredMedications.isEmpty && _searchController.text.isNotEmpty
          ? ListView(
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 56,
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'No medications found',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try a different search term',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      )
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _filteredMedications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final med = _filteredMedications[index];
          return MedicationCard(
            medication: med,
            hasSchedule: _hasScheduleMap[med.id] ?? false,
            onTap: () => _openDetail(med),
            onScheduleTap: () => _addSchedule(med),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LOADING, EMPTY, ERROR WIDGETS
// ══════════════════════════════════════════════════════════════
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SkeletonBox(height: 60, borderRadius: 12),
        const SizedBox(height: 8),
        SkeletonBox(height: 60, borderRadius: 12),
        const SizedBox(height: 8),
        SkeletonBox(height: 60, borderRadius: 12),
        const SizedBox(height: 8),
        SkeletonBox(height: 60, borderRadius: 12),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medication_rounded,
                size: 56,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 24),
            Text('No medications yet', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(
              'Add your first medication to start\ntracking your health journey',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Medication'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(message, style: AppTextStyles.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}