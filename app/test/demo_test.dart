// Demo data loads in Dart and keeps every status, stage and alert after moving dates.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/demo.dart';
import 'package:wo_tracker/domain/rules_engine.dart';

void main() {
  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  final engine = RulesEngine(json('assets/rules/rules.json'));
  final file = json('assets/demo/demo_orders.json');
  final today = file['today'] as String;

  test('loads every demo order', () {
    final orders = DemoData.load(file, today);
    expect(orders.length, (file['orders'] as List).length);
    expect(orders.where((o) => o.deleted).length, 1);
  });

  for (final days in [1, 37, 400]) {
    test('moving dates by $days days changes nothing on screen', () {
      final later = fromDay(toDay(today) + days);
      final a = DemoData.load(file, today);
      final b = DemoData.load(file, later);
      for (var i = 0; i < a.length; i++) {
        final ea = engine.evaluate(a[i], today), eb = engine.evaluate(b[i], later);
        expect(eb.status, ea.status, reason: a[i].id);
        expect(eb.stage, ea.stage, reason: a[i].id);
        expect(eb.alerts.map((x) => [x.code, x['days'] ?? x['daysLeft']]).toList(),
            ea.alerts.map((x) => [x.code, x['days'] ?? x['daysLeft']]).toList(), reason: a[i].id);
      }
    });
  }
}
