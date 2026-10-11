// The Dart Excel builders must match test/fixtures/export_doc.json, and the data copy
// must read back into the same orders.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/hijri.dart';
import 'package:wo_tracker/domain/insights.dart';
import 'package:wo_tracker/domain/order_input.dart';
import 'package:wo_tracker/domain/rules_engine.dart';
import 'package:wo_tracker/i18n/strings.dart';
import 'package:wo_tracker/report/export_doc.dart';

void main() {
  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  Object? plain(Object? o) => jsonDecode(jsonEncode(o));
  final rules = json('assets/rules/rules.json');
  final en = json('assets/i18n/en.json');
  final ar = json('assets/i18n/ar.json');
  final hijri = HijriCalendar(json('assets/calendar/umalqura.json'));
  final demo = json('assets/demo/demo_orders.json');
  final orders = (demo['orders'] as List).map((o) => OrderInput.fromJson(Map<String, dynamic>.from(o as Map))).toList();
  final fx = json('test/fixtures/export_doc.json');
  final exporter = ExportDoc(Insights(RulesEngine(rules)));

  for (final c in (fx['report'] as List).cast<Map<String, dynamic>>()) {
    test('${c['kind']} report workbook in ${c['lang']}', () {
      final lang = c['lang'] as String;
      final wb = exporter.reportWorkbook(orders, c['kind'] as String, c['date'] as String, c['today'] as String,
          s: Strings(lang, lang == 'ar' ? ar : en, en, rules), hijri: hijri, preparedBy: c['preparedBy'] as String, generatedAt: c['generatedAt'] as String?);
      final got = plain(wb) as Map<String, dynamic>;
      final want = c['workbook'] as Map<String, dynamic>;
      expect(got['fileName'], want['fileName']);
      final gs = got['sheets'] as List, ws = want['sheets'] as List;
      expect(gs.length, ws.length);
      for (var i = 0; i < ws.length; i++) {
        final g = gs[i] as Map, w = ws[i] as Map;
        expect(g['name'], w['name']);
        expect(g['columns'], w['columns'], reason: '${w['name']} columns');
        final gr = g['rows'] as List, wr = w['rows'] as List;
        expect(gr.length, wr.length, reason: '${w['name']} row count');
        for (var j = 0; j < wr.length; j++) {
          expect(gr[j], wr[j], reason: '${w['name']} row $j');
        }
        expect(g['totals'], w['totals']);
        expect(g['rowFormulas'], w['rowFormulas']);
      }
    });
  }

  test('data workbook matches, and reads back into the same orders', () {
    final d = fx['data'] as Map<String, dynamic>;
    final wb = plain(exporter.dataWorkbook(orders, d['today'] as String, d['generatedAt'] as String)) as Map<String, dynamic>;
    final want = d['workbook'] as Map<String, dynamic>;
    for (var i = 0; i < (want['sheets'] as List).length; i++) {
      expect((wb['sheets'] as List)[i], (want['sheets'] as List)[i], reason: (want['sheets'] as List)[i]['name'] as String);
    }
    expect(wb['about'], want['about']);
    final back = ExportDoc.ordersFromDataWorkbook(want);
    final again = plain(exporter.dataWorkbook(back, d['today'] as String, d['generatedAt'] as String));
    expect(again, want, reason: 'export → read back → export gives the same file');
  });
}
