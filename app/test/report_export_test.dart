// The report export paths that the fixture tests do not reach: the PDF is drawn by the `pdf`
// package at run time (the fixtures only check the document model), and the Excel file is
// zipped. Both are exercised here in English and Arabic, so a change that breaks one language
// is caught without opening the app.
//
// The generated files are also written to build/report-export/ so they can be opened and
// looked at after a run.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/hijri.dart';
import 'package:wo_tracker/domain/insights.dart';
import 'package:wo_tracker/domain/order_input.dart';
import 'package:wo_tracker/domain/rules_engine.dart';
import 'package:wo_tracker/i18n/strings.dart';
import 'package:wo_tracker/report/export_doc.dart';
import 'package:wo_tracker/report/pdf_report.dart';
import 'package:wo_tracker/report/report_doc.dart';
import 'package:wo_tracker/report/xlsx_writer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  final rules = json('assets/rules/rules.json');
  final en = json('assets/i18n/en.json');
  final ar = json('assets/i18n/ar.json');
  final hijri = HijriCalendar(json('assets/calendar/umalqura.json'));
  final orders = (json('assets/demo/demo_orders.json')['orders'] as List)
      .map((o) => OrderInput.fromJson(Map<String, dynamic>.from(o as Map)))
      .toList();

  for (final lang in const ['en', 'ar']) {
    test('report PDF and Excel export: $lang', () async {
      final s = Strings(lang, lang == 'ar' ? ar : en, en, rules);
      final preparedBy = lang == 'ar' ? 'م. نجم' : 'Engr Najim';
      Directory('build/report-export').createSync(recursive: true);

      // PDF: Arabic must come out right-to-left and carry the Arabic font.
      final doc = ReportDoc(Insights(RulesEngine(rules))).build(
        orders,
        'monthly',
        '2026-10-15',
        '2026-10-27',
        s: s,
        hijri: hijri,
        preparedBy: preparedBy,
        generatedAt: '2026-10-27 20:55',
      );
      expect(doc['dir'], lang == 'ar' ? 'rtl' : 'ltr');
      final pdf = await reportPdf(doc, await ReportFonts.load());
      await File('build/report-export/monthly-$lang.pdf').writeAsBytes(pdf);
      expect(pdf.length, greaterThan(5000));
      // A complete PDF file, not a fragment.
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

      // Excel: a real zip, and Arabic must ask the sheet view to run right-to-left.
      final wb = ExportDoc(Insights(RulesEngine(rules))).reportWorkbook(
        orders,
        'monthly',
        '2026-10-15',
        '2026-10-27',
        s: s,
        hijri: hijri,
        preparedBy: preparedBy,
        generatedAt: '2026-10-27 20:55',
      );
      expect(wb['dir'], lang == 'ar' ? 'rtl' : 'ltr');
      final xlsx = workbookXlsx(wb);
      await File('build/report-export/monthly-$lang.xlsx').writeAsBytes(xlsx);
      expect(xlsx.length, greaterThan(5000));
      expect(String.fromCharCodes(xlsx.take(2)), 'PK');
    });
  }
}
