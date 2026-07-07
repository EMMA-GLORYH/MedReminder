// lib/screens/gui/medications/widgets/medication_search_delegate.dart

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

// ══════════════════════════════════════════════════════════════
// MEDICATION SEARCH BAR (used in medications_list_view.dart)
// ══════════════════════════════════════════════════════════════
class MedicationSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onClear;

  const MedicationSearchBar({
    super.key,
    required this.controller,
    required this.onClear,
  });

  @override
  State<MedicationSearchBar> createState() => _MedicationSearchBarState();
}

class _MedicationSearchBarState extends State<MedicationSearchBar> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;

    return Focus(
      onFocusChange: (focused) => setState(() => _hasFocus = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hasFocus
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.border,
            width: _hasFocus ? 1.5 : 1.0,
          ),
          boxShadow: _hasFocus
              ? [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
              : [],
        ),
        child: TextField(
          controller: widget.controller,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Search by name, generic, or notes...',
            hintStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary.withValues(alpha: 0.6),
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: _hasFocus ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            suffixIcon: hasText
                ? IconButton(
              onPressed: () {
                widget.controller.clear();
                widget.onClear();
              },
              icon: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            )
                : null,
            filled: false,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 16,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SEARCH ALGORITHM — Fuzzy matching + relevance scoring
// ══════════════════════════════════════════════════════════════

/// A search result with a relevance score.
/// Higher score = better match.
class SearchResult<T> {
  final T item;
  final double score;
  final String matchedField;
  final String matchedText;

  const SearchResult({
    required this.item,
    required this.score,
    required this.matchedField,
    required this.matchedText,
  });
}

/// Professional search algorithm that scores results by relevance.
///
/// Scoring rules:
///   - Exact match on brand name:      100 points
///   - Starts with query (brand):       80 points
///   - Contains query (brand):          60 points
///   - Exact match on generic name:     70 points
///   - Starts with query (generic):     55 points
///   - Contains query (generic):        40 points
///   - Contains query (notes):          20 points
///   - Fuzzy match (typo tolerance):    10 points
///
/// Results are sorted by score (highest first).
class MedicationSearchAlgorithm {
  const MedicationSearchAlgorithm._();

  /// Search medications with relevance scoring.
  /// Returns results sorted by relevance (best match first).
  static List<SearchResult<T>> search<T>({
    required List<T> items,
    required String query,
    required String Function(T item) getBrandName,
    required String? Function(T item) getGenericName,
    String? Function(T item)? getNotes,
  }) {
    if (query.trim().isEmpty) return [];

    final normalizedQuery = query.toLowerCase().trim();
    final results = <SearchResult<T>>[];

    for (final item in items) {
      final brand = getBrandName(item).toLowerCase();
      final generic = getGenericName(item)?.toLowerCase() ?? '';
      final notes = getNotes?.call(item)?.toLowerCase() ?? '';

      double bestScore = 0;
      String matchedField = '';
      String matchedText = '';

      // ── Brand name scoring ──
      final brandScore = _scoreField(normalizedQuery, brand);
      if (brandScore > bestScore) {
        bestScore = brandScore;
        matchedField = 'brand';
        matchedText = getBrandName(item);
      }

      // ── Generic name scoring ──
      if (generic.isNotEmpty) {
        final genericScore = _scoreField(normalizedQuery, generic) * 0.7;
        if (genericScore > bestScore) {
          bestScore = genericScore;
          matchedField = 'generic';
          matchedText = getGenericName(item) ?? '';
        }
      }

      // ── Notes scoring ──
      if (notes.isNotEmpty) {
        final notesScore = _scoreField(normalizedQuery, notes) * 0.3;
        if (notesScore > bestScore) {
          bestScore = notesScore;
          matchedField = 'notes';
          matchedText = getNotes?.call(item) ?? '';
        }
      }

      // ── Fuzzy matching (typo tolerance) ──
      if (bestScore == 0) {
        final fuzzyBrand = _fuzzyScore(normalizedQuery, brand);
        final fuzzyGeneric = _fuzzyScore(normalizedQuery, generic);
        final bestFuzzy = fuzzyBrand > fuzzyGeneric ? fuzzyBrand : fuzzyGeneric;

        if (bestFuzzy > 0.6) {
          bestScore = bestFuzzy * 10;
          matchedField = fuzzyBrand > fuzzyGeneric ? 'brand' : 'generic';
          matchedText = fuzzyBrand > fuzzyGeneric
              ? getBrandName(item)
              : (getGenericName(item) ?? '');
        }
      }

      if (bestScore > 0) {
        results.add(SearchResult(
          item: item,
          score: bestScore,
          matchedField: matchedField,
          matchedText: matchedText,
        ));
      }
    }

    // Sort by score descending (best match first)
    results.sort((a, b) => b.score.compareTo(a.score));

    return results;
  }

  /// Score a single field against the query.
  static double _scoreField(String query, String field) {
    if (field.isEmpty) return 0;

    // Exact match
    if (field == query) return 100;

    // Starts with
    if (field.startsWith(query)) return 80;

    // Word-level starts with (e.g., "para" matches "Paracetamol 500mg")
    final words = field.split(RegExp(r'[\s\-_/]+'));
    for (final word in words) {
      if (word.startsWith(query)) return 75;
    }

    // Contains
    if (field.contains(query)) return 60;

    // Individual query words all present
    final queryWords = query.split(RegExp(r'\s+'));
    if (queryWords.length > 1) {
      final allPresent = queryWords.every((w) => field.contains(w));
      if (allPresent) return 50;
    }

    return 0;
  }

  /// Fuzzy matching using Levenshtein distance.
  /// Returns a similarity score between 0.0 and 1.0.
  static double _fuzzyScore(String query, String field) {
    if (field.isEmpty || query.isEmpty) return 0;

    // Compare against each word in the field
    final words = field.split(RegExp(r'[\s\-_/]+'));
    double bestSimilarity = 0;

    for (final word in words) {
      final similarity = _stringSimilarity(query, word);
      if (similarity > bestSimilarity) bestSimilarity = similarity;
    }

    return bestSimilarity;
  }

  /// Calculate string similarity using Levenshtein distance.
  /// Returns value between 0.0 (completely different) and 1.0 (identical).
  static double _stringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    final distance = _levenshteinDistance(s1, s2);

    return 1.0 - (distance / maxLen);
  }

  /// Compute the Levenshtein distance between two strings.
  static int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> previousRow = List.generate(s2.length + 1, (i) => i);
    List<int> currentRow = List.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      currentRow[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        final cost = s1[i] == s2[j] ? 0 : 1;

        currentRow[j + 1] = [
          currentRow[j] + 1,
          previousRow[j + 1] + 1,
          previousRow[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }

      final temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }

    return previousRow[s2.length];
  }
}

// ══════════════════════════════════════════════════════════════
// HIGHLIGHTED TEXT — Shows which part of the text matched
// ══════════════════════════════════════════════════════════════
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? baseStyle;
  final Color? highlightColor;

  // ✅ FIXED: Removed const, use nullable types with runtime defaults
  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.baseStyle,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = baseStyle ?? AppTextStyles.bodyMedium;
    final color = highlightColor ?? AppColors.primary;

    if (query.isEmpty) return Text(text, style: style);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final startIndex = lowerText.indexOf(lowerQuery);

    if (startIndex == -1) return Text(text, style: style);

    final endIndex = startIndex + query.length;

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text.substring(0, startIndex),
            style: style,
          ),
          TextSpan(
            text: text.substring(startIndex, endIndex),
            style: style.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              backgroundColor: color.withValues(alpha: 0.1),
            ),
          ),
          TextSpan(
            text: text.substring(endIndex),
            style: style,
          ),
        ],
      ),
    );
  }
}