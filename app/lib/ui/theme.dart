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

/// One colour per board stage, so a column (and the card in it) is known at a glance.
Color stageColor(String key) => switch (key) {
      'kashfeya' => const Color(0xFF5A6B7B),
      'tasreeh' => const Color(0xFFB36B00),
      'starting' => const Color(0xFF0F7F85),
      'civil' => const Color(0xFF2152C4),
      'restoration' => const Color(0xFFB5481C),
      'meter' => const Color(0xFF6A3FB5),
      'closeout' => const Color(0xFF23784A),
      _ => C.accent,
    };

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)), side: BorderSide(color: C.line)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: C.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: C.field)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: C.field)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: C.accent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: C.critical)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: C.critical, width: 1.5)),
      labelStyle: TextStyle(color: C.muted, fontSize: 13, fontWeight: FontWeight.w500),
      hintStyle: TextStyle(color: C.locked, fontSize: 13.5),
      helperStyle: TextStyle(color: C.faint, fontSize: 12),
      // Labels always sit above the box, so empty and filled fields look the same on every screen.
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        side: const BorderSide(color: C.field),
        textStyle: const TextStyle(fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accent, textStyle: const TextStyle(fontSize: 13.5)),
    ),
    // Segmented buttons keep each label on one line where they can.
    segmentedButtonTheme: const SegmentedButtonThemeData(
      style: ButtonStyle(visualDensity: VisualDensity.compact, textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.ink,
      actionTextColor: const Color(0xFF9DB8F5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    chipTheme: ChipThemeData(
      side: const BorderSide(color: C.field),
      backgroundColor: C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: C.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
  );
}

const monoStyle = TextStyle(fontFamily: mono, fontFeatures: [FontFeature.tabularFigures()]);
