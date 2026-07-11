// lib/screens/gui/medications/widgets/medications_list_view.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// ─── Cache key ────────────────────────────────────────────────
const _kCacheKey = 'medications_list_cache_v1';

class MedicationsListView extends StatefulWidget {
  const MedicationsListView({super.key});

  @override
  State<MedicationsListView> createState() => _MedicationsListViewState();
}

class _MedicationsListViewState extends State<MedicationsListView> {
  List<Medication> _medications         = [];
  List<Medication> _filteredMedications = [];
  Map<String, bool> _hasScheduleMap     = {};

  bool _isFirstLoad = true;  // true only before any data (cached or live) shown
  bool _isSyncing   = false; // background sync indicator
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // ── Init ────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _bootLoad();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Boot: show cache instantly, sync in background ──────────
  Future<void> _bootLoad() async {
    await _loadFromCache();
    _syncFromServer();
  }

  // ── Read from SharedPreferences ─────────────────────────────
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kCacheKey);
      if (raw == null) return;

      final list = (jsonDecode(raw) as List)
          .map((j) => Medication.fromJson(j as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _medications = list;
        _isFirstLoad = false;
      });
      _applyFilters();
    } catch (_) {
      // Corrupt cache — server will repopulate it
    }
  }

  // ── Write to SharedPreferences ───────────────────────────────
  Future<void> _saveToCache(List<Medication> meds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCacheKey,
        jsonEncode(meds.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ── Fetch from server ────────────────────────────────────────
  Future<void> _syncFromServer() async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      final meds      = await MedicationService.instance.getMyMedications();
      final schedules = await ScheduleService.instance.getMySchedules();

      final scheduleMap = <String, bool>{};
      for (final med in meds) {
        scheduleMap[med.id] = schedules.any((s) => s.medicationId == med.id);
      }

      await _saveToCache(meds);

      if (!mounted) return;
      setState(() {
        _medications    = meds;
        _hasScheduleMap = scheduleMap;
        _isFirstLoad    = false;
        _isSyncing      = false;
        _error          = null;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        // Only show error if there's nothing to display at all
        if (_medications.isEmpty) _error = 'Could not load medications';
      });
    }
  }

  // ── Navigate then refresh optimistically ────────────────────
  Future<void> _go(Future<Object?> Function() navigate) async {
    final result = await navigate();
    if (result == true) {
      await _loadFromCache(); // show any locally-written cache immediately
      _syncFromServer();      // reconcile with server in background
    }
  }

  // ── Search ───────────────────────────────────────────────────
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
          items:         _medications,
          query:         query,
          getBrandName:  (m) => m.displayName,
          getGenericName: (m) => m.genericName,
          getNotes:      (m) => m.notes,
        );
        _filteredMedications = results.map((r) => r.item).toList();
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          MedicationHero(
            totalMedications: _medications.length,
            scheduledCount: _medications
                .where((m) => _hasScheduleMap[m.id] == true)
                .length,
            searchController: _searchController,
            onClearSearch:    () => _searchController.clear(),
          ),

          // Thin sync progress bar — only visible while background syncing
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height:   _isSyncing ? 3 : 0,
            child: LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primary.withValues(alpha: 0.6)),
            ),
          ),

          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _go(
              () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddMedicationScreen()),
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 6,
        shape:     const CircleBorder(),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildBody() {
    if (_isFirstLoad) return const _LoadingSkeleton();

    if (_error != null && _medications.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _syncFromServer);
    }

    if (_medications.isEmpty) {
      return _EmptyView(
        onAdd: () => _go(
              () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddMedicationScreen()),
          ),
        ),
      );
    }

    if (_filteredMedications.isEmpty && _searchController.text.isNotEmpty) {
      return ListView(children: [
        const SizedBox(height: 60),
        Center(
          child: Text(
            'No medications found',
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ),
      ]);
    }

    return RefreshIndicator(
      color:     AppColors.primary,
      onRefresh: _syncFromServer,
      child: ListView.separated(
        padding:          const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount:        _filteredMedications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final med = _filteredMedications[index];
          return MedicationCard(
            medication:  med,
            hasSchedule: _hasScheduleMap[med.id] ?? false,
            onTap: () => _go(
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MedicationDetailScreen(medication: med)),
              ),
            ),
            onScheduleTap: () => _go(
                  () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddScheduleScreen(
                    medicationId:   med.id,
                    medicationName: med.displayName,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ══════════════════════════════════════════════════════════════

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(height: 60, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(height: 60, borderRadius: 12),
        SizedBox(height: 8),
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
              child: const Icon(Icons.medication_rounded,
                  size: 56, color: AppColors.secondary),
            ),
            const SizedBox(height: 24),
            Text('No medications yet', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first medication',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String       message;
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
            const Icon(Icons.error_outline_rounded,
                size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(message,
                style:     AppTextStyles.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon:  const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}