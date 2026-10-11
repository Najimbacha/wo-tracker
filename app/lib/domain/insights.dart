// Screen and report logic. Mirrors tools/rules-check/insights.mjs exactly;
// both are checked against test/fixtures/insights.json.

import 'order_input.dart';
import 'rules_engine.dart';

const _active = {'open', 'on_hold'};
const unassignedContractor = '(not assigned)';

int _sevRank(String? s) => s == 'critical' ? 2 : (s == 'warning' ? 1 : 0);

String? _maxSeverity(List<Alert> alerts) {
  String? m;
  for (final a in alerts) {
    if (m == null || _sevRank(a.severity) > _sevRank(m)) m = a.severity;
  }
  return m;
}

int _cmp(String? a, String? b) => (a ?? '').compareTo(b ?? '');

String? _firstPermitStart(OrderInput o) {
  final s = o.permits.where((p) => p.startDate != null).map((p) => toDay(p.startDate!)).toList();
  if (s.isEmpty) return null;
  s.sort();
  return fromDay(s.first);
}

bool _closed(StepState s) => s.state == 'done' || s.state == 'na';

class Evaluated {
  final OrderInput order;
  final Evaluation ev;
  const Evaluated(this.order, this.ev);
}

class Insights {
  final RulesEngine engine;
  Insights(this.engine);

  Map<String, dynamic> get rules => engine.rules;

  List<Evaluated> evaluateAll(List<OrderInput> orders, String today, {Map<String, int>? alertSettings}) => [
        for (final o in orders)
          if (!o.deleted) Evaluated(o, engine.evaluate(o, today, alertSettings: alertSettings)),
      ];

  String? waitingSince(OrderInput o, Evaluation ev, String stepId) {
    final s = ev.steps.firstWhere((x) => x.id == stepId);
    final dates = <int>[];
    for (final d in s.step.deps) {
      for (final x in ev.steps) {
        if (x.id == d && x.doneDate != null) dates.add(toDay(x.doneDate!));
      }
    }
    if ((s.step.key == 'excavation' || s.step.key == 'poles') && o.category != 'emergency') {
      final start = _firstPermitStart(o);
      if (start != null) dates.add(toDay(start));
    }
    if (dates.isNotEmpty) return fromDay(dates.reduce((a, b) => a > b ? a : b));
    return o.receivedDate;
  }

  int daysWaiting(OrderInput o, Evaluation ev, String stepId, String today) {
    final since = waitingSince(o, ev, stepId);
    if (since == null || toDay(since) > toDay(today)) return 0;
    return activeDays(since, today, o.holdPeriods);
  }

  // ---------------- Pipeline ----------------
  PipelineResult pipeline(List<OrderInput> orders, String today, {Map<String, int>? alertSettings}) {
    final all = evaluateAll(orders, today, alertSettings: alertSettings).where((x) => _active.contains(x.ev.status)).toList();
    final steps = <String, StepCount>{for (final k in (rules['steps'] as Map).keys) k as String: StepCount()};
    final b = <String, int>{
      'kashfeyaNotDone': 0,
      'tasreehNotApplied': 0,
      'appliedNoDates': 0,
      'startsInFuture': 0,
      'expiredWorkOpen': 0,
      'lateStart': 0,
    };
    for (final x in all) {
      final ev = x.ev, o = x.order;
      final keys = ev.steps.map((s) => s.step.key).toSet();
      for (final key in keys) {
        final inst = ev.steps.where((s) => s.step.key == key).toList();
        if (inst.any((s) => s.state == 'ready')) steps[key]!.ready++;
        if (inst.any((s) => s.state == 'ready' || s.state == 'locked')) steps[key]!.total++;
      }
      StepState? get(String k) {
        for (final s in ev.steps) {
          if (s.step.key == k) return s;
        }
        return null;
      }

      final k = get('kashfeya');
      if (k != null && !_closed(k)) b['kashfeyaNotDone'] = b['kashfeyaNotDone']! + 1;
      final t = get('tasreeh_applied');
      if (t != null) {
        final tClosed = _closed(t);
        if (!tClosed) b['tasreehNotApplied'] = b['tasreehNotApplied']! + 1;
        final start = _firstPermitStart(o);
        // Not applicable means no tasreeh is needed, so it is not waiting for dates.
        if (t.state == 'done' && start == null) b['appliedNoDates'] = b['appliedNoDates']! + 1;
        StepState? gated;
        for (final s in ev.steps) {
          if (s.step.key == 'excavation' || s.step.key == 'poles') {
            gated = s;
            break;
          }
        }
        if (start != null && toDay(start) > toDay(today) && gated != null && !_closed(gated)) {
          b['startsInFuture'] = b['startsInFuture']! + 1;
        }
      }
      if (ev.alerts.any((a) => a.code == 'no_active_tasreeh')) b['expiredWorkOpen'] = b['expiredWorkOpen']! + 1;
      if (ev.alerts.any((a) => a.code == 'late_start')) b['lateStart'] = b['lateStart']! + 1;
    }
    return PipelineResult(all.length, steps, b);
  }

