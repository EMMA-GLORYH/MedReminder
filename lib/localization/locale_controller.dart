// lib/localization/locale_controller.dart
//
// Holds the app's current Locale in a ValueNotifier so any screen (e.g. a
// Settings page) can switch language at runtime, and persists the choice
// so it survives app restarts.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  static const _prefKey = 'app_locale_code';

  final ValueNotifier<Locale> notifier = ValueNotifier(const Locale('en'));

  /// Call once at startup, before runApp(), to restore the saved language.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefKey);
      if (code != null) notifier.value = Locale(code);
    } catch (_) {
      // Fall back to English if prefs aren't available for any reason.
    }
  }

  Future<void> setLocale(Locale locale) async {
    notifier.value = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, locale.languageCode);
    } catch (_) {}
  }
}