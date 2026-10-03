/// Money formatting utilities for Munshi.
///
/// Rules (from build guide §5.2):
/// - NEVER display raw millions to the owner: 12500000 → ₨ 1.25 کروڑ
/// - Always use lac/crore format for amounts >= 1 lac
/// - Latin digits only (never Urdu/Arabic digits for money)
/// - Spoken form: "ایک کروڑ پچیس لاکھ روپے"
/// - Money stored as BIGINT rupees (integer)
library;

import 'dart:math' as math;

class MoneyFormatter {
  MoneyFormatter._();

  static const _lac   = 100000;    // 1 Lac  = 100,000
  static const _crore = 10000000;  // 1 Crore = 10,000,000

  // ── Display formatting ────────────────────────────────────────────────────

  /// Format an integer rupee amount for display.
  /// Examples:
  ///   45000     → ₨ 45,000
  ///   8500000   → ₨ 85 لاکھ
  ///   12500000  → ₨ 1.25 کروڑ
  ///   125000000 → ₨ 12.5 کروڑ
  static String format(int rupees, {bool showSymbol = true}) {
    final prefix = showSymbol ? '₨ ' : '';
    if (rupees < 0) return '${prefix}0';

    if (rupees >= _crore) {
      final crores = rupees / _crore;
      final formatted = _trimTrailingZeros(crores.toStringAsFixed(2));
      return '$prefix$formatted کروڑ';
    }

    if (rupees >= _lac) {
      final lacs = rupees / _lac;
      final formatted = _trimTrailingZeros(lacs.toStringAsFixed(2));
      return '$prefix$formatted لاکھ';
    }

    // Below 1 lac: show with commas
    return '$prefix${_withCommas(rupees)}';
  }

  /// Compact format (no symbol, for chips/small spaces)
  static String compact(int rupees) => format(rupees, showSymbol: false);

  /// Full format with always-visible symbol
  static String full(int rupees) => format(rupees, showSymbol: true);

  /// Format as pure number with commas (for receipts, audit)
  static String withCommas(int rupees) => _withCommas(rupees);

  // ── Spoken form (Urdu TTS) ────────────────────────────────────────────────

