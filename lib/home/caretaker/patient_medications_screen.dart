// lib/screens/home/caretaker/patient_medications_screen.dart

import 'package:flutter/material.dart';
import 'package:mar/localization/app_localizations.dart';

import '../../models/medication.dart';
import '../../services/medication_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

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

class _PatientMedicationsScreenState
    extends State<PatientMedicationsScreen> {
  List<Medication> _medications =
  <Medication>[];

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  Future<void> _loadMedications() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final medications =
      await MedicationService.instance
          .getMedicationsForPatient(
        widget.patientId,
      );

      if (!mounted) return;

      setState(() {
        _medications = medications;
        _isLoading = false;
      });
    } catch (error, stack) {
      debugPrint(
        '❌ Failed to load patient medications: $error',
      );
      debugPrint('$stack');

      if (!mounted) return;

      setState(() {
        _error = error
            .toString()
            .replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '${widget.patientName} — Medications',
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadMedications,
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Padding(
              padding:
              const EdgeInsets.all(28),
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
                    style:
                    AppTextStyles.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: AppTextStyles.bodySmall
                        .copyWith(
                      color:
                      AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _loadMedications,
                    icon: const Icon(
                      Icons.refresh_rounded,
                    ),
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
        onRefresh: _loadMedications,
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Padding(
              padding:
              const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(
                    Icons.medication_outlined,
                    size: 58,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No medications found',
                    style: AppLocalizations.of(context) != null
                        ? AppTextStyles.h2
                        : AppTextStyles.h2,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.patientName} has no active medications.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(
                      color:
                      AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadMedications,
      child: ListView.separated(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32,
        ),
        itemCount: _medications.length,
        separatorBuilder: (_, __) =>
        const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _MedicationCard(
            medication: _medications[index],
          );
        },
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final Medication medication;

  const _MedicationCard({
    required this.medication,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl =
    medication.pillImageUrl?.trim();

    final hasImage =
        imageUrl != null && imageUrl.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.04,
            ),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
            BorderRadius.circular(14),
            child: hasImage
                ? Image.network(
              imageUrl,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) {
                return const _MedicationIcon();
              },
            )
                : const _MedicationIcon(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  medication.displayName,
                  style:
                  AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow:
                  TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  medication.displayDosage,
                  style:
                  AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  medication.medicationType,
                  style:
                  AppTextStyles.bodySmall.copyWith(
                    color:
                    AppColors.textSecondary,
                  ),
                ),
                if (medication.currentQuantity !=
                    null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Quantity: '
                        '${medication.currentQuantity}',
                    style:
                    AppTextStyles.bodySmall.copyWith(
                      color:
                      medication.needsRefill
                          ? AppColors.warning
                          : AppColors
                          .textSecondary,
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