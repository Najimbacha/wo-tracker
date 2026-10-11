// Runs the shared action cases (test/fixtures/actions.json) against the Dart actions.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/actions.dart';
import 'package:wo_tracker/domain/order_input.dart';
import 'package:wo_tracker/domain/rules_engine.dart';

void main() {
  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> m(Object? o) => Map<String, dynamic>.from(o as Map);
  final rules = json('assets/rules/rules.json');
  final fx = json('test/fixtures/actions.json');
  final today = fx['today'] as String;
  final engine = RulesEngine(rules);
  final actions = Actions(engine);
  final base = m(fx['orders']);

  Map<String, dynamic> rawOrder(String name, Object? patch) {
    final o = jsonDecode(jsonEncode(base[name])) as Map<String, dynamic>;
    if (patch == null) return o;
    final p = jsonDecode(jsonEncode(patch)) as Map<String, dynamic>;
    final steps = p.remove('steps');
    o.addAll(p);
    if (steps != null) o['steps'] = {...m(o['steps'] ?? {}), ...m(steps)};
    return o;
  }

  OrderInput? build(Object? name, [Object? patch]) => name == null ? null : OrderInput.fromJson(rawOrder(name as String, patch));
  List<OrderInput> all() => base.keys.map((k) => build(k)!).toList();
  List<String> codes(List<Reason> rs) => rs.map((r) => r.code).toList();
  Map<String, Object?> stepsJson(OrderInput o) => o.steps.map((k, v) => MapEntry(k, v.toJson()));

  for (final c in (fx['cases'] as List).map(m)) {
    test('${c['action']}: ${c['name']}', () {
      final a = m(c['args'] ?? {});
      final e = m(c['expect']);
      final o = c['order'] == null ? null : build(c['order'], c['patch']);
      ActionResult? r;
      switch (c['action']) {
        case 'markDone':
          r = actions.markDone(o!, a['step'] as String, a['date'] as String, today);
        case 'markNA':
          r = actions.markNA(o!, a['step'] as String, a['reason'] as String?, today);
        case 'clearStep':
          r = actions.clearStep(o!, a['step'] as String);
        case 'clearPreview':
          r = actions.clearPreview(o!, a['step'] as String);
        case 'putOnHold':
          r = actions.putOnHold(o!, a['from'] as String, a['reason'] as String?, today, reviewDate: a['review'] as String?);
        case 'resume':
          r = actions.resume(o!, a['date'] as String, today);
        case 'cancel':
          r = actions.cancel(o!, a['reason'] as String?, today);
        case 'merge':
          r = actions.merge(o!, build(c['target'], c['targetPatch']), a['reason'] as String?, a['carry'] as bool, today);
        case 'reopen':
          r = actions.reopen(o!);
        case 'bulkMarkDone':
          final b = actions.bulkMarkDone((c['orders'] as List).map((n) => build(n)!).toList(), a['stepKey'] as String, a['date'] as String, today);
          expect(b.updated.map((u) => {'id': u.id, 'steps': u.steps}).toList(), e['updated']);
          expect(b.skipped.map((s) => {'id': s.id, 'errors': codes(s.errors)}).toList(), e['skipped']);
          return;
        case 'editImpact':
          final after = OrderInput.fromJson({...rawOrder(c['order'] as String, c['patch']), ...m(a['after'])});
          expect(actions.editImpact(o!, after), e['impact']);
          return;
        case 'formSpec':
          final spec = actions.formSpec(OrderInput.fromJson(m(a['draft'])));
          m(e['spec']).forEach((k, v) => expect(spec[k], v, reason: 'spec.$k'));
          return;
        case 'normalizeDraft':
          final d = Actions.normalizeDraft(OrderInput.fromJson(m(a['draft'])), rules: rules);
          final ed = m(e['draft']);
          expect(d.woNumber, ed['woNumber']);
          expect(d.permits.map((p) => p.number).toList(), ((ed['permits'] as List?) ?? const []).map((p) => (p as Map)['number']).toList());
          expect(d.meters.map((x) => [x.number, x.oldNumber]).toList(), ((ed['meters'] as List?) ?? const []).map((x) => [(x as Map)['number'], x['oldNumber']]).toList());
          expect(d.needsExcavation, ed['needsExcavation'] ?? false);
          return;
        case 'validateDraft':
          final errs = actions.validateDraft(OrderInput.fromJson(m(a['draft'])), all(), today);
          expect(codes(errs), e['errors']);
          final data = (e['errorData'] as List?) ?? const [];
          for (var i = 0; i < data.length; i++) {
            m(data[i]).forEach((k, v) => expect(errs[i][k], v, reason: 'error[$i].$k'));
          }
          return;
        default:
          fail('unknown action ${c['action']}');
      }

      final res = r!;
      if (e.containsKey('ok')) expect(res.ok, e['ok'], reason: codes(res.errors).join(', '));
      if (e.containsKey('errors')) expect(codes(res.errors), e['errors']);
      final data = (e['errorData'] as List?) ?? const [];
      for (var i = 0; i < data.length; i++) {
        m(data[i]).forEach((k, v) => expect(res.errors[i][k], v, reason: 'error[$i].$k'));
      }
      final out = res.order;
      if (e.containsKey('steps')) expect(stepsJson(out!), e['steps']);
      if (e.containsKey('lastChangeDate')) expect(out!.lastChangeDate, e['lastChangeDate']);
      if (e.containsKey('completed')) expect(res.completed, e['completed']);
      if (e.containsKey('state')) expect(out!.state, e['state']);
      if (e.containsKey('reason')) expect(out!.stateReason, e['reason']);
      if (e.containsKey('mergedInto')) expect(out!.mergedInto, e['mergedInto']);
      if (e.containsKey('holdPeriods')) expect(out!.holdPeriods.map((h) => h.toJson()).toList(), e['holdPeriods']);
      if (e.containsKey('status')) {
        final s = m(e['status']);
        expect(out!.state, s['state']);
        expect(out.stateReason, isNull);
        expect(out.mergedInto, isNull);
        expect(out.holdPeriods.map((h) => h.toJson()).toList(), s['holdPeriods']);
      }
      if (e.containsKey('cleared')) expect(res.cleared, e['cleared']);
      if (e.containsKey('alsoClears')) expect(res.alsoClears, e['alsoClears']);
      if (e.containsKey('carried')) expect(res.carried, e['carried']);
      if (e.containsKey('notCarried')) expect(res.notCarried, e['notCarried']);
      if (e.containsKey('targetSteps')) expect(stepsJson(res.target!), e['targetSteps']);
      if (e.containsKey('targetLastChangeDate')) expect(res.target!.lastChangeDate, e['targetLastChangeDate']);
    });
  }
}
