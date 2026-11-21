import 'package:characters/characters.dart';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const navy = Color(0xFF0F172A);
  static const amber = Color(0xFFF59E0B);
  static const amberSoft = Color(0xFFFEF3C7);
  static const success = Color(0xFF10B981);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);
  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE2E8F0);
  static const muted = Color(0xFF64748B);
}

/// 8pt grid
class AppSpace {
  static const double xs = 8, sm = 12, md = 16, lg = 24, xl = 32;
}

class AppRadius {
  static const double card = 16, sheet = 24;
}

/// Use on numbers that change (ETA, speed, times) so the digits do not jump around.
const tabularFigures = [FontFeature.tabularFigures()];

// Old names used by existing screens. Kept so nothing breaks while we refactor.
const busYellow = AppColors.amber;
const ink = AppColors.navy;
const paper = AppColors.background;
const softCardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
  side: BorderSide(color: AppColors.border),
);

/// Amber style for the ONE main call-to-action on a screen.
final ButtonStyle accentButton = FilledButton.styleFrom(
  backgroundColor: AppColors.amber,
  foregroundColor: AppColors.navy,
);

OutlineInputBorder _outline(Color c, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: width),
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.navy).copyWith(
    primary: AppColors.navy,
    onPrimary: Colors.white,
    secondary: AppColors.amber,
    onSecondary: AppColors.navy,
    tertiary: AppColors.info,
    error: AppColors.danger,
    surface: AppColors.surface,
    onSurface: AppColors.navy,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    // Apply Inter to each style one by one. GoogleFonts.interTextTheme returns a
  // different TextTheme type in google_fonts 9, so we avoid it.
  TextStyle? inter(TextStyle? s) =>
      s == null ? null : GoogleFonts.inter(textStyle: s);
  final t = base.textTheme.apply(
    bodyColor: AppColors.navy,
    displayColor: AppColors.navy,
  );
  final text = t.copyWith(
    displayLarge: inter(t.displayLarge),
    displayMedium: inter(t.displayMedium),
    displaySmall: inter(t.displaySmall),
    headlineLarge: inter(t.headlineLarge),
    headlineMedium: inter(t.headlineMedium),
    headlineSmall: GoogleFonts.inter(
        fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.navy),
    titleLarge: GoogleFonts.inter(
        fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
    titleMedium: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy),
    titleSmall: inter(t.titleSmall),
    bodyLarge: inter(t.bodyLarge),
    bodyMedium: inter(t.bodyMedium),
    bodySmall: GoogleFonts.inter(fontSize: 12, color: AppColors.muted),
    labelLarge: inter(t.labelLarge),
    labelMedium: inter(t.labelMedium),
    labelSmall: inter(t.labelSmall),
  );
  
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: text,
    primaryTextTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      titleTextStyle: text.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.navy,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.amber,
      foregroundColor: AppColors.navy,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 14),
      border: _outline(AppColors.border),
      enabledBorder: _outline(AppColors.border),
      disabledBorder: _outline(AppColors.border),
      focusedBorder: _outline(AppColors.navy, width: 1.6),
      errorBorder: _outline(AppColors.danger),
      focusedErrorBorder: _outline(AppColors.danger, width: 1.6),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: softCardShape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0xFFCBD5E1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.navy,
        selectedBackgroundColor: AppColors.navy,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF1F5F9),
      labelStyle: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navy,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.navy),
  );
}