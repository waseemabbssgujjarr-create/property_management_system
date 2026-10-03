import 'package:flutter/material.dart';

/// Munshi spacing system.
/// 4pt base scale: 4, 8, 12, 16, 24, 32, 48, 64
abstract final class AppSpacing {
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double base = 16;
  static const double lg   = 24;
  static const double xl   = 32;
  static const double xxl  = 48;
  static const double xxxl = 64;

  // ── Touch targets ─────────────────────────────────────────────────────────
  /// Home action buttons — 96dp minimum
  static const double homeButtonSize = 96;
  /// Standard touch targets — 48dp minimum (WCAG)
  static const double touchTarget = 48;

  // ── Border radius ─────────────────────────────────────────────────────────
  static const double radiusCard    = 12;
  static const double radiusSheet   = 16;
  static const double radiusPill    = 100;
  static const double radiusButton  = 12;
  static const double radiusChip    = 8;
  static const double radiusImage   = 8;

  static const BorderRadius cardRadius   = BorderRadius.all(Radius.circular(radiusCard));
  static const BorderRadius sheetRadius  = BorderRadius.vertical(top: Radius.circular(radiusSheet));
  static const BorderRadius pillRadius   = BorderRadius.all(Radius.circular(radiusPill));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(radiusButton));

  // ── Page padding ──────────────────────────────────────────────────────────
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: base, vertical: lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(base);
  static const EdgeInsets chipPadding = EdgeInsets.symmetric(horizontal: md, vertical: sm);

  // ── Screen edge clearance ─────────────────────────────────────────────────
  static const double screenHorizontal = base;
  static const double screenVertical   = lg;
}

/// Munshi elevation system — soft, large-radius shadows (premium feel).
abstract final class AppElevation {
  static const List<BoxShadow> none = [];

  static const List<BoxShadow> low = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, 4),
      spreadRadius: -2,
    ),
  ];

  static const List<BoxShadow> high = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -4,
    ),
  ];

  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 40,
      offset: Offset(0, -4),
      spreadRadius: 0,
    ),
  ];
}