  List<DayStarts> startsByDay(List<OrderInput> orders, String today, {int days = 7, Map<String, int>? alertSettings}) {
    final all = evaluateAll(orders, today, alertSettings: alertSettings).where((x) => _active.contains(x.ev.status));
    final t0 = toDay(today);
    final out = [for (var i = 0; i < days; i++) DayStarts(fromDay(t0 + i))];
    for (final x in all) {
      StepState? gated;
      for (final s in x.ev.steps) {
        if (s.step.key == 'excavation' || s.step.key == 'poles') {
          gated = s;
          break;
        }
      }
      if (gated == null || _closed(gated)) continue;
      final start = _firstPermitStart(x.order);
      if (start == null) continue;
      final i = toDay(start) - t0;
      if (i >= 0 && i < days) out[i].orders.add(x.order.id ?? '');
    }
    return out;
  }

  // ---------------- Board ----------------
  BoardCard _card(OrderInput o, Evaluation ev, String today) {
    String? nextId = ev.next.isNotEmpty ? ev.next.first : null;
    if (nextId == null) {
      for (final s in ev.steps) {
        if (!_closed(s)) {
          nextId = s.id;
          break;
        }
      }
    }
    return BoardCard(
      id: o.id,
      woNumber: o.woNumber,
      type: o.type,
      district: o.district,
      contractor: o.contractor,
      next: nextId,
      nextKey: nextId == null ? null : ev.steps.firstWhere((s) => s.id == nextId).step.key,
      daysWaiting: nextId == null ? 0 : daysWaiting(o, ev, nextId, today),
      startsOn: ev.stage == 'starting' ? _firstPermitStart(o) : null,
      severity: _maxSeverity(ev.alerts),
      onHold: ev.status == 'on_hold',
    );
  }

  static int _cardSort(BoardCard a, BoardCard b) {
    final s = _sevRank(b.severity) - _sevRank(a.severity);
    if (s != 0) return s;
    final d = b.daysWaiting - a.daysWaiting;
    if (d != 0) return d;
    return _cmp(a.woNumber, b.woNumber);
  }

  List<BoardColumn> board(List<OrderInput> orders, String today, {Map<String, int>? alertSettings}) {
    final all = evaluateAll(orders, today, alertSettings: alertSettings).where((x) => _active.contains(x.ev.status)).toList();
    return [
      for (final st in (rules['stages'] as List).cast<Map>())
        BoardColumn(
          st['key'] as String,
          all.where((x) => x.ev.stage == st['key']).map((x) => _card(x.order, x.ev, today)).toList()..sort(_cardSort),
        ),
    ];
  }

  // ---------------- Follow-up ----------------
  static const actionGroups = <String, List<String>>{
    'start_field_work': ['excavation', 'poles'],
    'close_trench': ['concrete', 'compaction', 'sub_base'],
    'surface': ['asphalt', 'asphalt_stage_1', 'asphalt_stage_2', 'tiles'],
    'cable_tape': ['cable_installed', 'warning_tape'],
    'overhead': ['stringing', 'stay_earthing', 'line_energized'],
    'transformer': ['foundation', 'transformer_installed', 'earthing', 'transformer_energized'],
    'meter_closeout': [
      'meter_installed', 'breaker_meter_changed', 'meter_relocated', 'meter_on', 'form_190', 'form_200', 'certificate', 'documents_submitted'
    ],
    'paperwork': ['kashfeya', 'tasreeh_applied'],
    'upcoming': [],
  };

  static String _groupOf(String key) {
    for (final e in actionGroups.entries) {
      if (e.value.contains(key)) return e.key;
    }
    throw StateError('No follow-up group for $key');
  }

  static int _groupOrder(String g) => actionGroups.keys.toList().indexOf(g);

