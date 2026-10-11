// The Dart report builder must produce exactly the documents in test/fixtures/report_doc.json,
// which come from the reference builder (tools/rules-check/report-doc.mjs).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/hijri.dart';
import 'package:wo_tracker/domain/insights.dart';
import 'package:wo_tracker/domain/order_input.dart';
import 'package:wo_tracker/domain/rules_engine.dart';
import 'package:wo_tracker/i18n/strings.dart';
import 'package:wo_tracker/report/report_doc.dart';

void main() {
  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  final rules = json('assets/rules/rules.json');
  final en = json('assets/i18n/en.json');
  final ar = json('assets/i18n/ar.json');
  final hijri = HijriCalendar(json('assets/calendar/umalqura.json'));
  final demo = json('assets/demo/demo_orders.json');
  final orders = (demo['orders'] as List).map((o) => OrderInput.fromJson(Map<String, dynamic>.from(o as Map))).toList();
  final builder = ReportDoc(Insights(RulesEngine(rules)));

  for (final c in (json('test/fixtures/report_doc.json')['cases'] as List).cast<Map<String, dynamic>>()) {
    test('${c['kind']} report in ${c['lang']}', () {
      final lang = c['lang'] as String;
      final s = Strings(lang, lang == 'ar' ? ar : en, en, rules);
      final doc = builder.build(orders, c['kind'] as String, c['date'] as String, c['today'] as String,
          s: s, hijri: hijri, preparedBy: c['preparedBy'] as String, generatedAt: c['generatedAt'] as String?);
      final got = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
      final want = c['doc'] as Map<String, dynamic>;
      for (final k in want.keys) {
        expect(got[k], want[k], reason: k);
      }
      expect(got.keys.toSet(), want.keys.toSet());
    });
  }
}
