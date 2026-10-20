// Colours, type and spacing from the design canvas ("Work Order Tracker Screens").
import 'package:flutter/material.dart';

/// The colour palette. `C.dark` picks the light or the dark set; it is switched once per
/// build in main.dart, and every screen reads these getters, so nothing is hard-coded per screen.
class C {
  static bool dark = false;
  static Color _p(int light, int night) => Color(dark ? night : light);

  static Color get ink => _p(0xFF15181C, 0xFFE8EBEF);
  static Color get muted => _p(0xFF4F5861, 0xFFB0B8C2);
  static Color get faint => _p(0xFF6B747C, 0xFF8E98A4);
  static Color get line => _p(0xFFE2E5E1, 0xFF2C333C);
  static Color get lineSoft => _p(0xFFECEEEB, 0xFF232A32);
  static Color get field => _p(0xFFD5D9D4, 0xFF3B4550);
  static Color get bg => _p(0xFFF4F5F3, 0xFF0F1216);
  static Color get card => _p(0xFFFFFFFF, 0xFF171B21);
  static Color get chip => _p(0xFFEEF0ED, 0xFF212830);
  static Color get panel => _p(0xFFF8F9F7, 0xFF13171C); // a quiet box inside a card
  static Color get panel2 => _p(0xFFFBFBFA, 0xFF13171C);
  static Color get accent => _p(0xFF2152C4, 0xFF7BA3FF);
  static Color get accentDark => _p(0xFF173C94, 0xFFA9C2FF);
  static Color get accentSoft => _p(0xFFEAF0FC, 0xFF1C2A47);
  static Color get critical => _p(0xFFB3261E, 0xFFFF8F86);
  static Color get criticalSoft => _p(0xFFFBECEA, 0xFF3B2020);
  static Color get warning => _p(0xFF9A5B00, 0xFFF0B450);
  static Color get warningEdge => _p(0xFFC98A1B, 0xFFD99A2B);
  static Color get warningSoft => _p(0xFFFCF2E1, 0xFF382D17);
  static Color get success => _p(0xFF23784A, 0xFF62CC91);
  static Color get successSoft => _p(0xFFE7F4EC, 0xFF16301F);
  static Color get locked => _p(0xFF9AA19B, 0xFF5F6975);
  // Text on a solid coloured fill (accent, stage colours, the done tick).
  static Color get onSolid => _p(0xFFFFFFFF, 0xFF0B0F14);
  // The dark bar (selection bar, toasts, tooltips): near-black on light, a raised grey on dark.
  static Color get inverse => _p(0xFF15181C, 0xFF2B323B);
  static Color get onInverse => _p(0xFFFFFFFF, 0xFFE8EBEF);
  static Color get onInverseSoft => _p(0xFFC4C9C3, 0xFFB0B8C2);
}

/// One colour per board stage, so a column (and the card in it) is known at a glance.
Color stageColor(String key) => C.dark
    ? switch (key) {
        'kashfeya' => const Color(0xFFA3B1C0),
        'tasreeh' => const Color(0xFFF0B450),
        'starting' => const Color(0xFF4FD0D6),
        'civil' => const Color(0xFF7BA3FF),
        'restoration' => const Color(0xFFFF9A6B),
        'meter' => const Color(0xFFBE9CFF),
        'closeout' => const Color(0xFF62CC91),
        _ => C.accent,
      }
    : switch (key) {
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

ThemeData appTheme({required bool arabic, bool dark = false}) {
  C.dark = dark;
  final family = arabic ? sansAr : sansEn;
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: family,
    fontFamilyFallback: const [sansAr, sansEn],
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.accent,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: C.card,
      primary: C.accent,
      error: C.critical,
    ),
    scaffoldBackgroundColor: C.bg,
    // Compact on PC (more on screen), normal touch sizes on the phone.
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
  final text = base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink);
  final veil = dark ? const Color(0x99000000) : Colors.black54;
  return base.copyWith(
    shadowColor: Colors.black,
    bottomSheetTheme: BottomSheetThemeData(modalBarrierColor: veil),
    drawerTheme: DrawerThemeData(scrimColor: veil),
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 13.5),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: C.faint),
    ),
    dividerTheme: DividerThemeData(color: C.lineSoft, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: C.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)), side: BorderSide(color: C.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
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
        foregroundColor: C.onSolid,
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        side: BorderSide(color: C.field),
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
      backgroundColor: C.inverse,
      contentTextStyle: TextStyle(color: C.onInverse, fontSize: 13.5),
      actionTextColor: dark ? C.accentDark : const Color(0xFF9DB8F5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: C.field),
      backgroundColor: C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: C.inverse, borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(color: C.onInverse, fontSize: 12.5),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dialogTheme: DialogThemeData(backgroundColor: C.card, barrierColor: veil, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
  );
}

const monoStyle = TextStyle(fontFamily: mono, fontFeatures: [FontFeature.tabularFigures()]);