  List<ContractorFollowUp> followUp(List<OrderInput> orders, String today, {Map<String, int>? alertSettings}) {
    final all = evaluateAll(orders, today, alertSettings: alertSettings).where((x) => x.ev.status == 'open');
    final byCon = <String, ContractorFollowUp>{};
    for (final x in all) {
      final o = x.order, ev = x.ev;
      final con = o.contractor ?? unassignedContractor;
      final c = byCon.putIfAbsent(con, () => ContractorFollowUp(con));
      c.orders++;
      if (ev.alerts.isNotEmpty) c.late++;
      final sev = _maxSeverity(ev.alerts);
      final ready = ev.steps.where((s) => s.state == 'ready').toList();
      final perGroup = <String, List<String>>{};
      if (ready.isNotEmpty) {
        for (final s in ready) {
          perGroup.putIfAbsent(_groupOf(s.step.key), () => []).add(s.id);
        }
      } else {
        perGroup['upcoming'] = [];
      }
      perGroup.forEach((g, stepIds) {
        final grp = c.groups.putIfAbsent(g, () => FollowUpGroup(g));
        var days = 0;
        for (final id in stepIds) {
          final d = daysWaiting(o, ev, id, today);
          if (d > days) days = d;
        }
        grp.items.add(FollowUpItem(
          id: o.id,
          woNumber: o.woNumber,
          steps: stepIds,
          daysWaiting: days,
          severity: sev,
          startsOn: g == 'upcoming' ? _firstPermitStart(o) : null,
        ));
        if (_sevRank(sev) > _sevRank(grp.severity)) grp.severity = sev;
      });
    }
    final out = byCon.values.toList();
    for (final c in out) {
      for (final g in c.groups.values) {
        g.items.sort((a, b) {
          final s = _sevRank(b.severity) - _sevRank(a.severity);
          if (s != 0) return s;
          final d = b.daysWaiting - a.daysWaiting;
          if (d != 0) return d;
          return _cmp(a.woNumber, b.woNumber);
        });
      }
    }
    out.sort((a, b) {
      final ua = a.contractor == unassignedContractor ? 1 : 0, ub = b.contractor == unassignedContractor ? 1 : 0;
      if (ua != ub) return ua - ub;
      if (a.orders != b.orders) return b.orders - a.orders;
      return _cmp(a.contractor, b.contractor);
    });
    return out;
  }

  // ---------------- Search ----------------
  static String normalizeText(String? s) {
    final buf = StringBuffer();
    for (final r in (s ?? '').toLowerCase().runes) {
      if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || r == 0x0640) continue;
      if (r == 0x0622 || r == 0x0623 || r == 0x0625 || r == 0x0671) {
        buf.writeCharCode(0x0627);
      } else if (r == 0x0649) {
        buf.writeCharCode(0x064A);
      } else if (r == 0x0629) {
        buf.writeCharCode(0x0647);
      } else if (r >= 0x0660 && r <= 0x0669) {
        buf.write(r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        buf.write(r - 0x06F0);
      } else {
        buf.writeCharCode(r);
      }
    }
    return buf.toString().trim();
  }

  static String _compact(String s) => s.replaceAll(RegExp(r'[\s\-/_.]'), '');
  static const _statusRank = {'open': 0, 'on_hold': 0, 'completed': 1, 'cancelled': 2, 'merged': 2};

  List<SearchHit> search(List<OrderInput> orders, String query, String today) {
    final q = normalizeText(query);
    if (q.isEmpty) return [];
    final qc = _compact(q);
    final results = <SearchHit>[];
    for (final x in evaluateAll(orders, today)) {
      final o = x.order;
      final fields = <List<String?>>[
        ['workOrder', o.woNumber],
        for (final p in o.permits) ['tasreeh', p.number],
        for (final m in o.meters) ...[
          ['meter', m.number],
          ['meter', m.oldNumber],
        ],
        ['network', o.networkRef],
        ['place', o.district],
        ['place', o.street],
        ['contractor', o.contractor],
        ['note', o.notes],
      ];
      final seen = <String>{};
      for (final f in fields) {
        final kind = f[0]!, raw = f[1];
        if (raw == null || raw.isEmpty) continue;
        final v = normalizeText(raw);
        var at = v.indexOf(q);
        if (at < 0 && qc.length >= 3) at = _compact(v).indexOf(qc);
        if (at < 0) continue;
        if (!seen.add('$kind|$raw')) continue;
        results.add(SearchHit(o.id, o.woNumber, kind, raw, at == 0, x.ev.status));
      }
    }
    results.sort((a, b) {
      final p = (b.prefix ? 1 : 0) - (a.prefix ? 1 : 0);
      if (p != 0) return p;
      final s = _statusRank[a.status]! - _statusRank[b.status]!;
      if (s != 0) return s;
      final w = _cmp(a.woNumber, b.woNumber);
      if (w != 0) return w;
      final k = _cmp(a.kind, b.kind);
      if (k != 0) return k;
      return _cmp(a.value, b.value);
    });
    return results;
  }

