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

// ─── Cache key — holds only the first indexed page, for instant paint ──
const _kCacheKey = 'medications_list_first_page_cache_v1';

// How many medications are fetched per index page. Small enough to render
// a clean first screen; large enough that most patients never scroll.
const _kPageSize = 12;

class MedicationsListView extends StatefulWidget {
  const MedicationsListView({super.key});

  @override
  State<MedicationsListView> createState() => _MedicationsListViewState();
}

class _MedicationsListViewState extends State<MedicationsListView> {
  List<Medication> _medications         = [];
  List<Medication> _filteredMedications = [];
  Map<String, bool> _hasScheduleMap     = {};
  List<dynamic> _schedules              = []; // fetched once, reused per page
  // ^ typed dynamic deliberately: this file doesn't need to know the exact
  //   Schedule model shape, only that each item has a `.medicationId`.
  //   Swap `List<dynamic>` for your real `List<Schedule>` type if you'd
  //   rather have compile-time checking here.

  bool _isFirstLoad   = true;  // true until first page (cache or live) shown
  bool _isSyncing     = false; // refreshing the first page in the background
  bool _isLoadingMore = false; // fetching the next index page
  bool _hasMore       = true;  // whether another page might exist
  int  _offset        = 0;     // next index to fetch from
  int? _totalCount;            // accurate total from a lightweight count query
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  // ── Init ────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _bootLoad();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Boot: paint the first page from cache instantly, then reconcile ──
  Future<void> _bootLoad() async {
    await _loadFirstPageFromCache();
    await _syncFirstPageFromServer();
  }

  Future<void> _loadFirstPageFromCache() async {
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
        _offset      = list.length;
        _isFirstLoad = false;
      });
      _applyFilters();
    } catch (_) {
      // Corrupt cache — the server sync below will repopulate it.
    }
  }

  Future<void> _saveFirstPageToCache(List<Medication> meds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCacheKey,
        jsonEncode(meds.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ── Index page 0 from the server — resets pagination state ──────────
  Future<void> _syncFirstPageFromServer() async {
    if (mounted) setState(() => _isSyncing = true);

    try {
      final results = await Future.wait([
        ScheduleService.instance.getMySchedules(),
        MedicationService.instance.getMyMedicationsPage(offset: 0, limit: _kPageSize),
        MedicationService.instance.getMedicationsCount(),
      ]);

      final schedules = results[0] as List<dynamic>;
      final firstPage = results[1] as List<Medication>;
      final total     = results[2] as int;

      final scheduleMap = <String, bool>{
        for (final m in firstPage)
          m.id: schedules.any((s) => s.medicationId == m.id),
      };

      await _saveFirstPageToCache(firstPage);

      if (!mounted) return;
      setState(() {
        _medications    = firstPage;
        _schedules      = schedules;
        _hasScheduleMap = scheduleMap;
        _offset         = firstPage.length;
        _hasMore        = firstPage.length == _kPageSize;
        _totalCount     = total;
        _isFirstLoad    = false;
        _isSyncing      = false;
        _error          = null;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        if (_medications.isEmpty) _error = 'Could not load medications';
      });
    }
  }

  // ── Next index page — appends, never replaces ────────────────────────
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isSearching) return;
    setState(() => _isLoadingMore = true);

    try {
      final next = await MedicationService.instance.getMyMedicationsPage(
        offset: _offset,
        limit:  _kPageSize,
      );

      final scheduleMap = Map<String, bool>.from(_hasScheduleMap);
      for (final m in next) {
        scheduleMap[m.id] = _schedules.any((s) => s.medicationId == m.id);
      }

      if (!mounted) return;
      setState(() {
        _medications    = [..._medications, ...next];
        _hasScheduleMap = scheduleMap;
        _offset         += next.length;
        _hasMore        = next.length == _kPageSize;
        _isLoadingMore  = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      // Silent failure — the trailing "load more" row simply stays put
      // and the user can trigger it again by scrolling.
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    const threshold = 300.0;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - threshold) {
      _loadMore();
    }
  }

  /// Resets pagination back to page 0 and refetches — used after add/edit/
  /// delete and on pull-to-refresh, since those actions can change which
  /// items belong on page 0 (e.g. a newly added medication sorts first).
  Future<void> _refreshAll() async {
    _offset  = 0;
    _hasMore = true;
    await _syncFirstPageFromServer();
  }

  // ── Navigate then refresh ────────────────────────────────────────────
  Future<void> _go(Future<Object?> Function() navigate) async {
    final result = await navigate();
    if (result == true) {
      await _refreshAll();
    }
  }

  // ── Search — filters within currently loaded pages ───────────────────
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
          items:          _medications,
          query:          query,
          getBrandName:   (m) => m.displayName,
          getGenericName: (m) => m.genericName,
          getNotes:       (m) => m.notes,
        );
        _filteredMedications = results.map((r) => r.item).toList();
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          MedicationHero(
            totalMedications: _totalCount ?? _medications.length,
            scheduledCount: _medications
                .where((m) => _hasScheduleMap[m.id] == true)
                .length,
            searchController: _searchController,
            onClearSearch:    () => _searchController.clear(),
          ),

          // Thin progress bar — visible while the first page is syncing.
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
      return _ErrorView(message: _error!, onRetry: _refreshAll);
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

    if (_filteredMedications.isEmpty && _isSearching) {
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

    // A trailing "loading more" row is appended only when there may be
    // more indexed pages left and the user isn't currently searching
    // (search operates over what's already loaded).
    final showLoadMoreRow = _hasMore && !_isSearching;
    final itemCount = _filteredMedications.length + (showLoadMoreRow ? 1 : 0);

    return RefreshIndicator(
      color:     AppColors.primary,
      onRefresh: _refreshAll,
      child: ListView.separated(
        controller:       _scrollController,
        padding:          const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount:        itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          if (index >= _filteredMedications.length) {
            // Trailing row: spinner while a page is in flight, otherwise
            // an invisible sentinel that simply triggers _onScroll.
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
                    : const SizedBox(height: 22),
              ),
            );
          }

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
        SkeletonBox(height: 96, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(height: 96, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(height: 96, borderRadius: 12),
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