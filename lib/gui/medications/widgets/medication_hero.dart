// lib/screens/gui/medications/widgets/medication_hero.dart

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import 'medication_search_delegate.dart';

class MedicationHero extends StatelessWidget {
  final int totalMedications;
  final int scheduledCount;
  final TextEditingController searchController;
  final VoidCallback onClearSearch;

  const MedicationHero({
    super.key,
    required this.totalMedications,
    required this.scheduledCount,
    required this.searchController,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.secondary, AppColors.secondaryLight],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _HeroDecorations()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stats row
                  Row(
                    children: [
                      _HeroChip(
                        icon: Icons.medication_rounded,
                        label: '$totalMedications total',
                      ),
                      const SizedBox(width: 10),
                      _HeroChip(
                        icon: Icons.schedule_rounded,
                        label: '$scheduledCount scheduled',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'My Medications',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search bar stacked inside hero
                  MedicationSearchBar(
                    controller: searchController,
                    onClear: onClearSearch,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDecorations extends StatelessWidget {
  const _HeroDecorations();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _HeroMedicalPainter()),
    );
  }
}

class _HeroMedicalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    // Pill bottle (right side)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 70, 30, 35, 50),
        const Radius.circular(6),
      ),
      paint,
    );
    // Bottle cap
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 73, 22, 41, 12),
        const Radius.circular(3),
      ),
      paint,
    );

    // Capsule (mid-right)
    canvas.save();
    canvas.translate(size.width * 0.65, size.height * 0.6);
    canvas.rotate(-0.4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 32, height: 14),
        const Radius.circular(7),
      ),
      paint,
    );
    canvas.restore();

    // Scattered dots
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.15);
    canvas.drawCircle(Offset(size.width * 0.3, 40), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.7), 3, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.35), 5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}