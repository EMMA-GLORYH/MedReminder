// lib/widgets/buttons/app_button.dart

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

enum AppButtonSize { small, medium, large }
enum AppButtonVariant { primary, secondary, outline, text, danger }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;
  final AppButtonSize size;
  final AppButtonVariant variant;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = true,
    this.size = AppButtonSize.large,
    this.variant = AppButtonVariant.primary,
  });

  double get _height {
    switch (size) {
      case AppButtonSize.small:
        return 40;
      case AppButtonSize.medium:
        return 48;
      case AppButtonSize.large:
        return 56;
    }
  }

  Color get _bgColor {
    switch (variant) {
      case AppButtonVariant.primary:
        return AppColors.primary;
      case AppButtonVariant.secondary:
        return AppColors.secondary;
      case AppButtonVariant.danger:
        return AppColors.error;
      case AppButtonVariant.outline:
      case AppButtonVariant.text:
        return Colors.transparent;
    }
  }

  Color get _fgColor {
    switch (variant) {
      case AppButtonVariant.primary:
        return AppColors.secondary;
      case AppButtonVariant.secondary:
      case AppButtonVariant.danger:
        return Colors.white;
      case AppButtonVariant.outline:
      case AppButtonVariant.text:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    final child = isLoading
        ? SizedBox(
      height: 22,
      width: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: _fgColor,
      ),
    )
        : Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: AppTextStyles.buttonLarge.copyWith(color: _fgColor),
        ),
      ],
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: _height,
      child: variant == AppButtonVariant.outline
          ? OutlinedButton(
        onPressed: isDisabled ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _fgColor,
          side: const BorderSide(color: AppColors.secondary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: child,
      )
          : variant == AppButtonVariant.text
          ? TextButton(
        onPressed: isDisabled ? null : onPressed,
        style: TextButton.styleFrom(foregroundColor: _fgColor),
        child: child,
      )
          : ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _bgColor,
          foregroundColor: _fgColor,
          elevation: 0,
          disabledBackgroundColor: _bgColor.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: child,
      ),
    );
  }
}