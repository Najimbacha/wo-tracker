// Runs the shared screen/report fixtures against the Dart insights module.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/insights.dart';
import 'package:wo_tracker/domain/order_input.dart';
import 'package:wo_tracker/domain/rules_engine.dart';

void main() {
  final rules = jsonDecode(File('assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
  final fx = jsonDecode(File('test/fixtures/insights.json').readAsStringSync()) as Map<String, dynamic>;
  final ins = Insights(RulesEngine(rules));
  final orders = (fx['orders'] as List).map((e) => OrderInput.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  final today = fx['today'] as String;
  Map<String, dynamic> m(Object? o) => Map<String, dynamic>.from(o as Map);

  test('pipeline', () {
    final p = ins.pipeline(orders, today);
    final e = m(fx['pipeline']);
    expect(p.activeCount, e['activeCount']);
    m(e['steps']).forEach((k, v) {
      expect(p.steps[k]!.ready, v['ready'], reason: '$k ready');
      expect(p.steps[k]!.total, v['total'], reason: '$k total');
    });
    expect(p.buckets, m(e['buckets']));
  });

  test('starts by day', () {
    final s = ins.startsByDay(orders, today);
    final e = (fx['startsByDay'] as List).map(m).toList();
    expect(s.length, e.length);
    for (var i = 0; i < e.length; i++) {
      expect(s[i].date, e[i]['date']);
      expect(s[i].count, e[i]['count'], reason: e[i]['date'] as String);
      if (e[i]['orders'] != null) expect(s[i].orders, (e[i]['orders'] as List).cast<String>());
    }
  });

  test('board', () {
    final b = ins.board(orders, today);
    final e = m(fx['board']);
    expect(b.map((c) => c.stage).toList(), e.keys.toList());
    for (final col in b) {
      final exp = (e[col.stage] as List).map(m).toList();
      expect(col.cards.length, exp.length, reason: col.stage);
      for (var i = 0; i < exp.length; i++) {
        final c = col.cards[i];
        expect(c.id, exp[i]['id'], reason: '${col.stage}[$i] id');
        expect(c.next, exp[i]['next'], reason: '${col.stage}[$i] next');
        expect(c.daysWaiting, exp[i]['daysWaiting'], reason: '${col.stage}[$i] days');
        expect(c.severity, exp[i]['severity'], reason: '${col.stage}[$i] severity');
        if (exp[i].containsKey('startsOn')) expect(c.startsOn, exp[i]['startsOn']);
      }
    }
  });

  test('follow-up', () {
    final f = ins.followUp(orders, today);
    final e = (fx['followUp'] as List).map(m).toList();
    expect(f.length, e.length);
    for (var i = 0; i < e.length; i++) {
      expect(f[i].contractor, e[i]['contractor']);
      expect(f[i].orders, e[i]['orders']);
      expect(f[i].late, e[i]['late']);
      final groups = f[i].sortedGroups;
      final eg = (e[i]['groups'] as List).map(m).toList();
      expect(groups.map((g) => g.group).toList(), eg.map((g) => g['group']).toList(), reason: f[i].contractor);
      for (var j = 0; j < eg.length; j++) {
        expect(groups[j].severity, eg[j]['severity'], reason: '${f[i].contractor}/${eg[j]['group']} severity');
        final items = (eg[j]['items'] as List).map(m).toList();
        expect(groups[j].items.length, items.length);
        for (var k = 0; k < items.length; k++) {
          expect(groups[j].items[k].id, items[k]['id']);
          expect(groups[j].items[k].steps, (items[k]['steps'] as List).cast<String>());
          expect(groups[j].items[k].daysWaiting, items[k]['daysWaiting'], reason: '${eg[j]['group']} ${items[k]['id']} days');
          if (items[k].containsKey('startsOn')) expect(groups[j].items[k].startsOn, items[k]['startsOn']);
        }
      }
    }
  });

  group('search', () {
    for (final s in (fx['search'] as List).map(m)) {
      test('"${s['query']}"', () {
        final r = ins.search(orders, s['query'] as String, today).map((h) => [h.id, h.kind, h.value]).toList();
        expect(r, (s['results'] as List).map((e) => (e as List).cast<String>()).toList());
      });
    }
  });

  group('filters', () {
    for (final f in (fx['filters'] as List).map(m)) {
      test(f['name'] as String, () {
        expect(ins.filterOrders(orders, today, FilterCriteria.fromJson(m(f['criteria']))), (f['ids'] as List).cast<String>());
      });
    }
  });

  test('daily report', () {
    final e = m(fx['daily']);
    final d = ins.dailyReport(orders, e['date'] as String);
    final r = d.day;
    expect(r.received, e['received']);
    expect(d.receivedPrev, e['receivedPrev']);
    expect(r.stepsCompleted, e['stepsCompleted']);
    expect(r.ordersTouched, e['ordersTouched']);
    expect(r.completed, e['completed']);
    expect(d.completedPrev, e['completedPrev']);
    expect(r.open, e['open']);
    expect(r.attention, e['attention']);
    expect(r.attentionByCode, m(e['attentionByCode']));
    expect(r.byStage, m(e['byStage']));
    expect(r.stepsByKey, m(e['stepsByKey']));
    final ec = (e['contractors'] as List).map(m).toList();
    expect(r.contractors.length, ec.length);
    for (var i = 0; i < ec.length; i++) {
      expect(r.contractors[i].contractor, ec[i]['contractor']);
      expect(r.contractors[i].open, ec[i]['open']);
      expect(r.contractors[i].completedInPeriod, ec[i]['completedInPeriod']);
      expect(r.contractors[i].lateStarts, ec[i]['lateStarts']);
      expect(r.contractors[i].avgDaysToFinish, ec[i]['avgDaysToFinish']);
      expect(r.contractors[i].finished, ec[i]['finished']);
      expect(r.contractors[i].finishDaysTotal, ec[i]['finishDaysTotal']);
    }
    m(e['quantities']).forEach((k, v) => expect(r.quantities[k], v, reason: k));
    final cl = (e['completedList'] as List).map(m).toList();
    expect(r.completedList.map((c) => [c.id, c.days]).toList(), cl.map((c) => [c['id'], c['days']]).toList());
    final dl = (e['delays'] as List).map(m).toList();
    expect(r.delays.map((x) => [x.id, x.code, x.days, x.severity]).toList(), dl.map((x) => [x['id'], x['code'], x['days'], x['severity']]).toList());
    expect(d.trend.length, e['trendLength']);
    for (final p in (e['trendPoints'] as List).map(m)) {
      final t = d.trend.firstWhere((x) => x.date == p['date']);
      expect([t.received, t.completed], [p['received'], p['completed']], reason: p['date'] as String);
    }
  });

  test('monthly report', () {
    final e = m(fx['monthly']);
    final r = ins.report(orders, e['from'] as String, e['to'] as String, today: e['today'] as String);
    expect(r.received, e['received']);
    expect(r.stepsCompleted, e['stepsCompleted']);
    expect(r.completed, e['completed']);
    m(e['quantities']).forEach((k, v) => expect(r.quantities[k], v, reason: k));
    expect(r.series.length, 31);
  });

  test('week and month ranges', () {
    for (final r in (fx['ranges'] as List).map(m)) {
      if (r['week'] != null) {
        final w = Insights.weekRange(r['date'] as String);
        expect([w.from, w.to], [r['week']['from'], r['week']['to']], reason: r['date'] as String);
      }
      if (r['month'] != null) {
        final mo = Insights.monthRange(r['date'] as String);
        expect([mo.from, mo.to], [r['month']['from'], r['month']['to']], reason: r['date'] as String);
      }
    }
  });

  test('Arabic text normalisation', () {
    expect(Insights.normalizeText('أولوية'), Insights.normalizeText('اولويه'));
    expect(Insights.normalizeText('مستشفى'), Insights.normalizeText('مستشفي'));
    expect(Insights.normalizeText('٤٤١٧'), '4417');
    expect(Insights.normalizeText('۴۴۱۷'), '4417');
    expect(Insights.normalizeText('مُحَمَّد'), 'محمد');
  });

  test('snapshot: the order as it stood on a past day', () {
    final o = OrderInput.fromJson({
      'id': 'S', 'type': '402', 'category': 'extension', 'woNumber': '441799001', 'receivedDate': '2026-09-20',
      'permits': [
        {'number': 'P1', 'appliedDate': '2026-09-22', 'startDate': '2026-09-24', 'endDate': '2026-10-24'},
        {'number': 'P2', 'appliedDate': '2026-10-20', 'startDate': '2026-10-25', 'endDate': '2026-11-25'},
      ],
      'steps': {
        'kashfeya': {'done': '2026-09-21'}, 'tasreeh_applied': {'done': '2026-09-22'},
        'excavation': {'done': '2026-10-02'}, 'warning_tape': {'na': true, 'reason': 'duct'},
      },
      'status': {'state': 'open', 'holdPeriods': [{'from': '2026-09-26', 'to': '2026-10-01', 'reason': 'No material'}]},
      'lastChangeDate': '2026-10-02',
    });
    expect(Insights.snapshot(o, '2026-09-19'), isNull);
    final s = Insights.snapshot(o, '2026-09-28')!;
    expect(s.steps.keys.toList(), ['kashfeya', 'tasreeh_applied', 'warning_tape']);
    expect(s.permits.map((p) => p.number).toList(), ['P1']);
    expect(s.state, 'on_hold');
    expect(s.holdPeriods.single.to, isNull);
    expect(s.lastChangeDate, '2026-09-22');
    final s2 = Insights.snapshot(o, '2026-10-05')!;
    expect(s2.state, 'open');
    expect(s2.lastChangeDate, '2026-10-02');
  });

  group('small cases', () {
    for (final c in (fx['extraCases'] as List).map(m)) {
      test(c['name'] as String, () {
        final os = (c['orders'] as List).map((e) => OrderInput.fromJson(m(e))).toList();
        final day = c['today'] as String;
        if (c['pipelineBuckets'] != null) expect(ins.pipeline(os, day).buckets, m(c['pipelineBuckets']));
        for (final f in ((c['filters'] as List?) ?? const []).map(m)) {
          expect(ins.filterOrders(os, day, FilterCriteria.fromJson(m(f['criteria']))), (f['ids'] as List).cast<String>());
        }
        if (c['report'] != null) {
          final e = m(c['report']);
          final r = ins.report(os, e['from'] as String, e['to'] as String, today: e['today'] as String);
          expect(r.completed, e['completed']);
          expect(r.completedList.map((x) => [x.id, x.days]).toList(), e['completedList']);
          for (final p in (e['completedOn'] as List)) {
            expect(r.series.firstWhere((x) => x.date == p[0]).completed, p[1], reason: p[0] as String);
          }
          expect(r.contractors.map((x) => [x.contractor, x.completedInPeriod, x.finished, x.avgDaysToFinish]).toList(), e['contractors']);
        }
        for (final g in ((c['followUpGroups'] as List?) ?? const [])) {
          final con = ins.followUp(os, day).firstWhere((x) => x.contractor == g[0]);
          final grp = con.groups[g[1]]!;
          expect(grp.items.map((i) => i.steps).toList(), [g[2]]);
          expect(grp.items.first.daysWaiting, g[3]);
        }
      });
    }
  });
}
