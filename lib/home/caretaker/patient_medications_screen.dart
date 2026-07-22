// lib/screens/home/caretaker/patient_medications_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mar/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/medication.dart';
import '../../../services/care_relationship_service.dart';
import '../../../services/local_cache_service.dart';
import '../../../services/medication_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/snackbar/app_snackbar.dart';
import 'caretaker_add_medication_screen.dart';
import 'caretaker_add_schedule_screen.dart';

class PatientMedicationsScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientMedicationsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientMedicationsScreen> createState() =>
      _PatientMedicationsScreenState();
}

class _PatientMedicationsScreenState extends State<PatientMedicationsScreen>
    with WidgetsBindingObserver {
  List<Medication> _medications = <Medication>[];

  bool _isLoading = true;
  bool _isLoadingFromCache = true;
  bool _checkingPermission = true;
  bool _canEdit = false;
  bool _hasLoadedFromServer = false;
  String? _error;

  RealtimeChannel? _realtimeChannel;
  bool _isSubscribed = false;

  // Optimistic updates tracking
  final Set<String> _optimisticMedicationIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribeFromRealtime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resubscribeToRealtime();
      _refreshData();
    } else if (state == AppLifecycleState.paused) {
      // Supabase handles this automatically, but we track state
      setState(() => _isSubscribed = false);
    }
  }

  Future<void> _initialize() async {
    // Load from cache first for instant UI
    await _loadFromCache();

    // Then check permissions and load from server
    await Future.wait([
      _checkPermission(),
      _loadMedications(),
    ]);

    // Subscribe to Supabase Realtime for real-time updates
    _subscribeToRealtime();
  }

  Future<void> _loadFromCache() async {
    try {
      debugPrint('📦 Loading medications from cache for patient: ${widget.patientId}');

      final allCachedMedications = await LocalCacheService.instance.getCachedMedications();

      // Filter medications for this patient
      final cachedMedications = allCachedMedications
          .where((med) => med.patientId == widget.patientId)
          .toList();

      if (cachedMedications.isNotEmpty && mounted) {
        debugPrint('✅ Loaded ${cachedMedications.length} medications from cache');

        setState(() {
          _medications = cachedMedications;
          _isLoadingFromCache = false;
        });
      } else {
        debugPrint('ℹ️ No cached medications found');
        if (mounted) {
          setState(() => _isLoadingFromCache = false);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading from cache: $e');
      if (mounted) {
        setState(() => _isLoadingFromCache = false);
      }
    }
  }

  Future<void> _checkPermission() async {
    try {
      final canEdit = await CareRelationshipService.instance
          .canEditMedications(widget.patientId);

      if (mounted) {
        setState(() {
          _canEdit = canEdit;
          _checkingPermission = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error checking edit permission: $e');
      if (mounted) {
        setState(() => _checkingPermission = false);
      }
    }
  }

  Future<void> _loadMedications() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('🔄 Loading medications from server for patient: ${widget.patientId}');

      final medications = await MedicationService.instance
          .getMedicationsForPatient(widget.patientId);

      if (!mounted) return;

      debugPrint('✅ Loaded ${medications.length} medications from server');

      // Cache the medications locally
      for (final medication in medications) {
        await LocalCacheService.instance.cacheMedication(medication);
      }

      setState(() {
        _medications = medications;
        _isLoading = false;
        _hasLoadedFromServer = true;
        _optimisticMedicationIds.clear(); // Clear optimistic updates
      });
    } catch (error, stack) {
      debugPrint('❌ Failed to load patient medications: $error');
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _error = error.toString().replaceAll('Exception: ', '');
        _isLoading = false;

        // If we have cache data, keep showing it despite error
        if (_medications.isEmpty) {
          _hasLoadedFromServer = false;
        }
      });

      // Show subtle error if we have cached data
      if (_medications.isNotEmpty && mounted) {
        AppSnackbar.warning(
          context,
          'Showing cached data. Connection issue.',
        );
      }
    }
  }

  void _subscribeToRealtime() {
    if (_realtimeChannel != null) {
      debugPrint('⚠️ Already subscribed to realtime');
      return;
    }

    try {
      debugPrint('🔌 Subscribing to Supabase Realtime for medications table');
      debugPrint('   Filtering by patient_id: ${widget.patientId}');

      _realtimeChannel = Supabase.instance.client
          .channel('medications:patient_id=eq.${widget.patientId}')
          .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'medications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'patient_id',
          value: widget.patientId,
        ),
        callback: _handleInsert,
      )
          .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'medications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'patient_id',
          value: widget.patientId,
        ),
        callback: _handleUpdate,
      )
          .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'medications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'patient_id',
          value: widget.patientId,
        ),
        callback: _handleDelete,
      )
          .subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Successfully subscribed to Supabase Realtime');
          if (mounted) {
            setState(() => _isSubscribed = true);
          }
        } else if (status == RealtimeSubscribeStatus.closed) {
          debugPrint('⚠️ Realtime subscription closed');
          if (mounted) {
            setState(() => _isSubscribed = false);
          }
        } else if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('❌ Realtime channel error: $error');
          if (mounted) {
            setState(() => _isSubscribed = false);
          }
        }
      });
    } catch (e, stack) {
      debugPrint('❌ Error subscribing to realtime: $e');
      debugPrint('$stack');
    }
  }

  void _handleInsert(PostgresChangePayload payload) {
    debugPrint('📨 Realtime INSERT event received');
    debugPrint('   New record: ${payload.newRecord}');

    try {
      final medication = Medication.fromJson(payload.newRecord);

      // Skip if this is an optimistic update we already have
      if (_optimisticMedicationIds.contains(medication.id)) {
        debugPrint('   ⏭️ Skipping optimistic update for: ${medication.id}');
        _optimisticMedicationIds.remove(medication.id);
        return;
      }

      // Check if medication already exists (shouldn't happen, but safety check)
      if (_medications.any((m) => m.id == medication.id)) {
        debugPrint('   ⚠️ Medication already exists, skipping: ${medication.id}');
        return;
      }

      if (mounted) {
        setState(() {
          _medications.add(medication);
          _medications.sort((a, b) => a.displayName.compareTo(b.displayName));
        });

        // Cache locally
        LocalCacheService.instance.cacheMedication(medication);

        AppSnackbar.success(
          context,
          '${medication.displayName} added',
        );

        debugPrint('✅ Medication added to list: ${medication.displayName}');
      }
    } catch (e, stack) {
      debugPrint('❌ Error handling INSERT event: $e');
      debugPrint('$stack');
    }
  }

  void _handleUpdate(PostgresChangePayload payload) {
    debugPrint('📨 Realtime UPDATE event received');
    debugPrint('   Old record: ${payload.oldRecord}');
    debugPrint('   New record: ${payload.newRecord}');

    try {
      final medication = Medication.fromJson(payload.newRecord);

      if (mounted) {
        setState(() {
          final index = _medications.indexWhere((m) => m.id == medication.id);
          if (index != -1) {
            _medications[index] = medication;
            debugPrint('✅ Medication updated: ${medication.displayName}');
          } else {
            debugPrint('⚠️ Medication not found for update: ${medication.id}');
          }
        });

        // Update cache
        LocalCacheService.instance.cacheMedication(medication);

        AppSnackbar.info(
          context,
          '${medication.displayName} updated',
        );
      }
    } catch (e, stack) {
      debugPrint('❌ Error handling UPDATE event: $e');
      debugPrint('$stack');
    }
  }

  void _handleDelete(PostgresChangePayload payload) {
    debugPrint('📨 Realtime DELETE event received');
    debugPrint('   Old record: ${payload.oldRecord}');

    try {
      final medicationId = payload.oldRecord['id'] as String;

      if (mounted) {
        final medication = _medications.firstWhere(
              (m) => m.id == medicationId,
          orElse: () => Medication(
            id: medicationId,
            patientId: widget.patientId,
            genericName: 'Unknown',
            dosageAmount: 0,
            dosageUnit: '',
            medicationType: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(), refillAlertAt:0, isActive: false,
          ),
        );

        setState(() {
          _medications.removeWhere((m) => m.id == medicationId);
        });

        // Remove from cache - clear all and re-cache remaining
        _recacheMedications();

        AppSnackbar.info(
          context,
          '${medication.displayName} removed',
        );

        debugPrint('✅ Medication deleted: ${medication.displayName}');
      }
    } catch (e, stack) {
      debugPrint('❌ Error handling DELETE event: $e');
      debugPrint('$stack');
    }
  }

  Future<void> _recacheMedications() async {
    try {
      // Clear existing cache
      await LocalCacheService.instance.clearMedicationCache();

      // Re-cache current medications
      for (final medication in _medications) {
        await LocalCacheService.instance.cacheMedication(medication);
      }

      debugPrint('✅ Medications re-cached successfully');
    } catch (e) {
      debugPrint('❌ Error re-caching medications: $e');
    }
  }

  void _resubscribeToRealtime() {
    debugPrint('🔄 Resubscribing to Supabase Realtime');
    _unsubscribeFromRealtime();
    _subscribeToRealtime();
  }

  Future<void> _unsubscribeFromRealtime() async {
    if (_realtimeChannel != null) {
      debugPrint('🔌 Unsubscribing from Supabase Realtime');

      await Supabase.instance.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;

      if (mounted) {
        setState(() => _isSubscribed = false);
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadMedications();
  }

  void _openAddMedication() {
    if (!_canEdit) {
      AppSnackbar.error(
        context,
        'You do not have permission to add medications for this patient.',
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaretakerAddMedicationScreen(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    ).then((result) {
      if (result == true && mounted) {
        // Realtime will handle the update, but refresh just in case
        _refreshData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.patientName} — Medications',
              style: AppTextStyles.titleMedium,
            ),
            if (!_isSubscribed && _hasLoadedFromServer)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 12,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
          ],
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          // Real-time indicator
          if (_isSubscribed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.success.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Live',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      floatingActionButton: _canEdit ? _buildAddMedicationFab() : null,
    );
  }

  Widget _buildAddMedicationFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.medication_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                'Add',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(28),
          color: AppColors.primary,
          child: InkWell(
            onTap: _openAddMedication,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    // Show loading only if we have no cache data
    if ((_checkingPermission || _isLoadingFromCache) && _medications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading medications...',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // Show error only if we have no cached data
    if (_error != null && _medications.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 52,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load medications',
                    style: AppTextStyles.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _refreshData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_medications.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medication_outlined,
                      size: 58,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No medications found',
                    style: AppTextStyles.h2,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.patientName} has no active medications. Add medications to set up schedules.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_canEdit) ...[
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _openAddMedication,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add First Medication'),
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
                        elevation: 2,
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

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshData,
      child: Stack(
        children: [
          ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: _medications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _MedicationCard(
                medication: _medications[index],
                patientId: widget.patientId,
                patientName: widget.patientName,
              );
            },
          ),

          // Subtle loading indicator when refreshing with existing data
          if (_isLoading && _medications.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Syncing...',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final Medication medication;
  final String patientId;
  final String patientName;

  const _MedicationCard({
    required this.medication,
    required this.patientId,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = medication.pillImageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CaretakerAddScheduleScreen(
              medicationId: medication.id,
              medicationName: medication.displayName,
              patientId: patientId,
              patientName: patientName,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: hasImage
                  ? Image.network(
                imageUrl,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const _MedicationIcon();
                },
              )
                  : const _MedicationIcon(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medication.displayName,
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    medication.displayDosage,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    medication.medicationType,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (medication.currentQuantity != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Quantity: ${medication.currentQuantity}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: medication.needsRefill
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicationIcon extends StatelessWidget {
  const _MedicationIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: const Icon(
        Icons.medication_rounded,
        size: 36,
        color: AppColors.secondary,
      ),
    );
  }
}