  // ---------------- Filters ----------------
  static String _segKind(Segment s) => s.base == 'soil' ? 'soil' : (s.width >= 80 ? 'asphalt_80' : 'asphalt_40');

  String _tasreehState(OrderInput o, String today, Evaluation ev) {
    if (!ev.steps.any((s) => s.step.package == 'tasreeh')) return 'not_needed';
    if (ev.steps.any((s) => s.step.key == 'tasreeh_applied' && s.state == 'na')) return 'not_needed';
    final permits = o.permits.where((p) => p.startDate != null && p.endDate != null).toList();
    if (permits.isEmpty) return 'none';
    final t = toDay(today);
    final cur = engine.currentPermit(o, today);
    if (cur != null) return ev.alerts.any((a) => a.code == 'next_tasreeh_needed') ? 'ending' : 'active';
    if (permits.any((p) => toDay(p.startDate!) > t)) return 'future';
    return 'expired';
  }

  static bool _stepMatches(Evaluation ev, StepCondition c) {
    final inst = ev.steps.where((s) => s.step.key == c.step).toList();
    if (inst.isEmpty) return false;
    switch (c.state) {
      case 'ready':
        return inst.any((s) => s.state == 'ready');
      case 'not_done':
        return inst.any((s) => !_closed(s));
      case 'done':
        if (!inst.every(_closed)) return false;
        if (c.from == null && c.to == null) return true;
        final dates = inst.where((s) => s.doneDate != null).map((s) => toDay(s.doneDate!)).toList();
        if (dates.isEmpty) return false;
        final last = dates.reduce((a, b) => a > b ? a : b);
        return (c.from == null || last >= toDay(c.from!)) && (c.to == null || last <= toDay(c.to!));
      default:
        throw ArgumentError('Unknown step state ${c.state}');
    }
  }

  static bool _quick(String q, OrderInput o, Evaluation ev, String today) {
    switch (q) {
      case 'needs_attention':
        return ev.alerts.isNotEmpty;
      case 'late_start':
        return ev.alerts.any((a) => a.code == 'late_start');
      case 'tasreeh_ending':
        return ev.alerts.any((a) => a.code == 'next_tasreeh_needed');
      case 'expired':
        return ev.alerts.any((a) => a.code == 'no_active_tasreeh');
      case 'emergency':
        return o.category == 'emergency';
      case 'on_hold':
        return ev.status == 'on_hold';
      case 'received_today':
        return o.receivedDate == today;
      default:
        throw ArgumentError('Unknown quick filter $q');
    }
  }

  List<String?> filterOrders(List<OrderInput> orders, String today, FilterCriteria c, {Map<String, int>? alertSettings}) {
    final pool = c.includeDeleted
        ? [for (final o in orders) Evaluated(o, engine.evaluate(o, today, alertSettings: alertSettings))]
        : evaluateAll(orders, today, alertSettings: alertSettings);
    bool inList(List<String>? list, String? v) => list == null || list.isEmpty || list.contains(v);
    final out = pool.where((x) {
      final o = x.order, ev = x.ev;
      if (!inList(c.status, ev.status)) return false;
      if (!inList(c.categories, o.category)) return false;
      if (!inList(c.types, o.type)) return false;
      if (c.contractors != null && c.contractors!.isNotEmpty && !c.contractors!.contains(o.contractor ?? unassignedContractor)) return false;
      if (!inList(c.districts, o.district)) return false;
      if (c.voltages != null && c.voltages!.isNotEmpty && !o.cableRuns.any((r) => c.voltages!.contains(r.voltage))) return false;
      if (c.cableSizes != null && c.cableSizes!.isNotEmpty && !o.cableRuns.any((r) => c.cableSizes!.contains(r.sizeMm2))) return false;
      if (c.surfaces != null && c.surfaces!.isNotEmpty) {
        final kinds = o.segments.map(_segKind).toSet();
        if (o.segments.any((s) => s.tiled)) kinds.add('tiled');
        if (!engine.orderPackages(o).contains('civil')) kinds.add('no_digging');
        if (!c.surfaces!.any(kinds.contains)) return false;
      }
      if (c.receivedFrom != null || c.receivedTo != null) {
        if (o.receivedDate == null) return false;
        if (c.receivedFrom != null && toDay(o.receivedDate!) < toDay(c.receivedFrom!)) return false;
        if (c.receivedTo != null && toDay(o.receivedDate!) > toDay(c.receivedTo!)) return false;
      }
      if (c.tasreeh != null && c.tasreeh!.isNotEmpty && !c.tasreeh!.contains(_tasreehState(o, today, ev))) return false;
      for (final cond in c.steps) {
        if (!_stepMatches(ev, cond)) return false;
      }
      for (final q in c.quick) {
        if (!_quick(q, o, ev, today)) return false;
      }
      return true;
    }).toList();
    out.sort((a, b) {
      final d = toDay(b.order.receivedDate ?? '1970-01-01') - toDay(a.order.receivedDate ?? '1970-01-01');
      if (d != 0) return d;
      return _cmp(a.order.woNumber, b.order.woNumber);
    });
    return out.map((x) => x.order.id).toList();
  }

