import 'dart:async';

import 'package:flutter/material.dart';
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
  final Set<String> _expandedMedicationIds = <String>{};

  String _resolvedPatientId = '';

  bool _isLoading = true;
  bool _isLoadingFromCache = true;
  bool _checkingPermission = true;
  bool _canEdit = false;
  bool _hasLoadedFromServer = false;
  String? _error;

  RealtimeChannel? _realtimeChannel;
  bool _isSubscribed = false;

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
      if (mounted) {
        setState(() => _isSubscribed = false);
      }
    }
  }

  Future<String> _resolveTruePatientId(String id) async {
    final safeId = id.trim();
    if (safeId.isEmpty) return safeId;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('id', safeId)
          .maybeSingle();

      if (profile != null && profile['id'] != null) {
        return safeId;
      }
    } catch (_) {}

    try {
      final relationship = await Supabase.instance.client
          .from('care_relationships')
          .select('patient_id')
          .eq('id', safeId)
          .maybeSingle();

      if (relationship != null && relationship['patient_id'] != null) {
        return relationship['patient_id'].toString();
      }
    } catch (_) {}

    return safeId;
  }

  Future<void> _initialize() async {
    _resolvedPatientId = await _resolveTruePatientId(widget.patientId);
    debugPrint('🚀 Using resolved patient ID: $_resolvedPatientId');

    await _loadFromCache();

    await Future.wait([
      _checkPermission(),
      _loadMedications(),
    ]);

    _subscribeToRealtime();
  }

  Future<void> _loadFromCache() async {
    try {
      final allCachedMedications =
      await LocalCacheService.instance.getCachedMedications();

      final cachedMedications = allCachedMedications
          .where((med) => med.patientId == _resolvedPatientId)
          .toList();

      if (!mounted) return;

      setState(() {
        if (cachedMedications.isNotEmpty) {
          _medications = cachedMedications;
        }
        _isLoadingFromCache = false;
      });
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
          .canEditMedications(_resolvedPatientId);

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
      debugPrint(
        '🔄 Loading medications from server for patient: $_resolvedPatientId',
      );

      final medications = await MedicationService.instance
          .getMedicationsForPatient(_resolvedPatientId);

      if (!mounted) return;

      for (final medication in medications) {
        await LocalCacheService.instance.cacheMedication(medication);
      }

      setState(() {
        _medications = medications;
        _isLoading = false;
        _hasLoadedFromServer = true;
        _optimisticMedicationIds.clear();
      });
    } catch (error, stack) {
      debugPrint('❌ Failed to load patient medications: $error');
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _error = error.toString().replaceAll('Exception: ', '');
        _isLoading = false;
        if (_medications.isEmpty) {
          _hasLoadedFromServer = false;
        }
      });

      if (_medications.isNotEmpty && mounted) {
        AppSnackbar.warning(context, 'Showing cached data. Connection issue.');
      }
    }
  }

  void _toggleExpanded(String medicationId) {
    setState(() {
      if (_expandedMedicationIds.contains(medicationId)) {
        _expandedMedicationIds.remove(medicationId);
      } else {
        _expandedMedicationIds.add(medicationId);
      }
    });
  }

  Future<void> _promptScheduleMedication(Medication medication) async {
    if (!_canEdit) {
      _showMedicationDetails(medication);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Schedule or reschedule?'),
        content: Text(
          'Do you want to schedule or reschedule ${medication.displayName} for ${widget.patientName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CaretakerAddScheduleScreen(
          medicationId: medication.id,
          medicationName: medication.displayName,
          patientId: _resolvedPatientId,
          patientName: widget.patientName,
        ),
      ),
    );

    if (result == true && mounted) {
      _refreshData();
    }
  }

  Future<void> _openEditMedication(Medication medication) async {
    if (!_canEdit) {
      AppSnackbar.error(
        context,
        'You do not have permission to edit medications for this patient.',
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CaretakerAddMedicationScreen(
          patientId: _resolvedPatientId,
          patientName: widget.patientName,
          initialMedication: medication,
        ),
      ),
    );

    if (result == true && mounted) {
      _refreshData();
    }
  }

  Future<void> _deleteMedication(Medication medication) async {
    if (!_canEdit) {
      AppSnackbar.error(
        context,
        'You do not have permission to delete medications for this patient.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete medication?'),
        content: Text(
          'This will remove ${medication.displayName} and deactivate any linked schedules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await MedicationService.instance
          .deleteMedicationWithSchedules(medication.id);

      if (!mounted) return;

      setState(() {
        _medications.removeWhere((m) => m.id == medication.id);
        _expandedMedicationIds.remove(medication.id);
      });

      await _recacheMedications();

      AppSnackbar.success(
        context,
        '${medication.displayName} deleted',
      );
    } catch (e, stack) {
      debugPrint('❌ Delete medication error: $e');
      debugPrint('$stack');

      if (mounted) {
        AppSnackbar.error(
          context,
          'Failed to delete medication. Please try again.',
        );
      }
    }
  }

  void _showMedicationDetails(Medication medication) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final imageUrl = medication.pillImageUrl?.trim();
        final hasImage = imageUrl != null && imageUrl.isNotEmpty;

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Medication Details',
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: hasImage
                            ? Image.network(
                          imageUrl,
                          width: 140,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const _MedicationPreviewIcon(size: 140),
                        )
                            : const _MedicationPreviewIcon(size: 140),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DetailRow(
                      label: 'Name',
                      value: medication.displayName,
                    ),
                    _DetailRow(
                      label: 'Generic name',
                      value: medication.genericName,
                    ),
                    _DetailRow(
                      label: 'Dosage',
                      value: medication.displayDosage,
                    ),
                    _DetailRow(
                      label: 'Type',
                      value: medication.medicationType,
                    ),
                    if (medication.currentQuantity != null)
                      _DetailRow(
                        label: 'Quantity',
                        value: '${medication.currentQuantity}',
                      ),
                    if ((medication.pillColor ?? '').trim().isNotEmpty)
                      _DetailRow(
                        label: 'Color',
                        value: medication.pillColor!,
                      ),
                    if ((medication.pillShape ?? '').trim().isNotEmpty)
                      _DetailRow(
                        label: 'Shape',
                        value: medication.pillShape!,
                      ),
                    if ((medication.notes ?? '').trim().isNotEmpty)
                      _DetailRow(
                        label: 'Notes',
                        value: medication.notes!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _subscribeToRealtime() {
    if (_realtimeChannel != null) return;

    try {
      _realtimeChannel = Supabase.instance.client
          .channel('medications:$_resolvedPatientId')
          .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'medications',
        callback: (payload) {
          if (payload.newRecord['patient_id']?.toString() ==
              _resolvedPatientId) {
            _handleInsert(payload);
          }
        },
      ).onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'medications',
        callback: (payload) {
          if (payload.newRecord['patient_id']?.toString() ==
              _resolvedPatientId) {
            _handleUpdate(payload);
          }
        },
      ).onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'medications',
        callback: (payload) => _handleDelete(payload),
      ).subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Realtime subscribed');
          if (mounted) setState(() => _isSubscribed = true);
        } else if (status == RealtimeSubscribeStatus.closed) {
          if (mounted) setState(() => _isSubscribed = false);
        } else if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('❌ Realtime error: $error');
          if (mounted) setState(() => _isSubscribed = false);
        }
      });
    } catch (e, stack) {
      debugPrint('❌ Realtime subscribe exception: $e');
      debugPrint('$stack');
    }
  }

  void _handleInsert(PostgresChangePayload payload) {
    try {
      final medication = Medication.fromJson(payload.newRecord);

      if (_optimisticMedicationIds.contains(medication.id)) {
        _optimisticMedicationIds.remove(medication.id);
        return;
      }

      if (_medications.any((m) => m.id == medication.id)) return;

      if (mounted) {
        setState(() {
          _medications.add(medication);
          _medications.sort((a, b) => a.displayName.compareTo(b.displayName));
        });

        LocalCacheService.instance.cacheMedication(medication);
      }
    } catch (e, stack) {
      debugPrint('❌ Insert handler error: $e');
      debugPrint('$stack');
    }
  }

  void _handleUpdate(PostgresChangePayload payload) {
    try {
      final medication = Medication.fromJson(payload.newRecord);

      if (mounted) {
        setState(() {
          final index = _medications.indexWhere((m) => m.id == medication.id);

          if (medication.isActive == false) {
            if (index != -1) {
              _medications.removeAt(index);
              _expandedMedicationIds.remove(medication.id);
            }
            return;
          }

          if (index != -1) {
            _medications[index] = medication;
          } else {
            _medications.add(medication);
          }
        });

        _medications.sort((a, b) => a.displayName.compareTo(b.displayName));
        LocalCacheService.instance.cacheMedication(medication);
      }
    } catch (e, stack) {
      debugPrint('❌ Update handler error: $e');
      debugPrint('$stack');
    }
  }

  void _handleDelete(PostgresChangePayload payload) {
    try {
      final medicationId = payload.oldRecord['id'] as String?;
      if (medicationId == null) return;

      final existingIndex = _medications.indexWhere((m) => m.id == medicationId);
      if (existingIndex != -1 && mounted) {
        setState(() {
          _medications.removeAt(existingIndex);
          _expandedMedicationIds.remove(medicationId);
        });
        _recacheMedications();
      }
    } catch (e, stack) {
      debugPrint('❌ Delete handler error: $e');
      debugPrint('$stack');
    }
  }

  Future<void> _recacheMedications() async {
    try {
      await LocalCacheService.instance.clearMedicationCache();
      for (final medication in _medications) {
        await LocalCacheService.instance.cacheMedication(medication);
      }
    } catch (e) {
      debugPrint('❌ Re-cache error: $e');
    }
  }

  void _resubscribeToRealtime() {
    _unsubscribeFromRealtime();
    _subscribeToRealtime();
  }

  Future<void> _unsubscribeFromRealtime() async {
    if (_realtimeChannel != null) {
      await Supabase.instance.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
      if (mounted) setState(() => _isSubscribed = false);
    }
  }

  Future<void> _refreshData() async => _loadMedications();

  void _openAddMedication() {
    if (!_canEdit) {
      AppSnackbar.error(
        context,
        'You do not have permission to add medications for this patient.',
      );
      return;
    }

    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CaretakerAddMedicationScreen(
          patientId: _resolvedPatientId,
          patientName: widget.patientName,
        ),
      ),
    ).then((_) {
      _refreshData();
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
      body: SafeArea(child: _buildBody()),
      floatingActionButton: _canEdit ? _buildAddMedicationFab() : null,
    );
  }

  Widget _buildAddMedicationFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.medication_rounded, size: 14, color: Colors.white),
              SizedBox(width: 4),
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
    if ((_checkingPermission || _isLoadingFromCache) && _medications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
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
              final medication = _medications[index];
              return _MedicationCard(
                medication: medication,
                patientName: widget.patientName,
                isExpanded: _expandedMedicationIds.contains(medication.id),
                canEdit: _canEdit,
                onTapSchedule: () => _promptScheduleMedication(medication),
                onToggleExpanded: () => _toggleExpanded(medication.id),
                onFullView: () => _showMedicationDetails(medication),
                onEdit: () => _openEditMedication(medication),
                onDelete: () => _deleteMedication(medication),
              );
            },
          ),
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
  final String patientName;
  final bool isExpanded;
  final bool canEdit;
  final VoidCallback onTapSchedule;
  final VoidCallback onToggleExpanded;
  final VoidCallback onFullView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MedicationCard({
    required this.medication,
    required this.patientName,
    required this.isExpanded,
    required this.canEdit,
    required this.onTapSchedule,
    required this.onToggleExpanded,
    required this.onFullView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = medication.pillImageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTapSchedule,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                      errorBuilder: (_, __, ___) =>
                      const _MedicationPreviewIcon(size: 72),
                    )
                        : const _MedicationPreviewIcon(size: 72),
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
                  Column(
                    children: [
                      IconButton(
                        onPressed: onToggleExpanded,
                        icon: Icon(
                          isExpanded
                              ? Icons.expand_less_rounded
                              : Icons.more_horiz_rounded,
                          color: AppColors.textSecondary,
                        ),
                        tooltip: 'More actions',
                      ),
                      const Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  Divider(color: AppColors.secondaryDark, height: 1),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MedicationActionChip(
                        label: 'Full View',
                        icon: Icons.visibility_outlined,
                        onTap: onFullView,
                      ),
                      _MedicationActionChip(
                        label: 'Edit',
                        icon: Icons.edit_outlined,
                        onTap: canEdit ? onEdit : null,
                      ),
                      _MedicationActionChip(
                        label: 'Delete',
                        icon: Icons.delete_outline_rounded,
                        foregroundColor: AppColors.error,
                        onTap: canEdit ? onDelete : null,
                      ),
                    ],
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

class _MedicationActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? foregroundColor;
  final VoidCallback? onTap;

  const _MedicationActionChip({
    required this.label,
    required this.icon,
    this.foregroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = foregroundColor ?? AppColors.primary;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _MedicationPreviewIcon extends StatelessWidget {
  final double size;

  const _MedicationPreviewIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        Icons.medication_rounded,
        size: size * 0.45,
        color: AppColors.secondary,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}