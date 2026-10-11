// Runs the shared golden fixtures against the Dart engine.
// The same file is checked by tools/rules-check (node --test), so both engines agree.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/order_input.dart';
import 'package:wo_tracker/domain/rules_engine.dart';

void main() {
  final rules = jsonDecode(File('assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
  final golden = jsonDecode(File('test/fixtures/golden.json').readAsStringSync()) as Map<String, dynamic>;
  final engine = RulesEngine(rules);
  List<String> sorted(Iterable<String> a) => a.toList()..sort();

  group('golden scenarios', () {
    for (final c in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final order = OrderInput.fromJson(Map<String, dynamic>.from(c['order'] as Map));
        final today = c['today'] as String;
        final e = c['expect'] as Map<String, dynamic>?;
        if (e != null) {
          final r = engine.evaluate(order, today);
          if (e.containsKey('total')) expect(r.total, e['total'], reason: 'total');
          if (e.containsKey('status')) expect(r.status, e['status'], reason: 'status');
          if (e.containsKey('stage')) expect(r.stage, e['stage'], reason: 'stage');
          if (e.containsKey('ready')) expect(sorted(r.next), sorted((e['ready'] as List).cast<String>()), reason: 'ready');
          if (e.containsKey('alerts')) {
            final ea = (e['alerts'] as List).cast<Map<String, dynamic>>();
            expect(r.alerts.length, ea.length, reason: 'alert count');
            for (var i = 0; i < ea.length; i++) {
              ea[i].forEach((k, v) => expect(r.alerts[i][k], v, reason: 'alert $i $k'));
            }
          }
          ((e['reasons'] as Map?) ?? const {}).forEach((id, codes) {
            final s = r.steps.firstWhere((x) => x.id == id);
            expect(s.state, 'locked', reason: '$id locked');
            expect(s.reasons.map((x) => x.code).toList(), (codes as List).cast<String>(), reason: '$id reasons');
          });
          ((e['waitingFor'] as Map?) ?? const {}).forEach((id, waits) {
            final s = r.steps.firstWhere((x) => x.id == id);
            expect(s.reasons.firstWhere((x) => x.code == 'waiting_for').steps, (waits as List).cast<String>());
          });
        }
        for (final v in ((c['validate'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          final errs = engine.validateMarkDone(order, v['step'] as String, v['date'] as String, today).map((x) => x.code).toList();
          expect(errs, (v['errors'] as List).cast<String>(), reason: 'validate ${v['step']} on ${v['date']}');
        }
      });
    }
  });

  group('clear impact', () {
    for (final c in (golden['clearImpact'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final order = OrderInput.fromJson(Map<String, dynamic>.from(c['order'] as Map));
        expect(engine.clearImpact(order, c['step'] as String), (c['expect'] as List).cast<String>());
      });
    }
  });

  group('order checks', () {
    for (final c in (golden['validateOrder'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final order = OrderInput.fromJson(Map<String, dynamic>.from(c['order'] as Map));
        expect(engine.validateOrder(order).map((r) => r.code).toList(), (c['errors'] as List).cast<String>());
      });
    }
  });

  test('validation errors carry the tasreeh number and segment', () {
    final o = OrderInput.fromJson({
      'type': '402', 'category': 'extension', 'woNumber': '441700709',
      'permits': [{'number': 'P-1'}, {'number': 'P-1'}],
      'segments': [{'id': 's2', 'base': 'asphalt', 'width': 60, 'lengthM': 12}],
    });
    final e = engine.validateOrder(o);
    expect(e.firstWhere((r) => r.code == 'duplicate_permit').permit, 'P-1');
    expect(e.firstWhere((r) => r.code == 'bad_segment_width').segment, 's2');
  });

  test('days: calendar days with hold periods removed', () {
    expect(activeDays('2026-10-06', '2026-10-11'), 5);
    expect(activeDays('2026-10-06', '2026-10-11', const [HoldPeriod(from: '2026-10-07', to: '2026-10-09')]), 3);
    expect(activeDays('2026-10-06', '2026-10-11', const [HoldPeriod(from: '2026-10-08')]), 2);
    expect(activeDays('2026-12-30', '2027-01-02'), 3);
    expect(activeDays('2028-02-28', '2028-03-01'), 2);
    expect(fromDay(toDay('2026-10-11')), '2026-10-11');
  });
}
