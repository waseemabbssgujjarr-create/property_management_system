import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_typography.dart';
import 'app_spacing.dart';

/// Munshi Material 3 theme.
/// Light and dark variants — dealers use phones at night.
abstract final class AppTheme {
  // ─── Light theme ──────────────────────────────────────────────────────────
  static ThemeData get light {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.brand600,
      onPrimary: Colors.white,
      primaryContainer: AppColors.brand100,
      onPrimaryContainer: AppColors.brand900,
      secondary: AppColors.gold500,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.gold100,
      onSecondaryContainer: AppColors.ink900,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: const Color(0xFFFDE8E8),
      onErrorContainer: AppColors.danger,
      surface: AppColors.paper,
      onSurface: AppColors.ink900,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.ink100,
      outlineVariant: const Color(0xFFEAE8E2),
    );

    return _buildTheme(colorScheme, Brightness.light);
  }

  // ─── Dark theme ───────────────────────────────────────────────────────────
  static ThemeData get dark {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.brand400,
      onPrimary: AppColors.paperDark,
      primaryContainer: AppColors.brand900,
      onPrimaryContainer: AppColors.brand100,
      secondary: AppColors.gold300,
      onSecondary: AppColors.ink900,
      secondaryContainer: const Color(0xFF3D2E00),
      onSecondaryContainer: AppColors.gold100,
      error: const Color(0xFFFF6B6B),
      onError: AppColors.paperDark,
      errorContainer: const Color(0xFF4A1010),
      onErrorContainer: const Color(0xFFFF6B6B),
      surface: AppColors.paperDark,
      onSurface: AppColors.inkDark,
      surfaceContainerHighest: AppColors.surfaceDark,
      outline: const Color(0xFF3A4040),
      outlineVariant: const Color(0xFF2A3030),
    );

    return _buildTheme(colorScheme, Brightness.dark);
  }

  // ─── Shared builder ───────────────────────────────────────────────────────
  static ThemeData _buildTheme(ColorScheme cs, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final inkColor = isLight ? AppColors.ink900 : AppColors.inkDark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: brightness,
      scaffoldBackgroundColor: cs.surface,

      // ── Typography ──────────────────────────────────────────────────────
      textTheme: TextTheme(
        displayLarge: AppTypography.display.copyWith(color: inkColor),
        headlineLarge: AppTypography.h1.copyWith(color: inkColor),
        headlineMedium: AppTypography.h2.copyWith(color: inkColor),
        bodyLarge: AppTypography.body.copyWith(color: inkColor),
        bodyMedium: AppTypography.body.copyWith(color: inkColor, fontSize: 14),
        labelLarge: AppTypography.bodyMedium.copyWith(color: inkColor),
        labelSmall: AppTypography.caption.copyWith(color: isLight ? AppColors.ink500 : const Color(0xFF9AA5B1)),
      ),

      // ── AppBar ────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: inkColor,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        systemOverlayStyle: isLight
          ? SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: cs.surface,
            )
          : SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: cs.surface,
            ),
        titleTextStyle: AppTypography.h2.copyWith(color: inkColor),
      ),

      // ── Bottom navigation ─────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cs.surface,
        selectedItemColor: cs.primary,
        unselectedItemColor: isLight ? AppColors.ink300 : AppColors.ink500,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTypography.caption,
      ),

      // ── Cards ────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: isLight ? Colors.white : AppColors.surfaceDark,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.cardRadius),
        margin: EdgeInsets.zero,
      ),

      // ── Elevated button ──────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: const RoundedRectangleBorder(borderRadius: AppSpacing.buttonRadius),
          textStyle: AppTypography.bodyMedium.copyWith(fontFamily: 'Inter'),
          elevation: 0,
        ),
      ),

      // ── Outlined button ──────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          minimumSize: const Size(double.infinity, 52),
          shape: const RoundedRectangleBorder(borderRadius: AppSpacing.buttonRadius),
          side: BorderSide(color: cs.primary, width: 1.5),
          textStyle: AppTypography.bodyMedium.copyWith(fontFamily: 'Inter'),
        ),
      ),

      // ── Text button ───────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          textStyle: AppTypography.bodyMedium.copyWith(fontFamily: 'Inter'),
          minimumSize: const Size(48, 48),
        ),
      ),

      // ── Input decoration ──────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? AppColors.surfaceHigh : AppColors.surfaceDark,
        border: OutlineInputBorder(
          borderRadius: AppSpacing.buttonRadius,
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.buttonRadius,
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.buttonRadius,
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.buttonRadius,
          borderSide: BorderSide(color: cs.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTypography.body.copyWith(
          color: isLight ? AppColors.ink300 : AppColors.ink500,
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: isLight ? AppColors.brand50 : AppColors.surfaceDark,
        selectedColor: cs.primaryContainer,
        labelStyle: AppTypography.caption.copyWith(color: inkColor),
        shape: const StadiumBorder(),
        padding: AppSpacing.chipPadding,
      ),

      // ── Bottom sheet ─────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Colors.white : AppColors.surfaceDark,
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.sheetRadius),
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: isLight ? AppColors.ink100 : const Color(0xFF3A4040),
      ),

      // ── Dialog ──────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? Colors.white : AppColors.surfaceDark,
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.cardRadius),
        elevation: 0,
      ),

      // ── Snackbar ─────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? AppColors.ink900 : AppColors.inkDark,
        contentTextStyle: AppTypography.urBody.copyWith(
          color: isLight ? Colors.white : AppColors.paperDark,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.buttonRadius),
      ),

      // ── Divider ───────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: cs.outline,
        thickness: 1,
        space: 0,
      ),

      // ── List tile ─────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        minLeadingWidth: 0,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        titleTextStyle: AppTypography.bodyMedium.copyWith(color: inkColor),
        subtitleTextStyle: AppTypography.caption,
      ),
    );
  }
}
