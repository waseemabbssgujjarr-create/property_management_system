import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Munshi typography system.
///
/// Rules:
/// - Urdu display/headlines: NotoNastaliqUrdu (RTL, display only)
/// - Urdu body/labels: NotoNaskhArabic (readable body text)
/// - Latin/numerals: Inter (always, including money figures)
/// - Money figures: tabular nums, minimum 24sp on owner-facing screens
/// - NEVER show raw millions — always lac/crore format
abstract final class AppTypography {
  // ── Urdu display (Nastaliq — headings only) ───────────────────────────────
  static TextStyle get urDisplayLarge => const TextStyle(
    fontFamily: 'NotoNastaliqUrdu',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.6, // Nastaliq needs more line height
  );

  static TextStyle get urH1 => const TextStyle(
    fontFamily: 'NotoNastaliqUrdu',
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.6,
  );

  static TextStyle get urH2 => const TextStyle(
    fontFamily: 'NotoNastaliqUrdu',
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.6,
  );

  // ── Urdu body (Naskh — readable body text) ───────────────────────────────
  static TextStyle get urBody => const TextStyle(
    fontFamily: 'NotoNaskhArabic',
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.ink900,
    height: 1.6,
  );

  static TextStyle get urBodyMedium => const TextStyle(
    fontFamily: 'NotoNaskhArabic',
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.ink900,
    height: 1.6,
  );

  static TextStyle get urBodyBold => const TextStyle(
    fontFamily: 'NotoNaskhArabic',
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.6,
  );

  static TextStyle get urCaption => const TextStyle(
    fontFamily: 'NotoNaskhArabic',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.ink500,
    height: 1.5,
  );

  static TextStyle get urLabel => const TextStyle(
    fontFamily: 'NotoNaskhArabic',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.ink700,
    height: 1.5,
  );

  // ── Latin/Numerals (Inter) ────────────────────────────────────────────────
  static TextStyle get display => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.2,
  );

  static TextStyle get h1 => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.25,
  );

  static TextStyle get h2 => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.3,
  );

  static TextStyle get body => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.ink900,
    height: 1.5,
  );

  static TextStyle get bodyMedium => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.ink900,
    height: 1.5,
  );

  static TextStyle get caption => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.ink500,
    height: 1.4,
  );

  // ── Money figures (critical — minimum 24sp, tabular nums) ─────────────────
  /// Owner-facing money display. 32sp. Tabular, bold.
  static TextStyle get moneyHero => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Standard money figure. 24sp minimum.
  static TextStyle get moneyLarge => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle get moneyMedium => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.ink900,
    height: 1.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle get moneySmall => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.ink700,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ── Number pad digits ─────────────────────────────────────────────────────
  static TextStyle get numPadDigit => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 26,
    fontWeight: FontWeight.w500,
    color: AppColors.ink900,
    height: 1,
  );

  static TextStyle get numPadPreview => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.ink900,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
