// Colours, type and spacing from the design canvas ("Work Order Tracker Screens").
import 'package:flutter/material.dart';

class C {
  static const ink = Color(0xFF15181C);
  static const muted = Color(0xFF4F5861);
  static const faint = Color(0xFF6B747C);
  static const line = Color(0xFFE2E5E1);
  static const lineSoft = Color(0xFFECEEEB);
  static const field = Color(0xFFD5D9D4);
  static const bg = Color(0xFFF4F5F3);
  static const card = Color(0xFFFFFFFF);
  static const chip = Color(0xFFEEF0ED);
  static const accent = Color(0xFF2152C4);
  static const accentDark = Color(0xFF173C94);
  static const accentSoft = Color(0xFFEAF0FC);
  static const critical = Color(0xFFB3261E);
  static const criticalSoft = Color(0xFFFBECEA);
  static const warning = Color(0xFF9A5B00);
  static const warningEdge = Color(0xFFC98A1B);
  static const warningSoft = Color(0xFFFCF2E1);
  static const success = Color(0xFF23784A);
  static const successSoft = Color(0xFFE7F4EC);
  static const locked = Color(0xFF9AA19B);
}

const sansEn = 'IBMPlexSans';
const sansAr = 'IBMPlexSansArabic';
const mono = 'IBMPlexMono';

ThemeData appTheme({required bool arabic}) {
  final family = arabic ? sansAr : sansEn;
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: family,
    fontFamilyFallback: const [sansAr, sansEn],
    colorScheme: ColorScheme.fromSeed(seedColor: C.accent, surface: C.card, primary: C.accent, error: C.critical),
    scaffoldBackgroundColor: C.bg,
    // Compact on PC (more on screen), normal touch sizes on the phone.
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
  final text = base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink);
  return base.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 13.5),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: C.faint),
    ),
    dividerTheme: const DividerThemeData(color: C.lineSoft, thickness: 1, space: 1),
    cardTheme: const CardThemeData(
      color: C.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)), side: BorderSide(color: C.line)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: C.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6)), borderSide: BorderSide(color: C.field)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6)), borderSide: BorderSide(color: C.field)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6)), borderSide: BorderSide(color: C.accent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6)), borderSide: BorderSide(color: C.critical)),
      labelStyle: TextStyle(color: C.muted, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        side: const BorderSide(color: C.field),
        textStyle: const TextStyle(fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accent, textStyle: const TextStyle(fontSize: 13.5)),
    ),
    // Segmented buttons keep each label on one line where they can.
    segmentedButtonTheme: const SegmentedButtonThemeData(
      style: ButtonStyle(visualDensity: VisualDensity.compact, textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13))),
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: C.ink, actionTextColor: Color(0xFF9DB8F5)),
    dialogTheme: const DialogThemeData(backgroundColor: C.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
  );
}

const monoStyle = TextStyle(fontFamily: mono, fontFeatures: [FontFeature.tabularFigures()]);
