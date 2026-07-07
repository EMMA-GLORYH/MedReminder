// lib/widgets/dialogs/confirm_dialog.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../buttons/app_button.dart';

enum ConfirmDialogType { info, warning, danger, success }

class ConfirmDialog {
  ConfirmDialog._();

  /// Show a confirm dialog
  /// Returns true if confirmed, false or null if cancelled
  static Future<bool?> show(
      BuildContext context, {
        required String title,
        required String message,
        String confirmText = 'Confirm',
        String cancelText = 'Cancel',
        ConfirmDialogType type = ConfirmDialogType.info,
        IconData? customIcon,
      }) {
    IconData icon;
    Color iconColor;

    switch (type) {
      case ConfirmDialogType.warning:
        icon = customIcon ?? Icons.warning_amber_rounded;
        iconColor = AppColors.warning;
        break;
      case ConfirmDialogType.danger:
        icon = customIcon ?? Icons.error_outline_rounded;
        iconColor = AppColors.error;
        break;
      case ConfirmDialogType.success:
        icon = customIcon ?? Icons.check_circle_outline_rounded;
        iconColor = AppColors.primary;
        break;
      case ConfirmDialogType.info:
        icon = customIcon ?? Icons.info_outline_rounded;
        iconColor = AppColors.secondary;
        break;
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: iconColor),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: cancelText,
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.medium,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: confirmText,
                      variant: type == ConfirmDialogType.danger
                          ? AppButtonVariant.danger
                          : AppButtonVariant.primary,
                      size: AppButtonSize.medium,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}