  // ---------------- Reports ----------------
  static DateRange weekRange(String date) {
    final d = toDay(date);
    final dow = ((d + 4) % 7 + 7) % 7; // 0 = Sunday ... 6 = Saturday
    final sinceSat = (dow + 1) % 7;
    return DateRange(fromDay(d - sinceSat), fromDay(d - sinceSat + 6));
  }

  static DateRange monthRange(String date) {
    final parts = date.split('-');
    final y = int.parse(parts[0]), m = int.parse(parts[1]);
    final last = DateTime.utc(y, m + 1, 0).day;
    final mm = m.toString().padLeft(2, '0');
    return DateRange('$y-$mm-01', '$y-$mm-${last.toString().padLeft(2, '0')}');
  }

  static bool _inRange(String? date, String from, String to) =>
      date != null && toDay(date) >= toDay(from) && toDay(date) <= toDay(to);

  /// The day an order was completed: when its documents were submitted to SEC, or, if that
  /// step was marked Not applicable, the latest date any of its steps was done.
  static String? completedOn(Evaluation ev) {
    if (ev.status != 'completed') return null;
    for (final s in ev.steps) {
      if (s.step.key == 'documents_submitted' && s.doneDate != null) return s.doneDate;
    }
    final dates = ev.steps.where((s) => s.doneDate != null).map((s) => toDay(s.doneDate!)).toList();
    return dates.isEmpty ? null : fromDay(dates.reduce((a, b) => a > b ? a : b));
  }

  static String? _docsDone(Evaluation ev) => completedOn(ev);

  /// The order as it stood at the end of [asOf] (see snapshot in insights.mjs), or null
  /// if it had not been received yet. Reports for past periods use this.
  static OrderInput? snapshot(OrderInput o, String asOf) {
    final t = toDay(asOf);
    if (o.receivedDate != null && toDay(o.receivedDate!) > t) return null;
    final steps = Map<String, StepRecord>.from(o.steps)..removeWhere((_, r) => r.done != null && toDay(r.done!) > t);
    final permits = o.permits.where((p) => !(p.appliedDate != null && toDay(p.appliedDate!) > t)).toList();
    final holds = o.holdPeriods
        .where((h) => toDay(h.from) <= t)
        .map((h) => h.to != null && toDay(h.to!) > t ? h.reopened() : h)
        .toList();
    var state = o.state;
    var base = o;
    // Cancelled or merged only from its own date (orders saved without a date: throughout).
    if ((state == 'cancelled' || state == 'merged') && o.stateDate != null && toDay(o.stateDate!) > t) {
      state = 'open';
      base = o.copyWith(stateReason: null, mergedInto: null, stateDate: null);
    }
    if (state == 'open' || state == 'on_hold') state = holds.any((h) => h.to == null) ? 'on_hold' : 'open';
    var last = o.lastChangeDate;
    if (last != null && toDay(last) > t) {
      final dates = [o.receivedDate, ...steps.values.map((r) => r.done), ...permits.map((p) => p.appliedDate)].whereType<String>().map(toDay).toList();
      last = dates.isEmpty ? null : fromDay(dates.reduce((a, b) => a > b ? a : b));
    }
    return base.copyWith(steps: steps, permits: permits, holdPeriods: holds, state: state, lastChangeDate: last);
  }

