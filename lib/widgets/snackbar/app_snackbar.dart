// lib/widgets/snackbar/app_snackbar.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class AppSnackbar {
  AppSnackbar._();

  static void success(BuildContext context, String message) {
    _show(context, message, AppColors.primary, Icons.check_circle_rounded);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, AppColors.error, Icons.error_rounded);
  }

  static void warning(BuildContext context, String message) {
    _show(context, message, AppColors.warning, Icons.warning_rounded);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, AppColors.secondary, Icons.info_rounded);
  }

  static void _show(
      BuildContext context,
      String message,
      Color color,
      IconData icon,
      ) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}