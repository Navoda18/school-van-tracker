import 'package:flutter/material.dart';

const busYellow = Color(0xFFFFC107);
const ink = Color(0xFF1F2430);
const paper = Color(0xFFFFFBEF);

const softCardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(16)),
  side: BorderSide(color: Color(0xFFF0E2B0)),
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: busYellow).copyWith(
    primary: busYellow,
    onPrimary: ink,
    primaryContainer: const Color(0xFFFFEFB8),
    onPrimaryContainer: ink,
    secondary: ink,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: busYellow,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle:
          TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
        textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: busYellow,
      foregroundColor: ink,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: ink,
        selectedBackgroundColor: busYellow,
        selectedForegroundColor: ink,
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Color(0xFFFFEFB8),
      labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
      side: BorderSide.none,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
  );
}