  ReportResult report(List<OrderInput> orders, String from, String to, {String? today, Map<String, int>? alertSettings}) {
    final now = today ?? to;
    final all = evaluateAll(orders.map((o) => snapshot(o, now)).whereType<OrderInput>().toList(), now, alertSettings: alertSettings);
    final active = all.where((x) => _active.contains(x.ev.status)).toList();

    final received = all.where((x) => _inRange(x.order.receivedDate, from, to)).length;
    var stepsCompleted = 0;
    final touched = <String?>{};
    final stepsByKey = <String, int>{};
    for (final x in all) {
      for (final s in x.ev.steps) {
        if (s.state == 'done' && _inRange(s.doneDate, from, to)) {
          stepsCompleted++;
          touched.add(x.order.id);
          stepsByKey[s.step.key] = (stepsByKey[s.step.key] ?? 0) + 1;
        }
      }
    }
    final completed = all.where((x) => x.ev.status == 'completed' && _inRange(_docsDone(x.ev), from, to)).toList();

    final attentionByCode = <String, int>{};
    for (final x in active) {
      for (final code in x.ev.alerts.map((a) => a.code).toSet()) {
        attentionByCode[code] = (attentionByCode[code] ?? 0) + 1;
      }
    }
    final byStage = <String, int>{for (final st in (rules['stages'] as List).cast<Map>()) st['key'] as String: 0};
    for (final x in active) {
      if (x.ev.stage != null) byStage[x.ev.stage!] = byStage[x.ev.stage!]! + 1;
    }

    final cons = <String, _ConAcc>{};
    for (final x in all) {
      final c = cons.putIfAbsent(x.order.contractor ?? unassignedContractor, () => _ConAcc(x.order.contractor ?? unassignedContractor));
      if (_active.contains(x.ev.status)) c.open++;
      if (x.ev.status == 'open' && x.ev.alerts.any((a) => a.code == 'late_start')) c.lateStarts++;
      if (x.ev.status == 'completed') {
        final d = _docsDone(x.ev);
        if (_inRange(d, from, to)) c.completedInPeriod++;
        if (d != null && x.order.receivedDate != null) c.finishDays.add(activeDays(x.order.receivedDate!, d, x.order.holdPeriods));
      }
    }
    final contractors = cons.values
        .where((c) => c.open > 0 || c.completedInPeriod > 0 || c.lateStarts > 0)
        .map((c) => ContractorStats(
              c.name,
              c.open,
              c.completedInPeriod,
              c.lateStarts,
              c.finishDays.isEmpty ? null : (c.finishDays.reduce((a, b) => a + b) / c.finishDays.length).round(),
              finished: c.finishDays.length,
              finishDaysTotal: c.finishDays.fold(0, (a, b) => a + b),
            ))
        .toList()
      ..sort((a, b) {
        final ua = a.contractor == unassignedContractor ? 1 : 0, ub = b.contractor == unassignedContractor ? 1 : 0;
        if (ua != ub) return ua - ub;
        if (a.open != b.open) return b.open - a.open;
        return _cmp(a.contractor, b.contractor);
      });

    final q = <String, double>{'cableLV': 0, 'cableMV': 0, 'asphalt40': 0, 'asphalt80': 0, 'soil': 0, 'tiles': 0};
    for (final x in all) {
      bool done(String id) {
        for (final s in x.ev.steps) {
          if (s.id == id) return s.state == 'done' && _inRange(s.doneDate, from, to);
        }
        return false;
      }

      if (done('cable_installed')) {
        for (final r in x.order.cableRuns) {
          final k = r.voltage == 'MV' ? 'cableMV' : 'cableLV';
          q[k] = q[k]! + r.lengthM;
        }
      }
      for (final seg in x.order.segments) {
        if (seg.base == 'soil' && done('compaction@${seg.id}')) q['soil'] = q['soil']! + seg.lengthM;
        if (seg.base == 'asphalt' && seg.width < 80 && done('asphalt@${seg.id}')) q['asphalt40'] = q['asphalt40']! + seg.lengthM;
        if (seg.base == 'asphalt' && seg.width >= 80 && done('asphalt_stage_2@${seg.id}')) q['asphalt80'] = q['asphalt80']! + seg.lengthM;
        if (seg.tiled && done('tiles@${seg.id}')) q['tiles'] = q['tiles']! + seg.lengthM;
      }
    }

    final delays = <DelayRow>[];
    for (final x in active) {
      if (x.ev.status != 'open' || x.ev.alerts.isEmpty) continue;
      final sorted = [...x.ev.alerts]..sort((a, b) {
          final s = _sevRank(b.severity) - _sevRank(a.severity);
          if (s != 0) return s;
          return ((b.data['days'] as int?) ?? 0) - ((a.data['days'] as int?) ?? 0);
        });
      final top = sorted.first;
      delays.add(DelayRow(x.order.id, x.order.woNumber, x.order.type, x.order.district, x.order.contractor, top.code,
          top.data['days'] as int?, top.severity));
    }
    delays.sort((a, b) {
      final s = _sevRank(b.severity) - _sevRank(a.severity);
      if (s != 0) return s;
      final d = (b.days ?? 0) - (a.days ?? 0);
      if (d != 0) return d;
      return _cmp(a.woNumber, b.woNumber);
    });

    final series = <SeriesPoint>[];
    for (var d = toDay(from); d <= toDay(to); d++) {
      final day = fromDay(d);
      series.add(SeriesPoint(
        day,
        all.where((x) => x.order.receivedDate == day).length,
        all.where((x) => x.ev.status == 'completed' && _docsDone(x.ev) == day).length,
      ));
    }

    final completedList = completed
        .map((x) => CompletedRow(x.order.id, x.order.woNumber, x.order.type, activeDays(x.order.receivedDate!, _docsDone(x.ev)!, x.order.holdPeriods)))
        .toList()
      ..sort((a, b) => _cmp(a.woNumber, b.woNumber));

    return ReportResult(
      from: from,
      to: to,
      received: received,
      stepsCompleted: stepsCompleted,
      ordersTouched: touched.length,
      completed: completed.length,
      completedList: completedList,
      open: active.length,
      attention: active.where((x) => x.ev.alerts.isNotEmpty).length,
      attentionByCode: attentionByCode,
      byStage: byStage,
      stepsByKey: stepsByKey,
      contractors: contractors,
      quantities: q,
      delays: delays,
      series: series,
    );
  }

