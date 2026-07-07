// lib/theme/app_colors.dart

import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // Private constructor - never instantiate

  // ── Brand Colors ──
  static const Color primary = Color(0xFF99CC33);       // Lime green
  static const Color secondary = Color(0xFF003333);     // Deep teal

  // ── Primary Shades ──
  static const Color primaryLight = Color(0xFFB8DB5C);  // Lighter lime
  static const Color primaryDark = Color(0xFF7AA827);   // Darker lime

  // ── Secondary Shades ──
  static const Color secondaryLight = Color(0xFF1A4D4D); // Lighter teal
  static const Color secondaryDark = Color(0xFF001A1A);  // Darker teal

  // ── Neutral Colors ──
  static const Color background = Color(0xFFF9FAF7);    // Off-white
  static const Color surface = Color(0xFFFFFFFF);       // Pure white
  static const Color surfaceVariant = Color(0xFFF0F3EB);// Light gray-green

  // ── Text Colors ──
  static const Color textPrimary = Color(0xFF003333);   // Same as secondary
  static const Color textSecondary = Color(0xFF4D6666); // Muted teal
  static const Color textLight = Color(0xFF8FA5A5);     // Very muted
  static const Color textOnPrimary = Color(0xFF003333); // On lime bg
  static const Color textOnSecondary = Color(0xFFFFFFFF); // On teal bg

  // ── Status Colors ──
  static const Color success = Color(0xFF99CC33);       // Reuse primary
  static const Color warning = Color(0xFFFFA726);       // Orange
  static const Color error = Color(0xFFE53935);         // Red
  static const Color info = Color(0xFF29B6F6);          // Blue

  // ── Borders & Dividers ──
  static const Color border = Color(0xFFE0E5DA);
  static const Color divider = Color(0xFFEDEFE8);
}