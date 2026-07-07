// lib/theme/app_text_styles.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // ── Base font family ──
  // Poppins is friendly, professional, and reads well for health apps
  static TextStyle _base({
    required double size,
    FontWeight weight = FontWeight.normal,
    Color color = AppColors.textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // ── Display (Hero text) ──
  static TextStyle get displayLarge => _base(
    size: 32,
    weight: FontWeight.bold,
    height: 1.2,
  );

  static TextStyle get displayMedium => _base(
    size: 28,
    weight: FontWeight.bold,
    height: 1.25,
  );

  // ── Headings ──
  static TextStyle get h1 => _base(size: 24, weight: FontWeight.w700);
  static TextStyle get h2 => _base(size: 20, weight: FontWeight.w600);
  static TextStyle get h3 => _base(size: 18, weight: FontWeight.w600);

  // ── Titles ──
  static TextStyle get titleLarge => _base(size: 18, weight: FontWeight.w600);
  static TextStyle get titleMedium => _base(size: 16, weight: FontWeight.w600);
  static TextStyle get titleSmall => _base(size: 14, weight: FontWeight.w600);

  // ── Body ──
  static TextStyle get bodyLarge => _base(size: 16, height: 1.5);
  static TextStyle get bodyMedium => _base(size: 14, height: 1.5);
  static TextStyle get bodySmall => _base(
    size: 12,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  // ── Labels ──
  static TextStyle get labelLarge => _base(size: 14, weight: FontWeight.w600);
  static TextStyle get labelMedium => _base(size: 12, weight: FontWeight.w600);
  static TextStyle get labelSmall => _base(
    size: 11,
    weight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  // ── Buttons ──
  static TextStyle get buttonLarge => _base(size: 16, weight: FontWeight.w600);
  static TextStyle get buttonMedium => _base(size: 14, weight: FontWeight.w600);

  // ── Caption ──
  static TextStyle get caption => _base(
    size: 11,
    color: AppColors.textLight,
  );
}