  DailyReport dailyReport(List<OrderInput> orders, String date, {Map<String, int>? alertSettings}) {
    final r = report(orders, date, date, today: date, alertSettings: alertSettings);
    final prev = fromDay(toDay(date) - 1);
    final p = report(orders, prev, prev, today: prev, alertSettings: alertSettings);
    final trend = report(orders, fromDay(toDay(date) - 13), date, today: date, alertSettings: alertSettings).series;
    return DailyReport(r, p.received, p.completed, trend);
  }
}

// ---------------- Result types ----------------
class StepCount {
  int ready = 0;
  int total = 0;
}

class PipelineResult {
  final int activeCount;
  final Map<String, StepCount> steps;
  final Map<String, int> buckets;
  const PipelineResult(this.activeCount, this.steps, this.buckets);
}

class DayStarts {
  final String date;
  final List<String> orders = [];
  DayStarts(this.date);
  int get count => orders.length;
}

class BoardCard {
  final String? id, woNumber, type, district, contractor, next, nextKey, startsOn, severity;
  final int daysWaiting;
  final bool onHold;
  const BoardCard({
    this.id,
    this.woNumber,
    required this.type,
    this.district,
    this.contractor,
    this.next,
    this.nextKey,
    required this.daysWaiting,
    this.startsOn,
    this.severity,
    this.onHold = false,
  });
}

class BoardColumn {
  final String stage;
  final List<BoardCard> cards;
  const BoardColumn(this.stage, this.cards);
}

class FollowUpItem {
  final String? id, woNumber, severity, startsOn;
  final List<String> steps;
  final int daysWaiting;
  const FollowUpItem({this.id, this.woNumber, required this.steps, required this.daysWaiting, this.severity, this.startsOn});
}

class FollowUpGroup {
  final String group;
  String? severity;
  final List<FollowUpItem> items = [];
  FollowUpGroup(this.group);
}

class ContractorFollowUp {
  final String contractor;
  int orders = 0;
  int late = 0;
  final Map<String, FollowUpGroup> groups = {};
  ContractorFollowUp(this.contractor);

  /// Groups in urgency order: most severe first, then the fixed action order.
  List<FollowUpGroup> get sortedGroups => groups.values.toList()
    ..sort((a, b) {
      final s = _sevRank(b.severity) - _sevRank(a.severity);
      if (s != 0) return s;
      return Insights._groupOrder(a.group) - Insights._groupOrder(b.group);
    });
}

