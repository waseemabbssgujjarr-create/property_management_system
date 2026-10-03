import 'package:flutter/material.dart';

/// Munshi design token colors.
/// NEVER use raw hex values outside this file.
/// All color usage must reference these constants.
abstract final class AppColors {
  // ── Brand (trust + prosperity — deep green) ──────────────────────────────
  static const brand900 = Color(0xFF0B3D2E);
  static const brand700 = Color(0xFF0A5239);
  static const brand600 = Color(0xFF0E7A5F);
  static const brand400 = Color(0xFF24A87E);
  static const brand100 = Color(0xFFE3F3EC);
  static const brand50  = Color(0xFFF0FAF5);

  // ── Gold (success, highlight, closed deal) ────────────────────────────────
  static const gold500 = Color(0xFFC9A227);
  static const gold300 = Color(0xFFE8C94E);
  static const gold100 = Color(0xFFFDF3CE);

  // ── Ink / Text ────────────────────────────────────────────────────────────
  static const ink900   = Color(0xFF14201B);
  static const ink700   = Color(0xFF2E3D36);
  static const ink500   = Color(0xFF5C6F66);
  static const ink300   = Color(0xFF8FA09A);
  static const ink100   = Color(0xFFD6DDD9);

  // ── Surface ───────────────────────────────────────────────────────────────
  static const paper       = Color(0xFFF7F5EF); // warm, register feel
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceHigh = Color(0xFFF2F0EA);

  // ── Dark mode surfaces ────────────────────────────────────────────────────
  static const paperDark   = Color(0xFF101613);
  static const inkDark     = Color(0xFFEDEBE3);
  static const surfaceDark = Color(0xFF1A211D);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const success = Color(0xFF1B8A4B);
  static const warn    = Color(0xFFD97706);
  static const danger  = Color(0xFFC0392B);
  static const info    = Color(0xFF2563EB);

  // ── Money direction ───────────────────────────────────────────────────────
  /// Use for ALL money-in amounts everywhere, without exception
  static const moneyIn  = success;
  /// Use for ALL money-out amounts everywhere, without exception
  static const moneyOut = danger;

  // ── Deal stage colors (FIXED — never change) ──────────────────────────────
  static const stageInquiry  = Color(0xFF9AA5B1); // gray
  static const stageToken    = Color(0xFFD97706); // amber
  static const stageBayana   = Color(0xFF2563EB); // blue
  static const stageRegistry = Color(0xFF7C3AED); // purple
  static const stageClosed   = Color(0xFFC9A227); // gold
  static const stageLost     = Color(0xFF3A3A3A); // dark

  // ── Property status colors ────────────────────────────────────────────────
  static const statusAvailable  = success;
  static const statusTokenGiven = stageToken;
  static const statusBayanaDone = stageBayana;
  static const statusSold       = stageClosed;
  static const statusWithdrawn  = stageLost;

  // ── Urgency ──────────────────────────────────────────────────────────────
  static const urgencyHot  = danger;
  static const urgencyWarm = warn;
  static const urgencyCold = stageInquiry;
}

/// Returns the correct deal stage color for a given stage string.
Color dealStageColor(String stage) => switch (stage) {
  'inquiry'  => AppColors.stageInquiry,
  'token'    => AppColors.stageToken,
  'bayana'   => AppColors.stageBayana,
  'registry' => AppColors.stageRegistry,
  'closed'   => AppColors.stageClosed,
  'lost'     => AppColors.stageLost,
  _          => AppColors.stageInquiry,
};

/// Returns the correct property status color.
Color propertyStatusColor(String status) => switch (status) {
  'available'   => AppColors.statusAvailable,
  'token_given' => AppColors.statusTokenGiven,
  'bayana_done' => AppColors.statusBayanaDone,
  'sold'        => AppColors.statusSold,
  'withdrawn'   => AppColors.statusWithdrawn,
  _             => AppColors.ink300,
};