  /// Returns Urdu spoken text for TTS.
  /// Examples:
  ///   45000    → "پینتالیس ہزار روپے"
  ///   8500000  → "پچاسی لاکھ روپے"
  ///   12500000 → "ایک کروڑ پچیس لاکھ روپے"
  static String toSpokenUrdu(int rupees) {
    if (rupees <= 0) return 'صفر روپے';

    if (rupees >= _crore) {
      final fullCrores = rupees ~/ _crore;
      final remainder  = rupees % _crore;
      final lacs       = remainder ~/ _lac;

      final croreText = '${_urduNumber(fullCrores)} کروڑ';
      if (lacs > 0) {
        return '$croreText ${_urduNumber(lacs)} لاکھ روپے';
      }
      return '$croreText روپے';
    }

    if (rupees >= _lac) {
      final lacs       = rupees ~/ _lac;
      final remainder  = rupees % _lac;
      final thousands  = remainder ~/ 1000;

      final lacText = '${_urduNumber(lacs)} لاکھ';
      if (thousands > 0) {
        return '$lacText ${_urduNumber(thousands)} ہزار روپے';
      }
      return '$lacText روپے';
    }

    if (rupees >= 1000) {
      final thousands = rupees ~/ 1000;
      final remainder = rupees % 1000;
      final thousandText = '${_urduNumber(thousands)} ہزار';
      if (remainder > 0) {
        return '$thousandText ${_urduNumber(remainder)} روپے';
      }
      return '$thousandText روپے';
    }

    return '${_urduNumber(rupees)} روپے';
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Parse a formatted string back to integer rupees.
  /// Handles: "1.25 کروڑ", "85 لاکھ", "45,000", "45000"
  static int? parse(String input) {
    final cleaned = input
        .replaceAll('₨', '')
        .replaceAll(',', '')
        .trim();

    if (cleaned.contains('کروڑ')) {
      final num = double.tryParse(
        cleaned.replaceAll('کروڑ', '').trim(),
      );
      return num != null ? (num * _crore).round() : null;
    }

    if (cleaned.contains('لاکھ')) {
      final num = double.tryParse(
        cleaned.replaceAll('لاکھ', '').trim(),
      );
      return num != null ? (num * _lac).round() : null;
    }

    return int.tryParse(cleaned);
  }

  // ── Validation ────────────────────────────────────────────────────────────

  static bool isValidAmount(int? amount) =>
      amount != null && amount >= 0;

  static bool isPositiveAmount(int? amount) =>
      amount != null && amount > 0;

  // ── Private helpers ───────────────────────────────────────────────────────

  static String _withCommas(int n) {
    // Pakistani number format: 12,34,567 (but dealers use 1,23,45,678 etc.)
    // We use standard international: 12,345,678
    return n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  static String _trimTrailingZeros(String s) {
    if (!s.contains('.')) return s;
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.replaceAll('.', '');
    return s;
  }

  /// Basic Urdu number words for TTS (covers common property-deal ranges)
  static String _urduNumber(int n) {
    // For larger numbers just use the digit string — TTS will read them
    if (n > 99) return n.toString();
    const ones = [
      '', 'ایک', 'دو', 'تین', 'چار', 'پانچ', 'چھ', 'سات', 'آٹھ', 'نو',
      'دس', 'گیارہ', 'بارہ', 'تیرہ', 'چودہ', 'پندرہ', 'سولہ', 'سترہ',
      'اٹھارہ', 'انیس', 'بیس', 'اکیس', 'بائیس', 'تئیس', 'چوبیس', 'پچیس',
      'چھبیس', 'ستائیس', 'اٹھائیس', 'انتیس', 'تیس', 'اکتیس', 'بتیس',
      'تینتیس', 'چونتیس', 'پینتیس', 'چھتیس', 'سینتیس', 'اڑتیس', 'انتالیس',
      'چالیس', 'اکتالیس', 'بیالیس', 'تینتالیس', 'چوالیس', 'پینتالیس',
      'چھیالیس', 'سینتالیس', 'اڑتالیس', 'انچاس', 'پچاس', 'اکیاون', 'باون',
      'ترپن', 'چوون', 'پچپن', 'چھپن', 'ستاون', 'اٹھاون', 'انسٹھ', 'ساٹھ',
      'اکسٹھ', 'باسٹھ', 'تریسٹھ', 'چوسٹھ', 'پینسٹھ', 'چھیاسٹھ', 'سریسٹھ',
      'اڑسٹھ', 'انہتر', 'ستر', 'اکہتر', 'بہتر', 'تہتر', 'چوہتر', 'پچہتر',
      'چھہتر', 'ستہتر', 'اٹھہتر', 'انہاتر', 'اسی', 'اکیاسی', 'بیاسی',
      'تراسی', 'چوراسی', 'پچاسی', 'چھیاسی', 'ستاسی', 'اٹھاسی', 'نواسی',
      'نوے', 'اکانوے', 'بانوے', 'ترانوے', 'چورانوے', 'پچانوے', 'چھیانوے',
      'ستانوے', 'اٹھانوے', 'ننانوے',
    ];
    if (n >= 0 && n < ones.length) return ones[n];
    return n.toString();
  }
}

// ── Convenience top-level functions ────────────────────────────────────────

/// Format rupees for display. The primary display function.
String formatMoney(int rupees) => MoneyFormatter.format(rupees);

/// Format rupees as spoken Urdu text for TTS.
String speakAmount(int rupees) => MoneyFormatter.toSpokenUrdu(rupees);

/// Format rupees without symbol (for secondary displays).
String compactMoney(int rupees) => MoneyFormatter.compact(rupees);