class SearchHit {
  final String? id, woNumber;
  final String kind, value, status;
  final bool prefix;
  const SearchHit(this.id, this.woNumber, this.kind, this.value, this.prefix, this.status);
}

class StepCondition {
  final String step, state; // state: done | not_done | ready
  final String? from, to;
  const StepCondition(this.step, this.state, {this.from, this.to});
  factory StepCondition.fromJson(Map<String, dynamic> j) =>
      StepCondition(j['step'] as String, j['state'] as String, from: j['from'] as String?, to: j['to'] as String?);
}

class FilterCriteria {
  final List<String>? status, categories, types, contractors, districts, voltages, surfaces, tasreeh;
  final List<int>? cableSizes;
  final String? receivedFrom, receivedTo;
  final List<StepCondition> steps;
  final List<String> quick;
  final bool includeDeleted;
  const FilterCriteria({
    this.status,
    this.categories,
    this.types,
    this.contractors,
    this.districts,
    this.voltages,
    this.surfaces,
    this.tasreeh,
    this.cableSizes,
    this.receivedFrom,
    this.receivedTo,
    this.steps = const [],
    this.quick = const [],
    this.includeDeleted = false,
  });
  factory FilterCriteria.fromJson(Map<String, dynamic> j) {
    List<String>? sl(String k) => (j[k] as List?)?.cast<String>();
    final rec = (j['received'] as Map?)?.cast<String, dynamic>();
    return FilterCriteria(
      status: sl('status'),
      categories: sl('categories'),
      types: sl('types'),
      contractors: sl('contractors'),
      districts: sl('districts'),
      voltages: sl('voltages'),
      surfaces: sl('surfaces'),
      tasreeh: sl('tasreeh'),
      cableSizes: (j['cableSizes'] as List?)?.map((e) => (e as num).toInt()).toList(),
      receivedFrom: rec?['from'] as String?,
      receivedTo: rec?['to'] as String?,
      steps: ((j['steps'] as List?) ?? const []).map((e) => StepCondition.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      quick: sl('quick') ?? const [],
      includeDeleted: j['includeDeleted'] as bool? ?? false,
    );
  }
}

class DateRange {
  final String from, to;
  const DateRange(this.from, this.to);
}

class _ConAcc {
  final String name;
  int open = 0, completedInPeriod = 0, lateStarts = 0;
  final List<int> finishDays = [];
  _ConAcc(this.name);
}

class ContractorStats {
  final String contractor;
  final int open, completedInPeriod, lateStarts;
  final int? avgDaysToFinish;
  final int finished; // completed orders behind the average (any date)
  final int finishDaysTotal; // their days added up, so contractors can be combined exactly
  const ContractorStats(this.contractor, this.open, this.completedInPeriod, this.lateStarts, this.avgDaysToFinish,
      {this.finished = 0, this.finishDaysTotal = 0});
}

class DelayRow {
  final String? id, woNumber, district, contractor;
  final String type, code, severity;
  final int? days;
  const DelayRow(this.id, this.woNumber, this.type, this.district, this.contractor, this.code, this.days, this.severity);
}

class SeriesPoint {
  final String date;
  final int received, completed;
  const SeriesPoint(this.date, this.received, this.completed);
}

class CompletedRow {
  final String? id, woNumber;
  final String type;
  final int days;
  const CompletedRow(this.id, this.woNumber, this.type, this.days);
}

class ReportResult {
  final String from, to;
  final int received, stepsCompleted, ordersTouched, completed, open, attention;
  final List<CompletedRow> completedList;
  final Map<String, int> attentionByCode, byStage, stepsByKey;
  final List<ContractorStats> contractors;
  final Map<String, double> quantities;
  final List<DelayRow> delays;
  final List<SeriesPoint> series;
  const ReportResult({
    required this.from,
    required this.to,
    required this.received,
    required this.stepsCompleted,
    required this.ordersTouched,
    required this.completed,
    required this.completedList,
    required this.open,
    required this.attention,
    required this.attentionByCode,
    required this.byStage,
    required this.stepsByKey,
    required this.contractors,
    required this.quantities,
    required this.delays,
    required this.series,
  });
}

class DailyReport {
  final ReportResult day;
  final int receivedPrev, completedPrev;
  final List<SeriesPoint> trend;
  const DailyReport(this.day, this.receivedPrev, this.completedPrev, this.trend);
}
