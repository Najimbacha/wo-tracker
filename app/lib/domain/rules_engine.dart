// Rules engine: mirrors tools/rules-check/engine.mjs exactly.
// Both are verified against test/fixtures/golden.json.
// Dates are 'YYYY-MM-DD' strings in Riyadh local time; days are calendar days.

import 'order_input.dart';

int toDay(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) throw FormatException('Bad date: $s');
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final dt = DateTime.utc(y, mo, d);
  if (dt.year != y || dt.month != mo || dt.day != d) throw FormatException('Bad date: $s');
  return dt.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

String fromDay(int n) {
  final dt = DateTime.fromMillisecondsSinceEpoch(n * Duration.millisecondsPerDay, isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)}';
}

/// Calendar days from [from] to [to], not counting days on hold.
int activeDays(String from, String to, [List<HoldPeriod> holds = const []]) {
  final a = toDay(from), b = toDay(to);
  if (b <= a) return 0;
  var held = 0;
  for (final h in holds) {
    final hs = a > toDay(h.from) ? a : toDay(h.from);
    final hEnd = h.to != null ? toDay(h.to!) : b;
    final he = b < hEnd ? b : hEnd;
    if (he > hs) held += he - hs;
  }
  final r = b - a - held;
  return r < 0 ? 0 : r;
}

class StepInstance {
  final String id;
  final String key;
  final String package;
  final String scope; // order | segment | meter
  final String? instance;
  final List<String> deps;
  final String? gate;
  const StepInstance(this.id, this.key, this.package, this.scope, this.instance, this.deps, this.gate);
}

class Reason {
  final String code; // waiting_for | tasreeh_starts | no_tasreeh_dates | missing_segments | ...
  final List<String> steps;
  final String? date;
  final String? permit; // tasreeh number, for permit errors
  final String? segment; // segment id, for segment errors
  final Map<String, Object?> extra; // anything else an action reports (state, id, district, wo)
  const Reason(this.code, {this.steps = const [], this.date, this.permit, this.segment, this.extra = const {}});
  Object? operator [](String k) => switch (k) {
        'code' => code,
        'steps' => steps,
        'date' => date,
        'permit' => permit,
        'segment' => segment,
        _ => extra[k],
      };
}

class StepState {
  final StepInstance step;
  final String state; // done | na | ready | locked
  final String? doneDate;
  final String? naReason;
  final List<Reason> reasons;
  const StepState(this.step, this.state, {this.doneDate, this.naReason, this.reasons = const []});
  String get id => step.id;
  bool get closed => state == 'done' || state == 'na';
}

class Alert {
  final String code;
  final String severity; // warning | critical
  final Map<String, Object?> data;
  const Alert(this.code, this.severity, this.data);
  Object? operator [](String k) => k == 'code' ? code : (k == 'severity' ? severity : data[k]);
}

class Evaluation {
  final List<StepState> steps;
  final int closed;
  final int total;
  final String status; // open | on_hold | completed | cancelled | merged
  final String? stage;
  final List<String> next;
  final List<Alert> alerts;
  const Evaluation(this.steps, this.closed, this.total, this.status, this.stage, this.next, this.alerts);
}

class RulesEngine {
  final Map<String, dynamic> rules;
  RulesEngine(this.rules);

  Map<String, dynamic> _m(Object? o) => Map<String, dynamic>.from(o as Map);
  List<String> _sl(Object? o) => ((o as List?) ?? const []).cast<String>();

  Map<String, dynamic> get _types => _m(rules['types']);
  Map<String, dynamic> get _packages => _m(rules['packages']);
  Map<String, dynamic> get _steps => _m(rules['steps']);

  List<String> segmentRecipe(Segment seg) {
    String key;
    if (seg.base == 'soil') {
      key = 'soil';
    } else if (seg.base == 'asphalt') {
      key = seg.width >= 80 ? 'asphalt_80' : 'asphalt_40';
    } else {
      throw ArgumentError('Unknown segment base: ${seg.base}');
    }
    final steps = [..._sl(_m(rules['segmentRecipes'])[key])];
    if (seg.tiled) steps.add(rules['tiledStep'] as String);
    return steps;
  }

  List<String> orderPackages(OrderInput o) {
    final t = _types[o.type];
    if (t == null) throw ArgumentError('Unknown type: ${o.type}');
    final type = _m(t);
    var pkgs = _sl(type['packages']);
    if ((type['optionalExcavation'] as bool? ?? false) && o.needsExcavation) {
      pkgs = [..._sl(rules['optionalExcavationPackages']), ...pkgs];
    }
    return pkgs;
  }

  List<Meter> _meters(OrderInput o) => o.meters.isNotEmpty ? o.meters : const [Meter('m1')];

  List<StepInstance> generate(OrderInput o) {
    final pkgs = orderPackages(o);
    final has = pkgs.toSet();
    final emergency = o.category == 'emergency';
    final out = <StepInstance>[];
    final byPackage = <String, List<String>>{};
    void add(StepInstance s) {
      out.add(s);
      byPackage.putIfAbsent(s.package, () => []).add(s.id);
    }

    List<String> resolveEntry(String pkg) {
      final list = ((_m(rules['entryDeps'])[pkg] as List?) ?? const []).map(_m).toList();
      Map<String, dynamic>? rule;
      for (final r in list) {
        final when = r['whenPackage'] as String?;
        if (when == null || has.contains(when)) {
          rule = r;
          break;
        }
      }
      if (rule == null) return [];
      var deps = _sl(rule['deps']);
      if (emergency && rule['emergencyDrops'] != null) {
        final drops = _sl(rule['emergencyDrops']);
        deps = deps.where((d) => !drops.contains(d)).toList();
      }
      final ids = <String>[];
      for (final d in deps) {
        if (d == '@restoration') {
          ids.addAll(byPackage['restoration'] ?? const []);
        } else if (d == '@all') {
          ids.addAll(out.where((s) => s.package != pkg).map((s) => s.id));
        } else {
          final found = out.where((s) => s.key == d && s.scope == 'order').toList();
          if (found.isEmpty) throw StateError('Entry dependency $d of $pkg not generated for type ${o.type}');
          ids.addAll(found.map((s) => s.id));
        }
      }
      return ids;
    }

    for (final pkg in pkgs) {
      final def = _m(_packages[pkg]);
      final scope = def['scope'] as String;
      if (scope == 'order') {
        String? prev;
        final keys = _sl(def['steps']);
        for (var i = 0; i < keys.length; i++) {
          final key = keys[i];
          final deps = i == 0 ? resolveEntry(pkg) : [prev!];
          add(StepInstance(key, key, pkg, 'order', null, deps, _m(_steps[key])['gate'] as String?));
          prev = key;
        }
      } else if (scope == 'segment') {
        final entry = resolveEntry(pkg);
        for (final seg in o.segments) {
          String? prev;
          final recipe = segmentRecipe(seg);
          for (var i = 0; i < recipe.length; i++) {
            final id = '${recipe[i]}@${seg.id}';
            add(StepInstance(id, recipe[i], pkg, 'segment', seg.id, i == 0 ? [...entry] : [prev!], null));
            prev = id;
          }
        }
      } else if (scope == 'meter') {
        final entry = resolveEntry(pkg);
        final keys = _sl(def['steps']);
        for (final m in _meters(o)) {
          String? prev;
          for (var i = 0; i < keys.length; i++) {
            final id = '${keys[i]}@${m.id}';
            add(StepInstance(id, keys[i], pkg, 'meter', m.id, i == 0 ? [...entry] : [prev!], null));
            prev = id;
          }
        }
      } else {
        throw StateError('Unknown scope $scope');
      }
    }
    return out;
  }

  bool _closed(OrderInput o, String id) => o.steps[id]?.closed ?? false;

  String? _firstPermitStart(OrderInput o) {
    final starts = o.permits.where((p) => p.startDate != null).map((p) => toDay(p.startDate!)).toList();
    if (starts.isEmpty) return null;
    starts.sort();
    return fromDay(starts.first);
  }

  // Tasreeh marked Not applicable: no permit dates will come, so field work is not held back.
  bool _tasreehWaived(OrderInput o) => o.steps['tasreeh_applied']?.na ?? false;

  bool _gateOpen(OrderInput o, String today) {
    if (_tasreehWaived(o)) return true;
    final s = _firstPermitStart(o);
    return s != null && toDay(s) <= toDay(today);
  }

  Permit? currentPermit(OrderInput o, String today) {
    final t = toDay(today);
    final ps = o.permits
        .where((p) => p.startDate != null && p.endDate != null && toDay(p.startDate!) <= t && t <= toDay(p.endDate!))
        .toList()
      ..sort((a, b) => toDay(b.startDate!) - toDay(a.startDate!));
    return ps.isEmpty ? null : ps.first;
  }

  Evaluation evaluate(OrderInput o, String today, {Map<String, int>? alertSettings}) {
    final th = <String, int>{
      ..._m(rules['alertDefaults']).map((k, v) => MapEntry(k, (v as num).toInt())),
      ...?alertSettings,
    };
    final steps = generate(o);
    final pkgs = orderPackages(o);
    final emergency = o.category == 'emergency';

    final ev = <StepState>[];
    for (final s in steps) {
      final r = o.steps[s.id];
      if (r != null && r.done != null) {
        ev.add(StepState(s, 'done', doneDate: r.done));
        continue;
      }
      if (r != null && r.na) {
        ev.add(StepState(s, 'na', naReason: r.reason ?? ''));
        continue;
      }
      final reasons = <Reason>[];
      final lockedBy = s.deps.where((d) => !_closed(o, d)).toList();
      if (lockedBy.isNotEmpty) reasons.add(Reason('waiting_for', steps: lockedBy));
      if (s.gate == 'tasreehStarted' && !emergency && !_gateOpen(o, today)) {
        final start = _firstPermitStart(o);
        reasons.add(start != null ? Reason('tasreeh_starts', date: start) : const Reason('no_tasreeh_dates'));
      }
      if (s.key == 'certificate') {
        _m(rules['requiredData']).forEach((pkg, req) {
          final q = _m(req);
          if (pkgs.contains(pkg) && q['blocks'] == 'certificate' && q['kind'] == 'segments' && o.segments.isEmpty) {
            reasons.add(const Reason('missing_segments'));
          }
        });
      }
      ev.add(reasons.isEmpty ? StepState(s, 'ready') : StepState(s, 'locked', reasons: reasons));
    }

    final total = ev.length;
    final closed = ev.where((e) => e.closed).length;
    final allDone = total > 0 && closed == total;
    String status;
    if (o.state == 'cancelled' || o.state == 'merged') {
      status = o.state;
    } else if (allDone) {
      status = 'completed';
    } else if (o.state == 'on_hold') {
      status = 'on_hold';
    } else {
      status = 'open';
    }

    String? stage;
    if (status == 'open' || status == 'on_hold') {
      StepState? first;
      for (final e in ev) {
        if (!e.closed) {
          first = e;
          break;
        }
      }
      if (first != null) {
        final codes = first.state == 'locked' ? first.reasons.map((r) => r.code).toList() : const <String>[];
        if (codes.contains('tasreeh_starts')) {
          stage = 'starting';
        } else if (codes.contains('no_tasreeh_dates')) {
          // Applied but no dates from Baladiya yet: still waiting for the tasreeh.
          stage = 'tasreeh';
        } else {
          for (final st in (rules['stages'] as List).map(_m)) {
            if (_sl(st['packages']).contains(first.step.package)) {
              stage = st['key'] as String;
              break;
            }
          }
        }
      }
    }

    final alerts = status == 'open'
        ? _alerts(o, today, th, ev, pkgs, stage)
        : status == 'on_hold'
            ? _holdAlerts(o, today)
            : <Alert>[];
    return Evaluation(ev, closed, total, status, stage, ev.where((e) => e.state == 'ready').map((e) => e.id).toList(), alerts);
  }

  // On hold: the only alert is the review date the user set when pausing the order.
  List<Alert> _holdAlerts(OrderInput o, String today) {
    final alerts = <Alert>[];
    HoldPeriod? open;
    for (final h in o.holdPeriods) {
      if (h.to == null) open = h;
    }
    final review = open?.review;
    if (review != null && toDay(review) <= toDay(today)) {
      alerts.add(Alert('hold_review_due', 'warning', {'date': review, 'days': toDay(today) - toDay(review)}));
    }
    return alerts;
  }

  List<Alert> _alerts(OrderInput o, String today, Map<String, int> th, List<StepState> ev, List<String> pkgs, String? stage) {
    final alerts = <Alert>[];
    final emergency = o.category == 'emergency';
    StepState? get(String id) {
      for (final e in ev) {
        if (e.id == id) return e;
      }
      return null;
    }

    int days(String from) => activeDays(from, today, o.holdPeriods);

    // Late start.
    if (!emergency) {
      final start = _firstPermitStart(o);
      for (final e in ev.where((x) => x.step.key == 'excavation' || x.step.key == 'poles')) {
        if (e.closed || start == null || toDay(start) > toDay(today)) continue;
        final d = days(start);
        if (d >= th['lateStartDays']!) {
          alerts.add(Alert('late_start', d >= 5 ? 'critical' : 'warning', {'step': e.id, 'days': d}));
        }
      }
    }

    // Open trench.
    final exc = get('excavation');
    if (exc != null && exc.state == 'done' && pkgs.contains('restoration')) {
      final openSeg = o.segments.isEmpty ||
          o.segments.any((s) {
            StepState? first;
            for (final e in ev) {
              if (e.step.instance == s.id && e.step.package == 'restoration') {
                first = e;
                break;
              }
            }
            return first != null && !first.closed;
          });
      final d = days(exc.doneDate!);
      if (openSeg && d >= th['openTrenchDays']!) alerts.add(Alert('open_trench', 'critical', {'days': d}));
    }

    // Restoration overdue.
    for (final s in o.segments) {
      final segSteps = ev.where((e) => e.step.instance == s.id && e.step.package == 'restoration').toList();
      if (segSteps.isEmpty) continue;
      final first = segSteps.first, last = segSteps.last;
      if (first.state == 'done' && !last.closed) {
        final d = days(first.doneDate!);
        if (d >= th['restorationOverdueDays']!) {
          alerts.add(Alert('restoration_overdue', 'warning', {'segment': s.id, 'days': d}));
        }
      }
    }

    // Tasreeh coverage.
    const fieldPkgs = ['civil', 'overhead', 'restoration', 'transformer'];
    final fieldOpen = ev.any((e) => fieldPkgs.contains(e.step.package) && !e.closed);
    final permits = o.permits.where((p) => p.startDate != null && p.endDate != null).toList();
    if (fieldOpen && permits.isNotEmpty) {
      final t = toDay(today);
      final cur = currentPermit(o, today);
      final firstStart = permits.map((p) => toDay(p.startDate!)).reduce((a, b) => a < b ? a : b);
      if (cur == null && t > firstStart) {
        final ended = permits.where((p) => toDay(p.endDate!) < t).map((p) => toDay(p.endDate!)).toList();
        final future = permits.any((p) => toDay(p.startDate!) > t);
        alerts.add(Alert('no_active_tasreeh', 'critical', {
          'since': ended.isEmpty ? null : fromDay(ended.reduce((a, b) => a > b ? a : b) + 1),
          'nextStarts': future,
        }));
      } else if (cur != null) {
        final left = toDay(cur.endDate!) - t;
        final hasNext = permits.any((p) => toDay(p.startDate!) > toDay(cur.startDate!));
        if (left <= th['tasreehEndingDays']! && !hasNext) {
          alerts.add(Alert('next_tasreeh_needed', 'warning', {'daysLeft': left}));
        }
      }
    }

    // Meter not on.
    for (final m in _meters(o)) {
      StepState? first;
      for (final e in ev) {
        if (e.step.instance == m.id && const ['meter_installed', 'breaker_meter_changed', 'meter_relocated'].contains(e.step.key)) {
          first = e;
          break;
        }
      }
      final on = get('meter_on@${m.id}');
      if (first != null && on != null && first.state == 'done' && !on.closed) {
        final d = days(first.doneDate!);
        if (d >= th['meterNotOnDays']!) alerts.add(Alert('meter_not_on', 'warning', {'meter': m.id, 'days': d}));
      }
    }

    // Emergency work without tasreeh.
    if (emergency && pkgs.contains('tasreeh')) {
      StepState? started;
      for (final e in ev) {
        if ((e.step.key == 'excavation' || e.step.key == 'poles') && e.state == 'done') {
          started = e;
          break;
        }
      }
      final ta = get('tasreeh_applied');
      if (started != null && ta != null && !ta.closed) {
        final d = days(started.doneDate!);
        if (d >= th['tawariTasreehMissingDays']!) alerts.add(Alert('tawari_tasreeh_missing', 'warning', {'days': d}));
      }
    }

    // Stalled, except while the next work is waiting for a tasreeh start date in the future.
    if (o.lastChangeDate != null && stage != 'starting') {
      final d = days(o.lastChangeDate!);
      if (d >= th['stalledDays']!) alerts.add(Alert('stalled', 'warning', {'days': d}));
    }
    return alerts;
  }

  /// Error codes; empty means the step may be marked done on [date].
  List<Reason> validateMarkDone(OrderInput o, String stepId, String date, String today) {
    final steps = generate(o);
    StepInstance? s;
    for (final x in steps) {
      if (x.id == stepId) {
        s = x;
        break;
      }
    }
    if (s == null) return const [Reason('unknown_step')];
    final errors = <Reason>[];
    if (_closed(o, stepId)) errors.add(const Reason('already_closed'));
    final open = s.deps.where((d) => !_closed(o, d)).toList();
    if (open.isNotEmpty) errors.add(Reason('waiting_for', steps: open));
    if (toDay(date) > toDay(today)) errors.add(const Reason('future_date'));
    if (o.receivedDate != null && toDay(date) < toDay(o.receivedDate!)) errors.add(const Reason('before_received'));
    final depDates = s.deps.map((d) => o.steps[d]?.done).whereType<String>().map(toDay).toList();
    if (depDates.isNotEmpty) {
      final maxDep = depDates.reduce((a, b) => a > b ? a : b);
      if (toDay(date) < maxDep) errors.add(Reason('before_previous_step', date: fromDay(maxDep)));
    }
    if (s.gate == 'tasreehStarted' && o.category != 'emergency' && !_tasreehWaived(o)) {
      final start = _firstPermitStart(o);
      if (start == null) {
        errors.add(const Reason('no_tasreeh_dates'));
      } else if (toDay(date) < toDay(start)) {
        errors.add(Reason('before_tasreeh_start', date: start));
      }
    }
    if (_m(_steps[s.key])['requires'] == 'cableRuns' && o.cableRuns.isEmpty) errors.add(const Reason('needs_cable_runs'));
    if (s.key == 'certificate' && orderPackages(o).contains('restoration') && o.segments.isEmpty) {
      errors.add(const Reason('missing_segments'));
    }
    return errors;
  }

  /// Closed steps that depend (directly or indirectly) on [stepId].
  List<String> clearImpact(OrderInput o, String stepId) {
    final steps = generate(o);
    final dependents = <String>{};
    var grew = true;
    while (grew) {
      grew = false;
      for (final s in steps) {
        if (dependents.contains(s.id)) continue;
        if (s.deps.contains(stepId) || s.deps.any(dependents.contains)) {
          dependents.add(s.id);
          grew = true;
        }
      }
    }
    return steps.where((s) => dependents.contains(s.id) && _closed(o, s.id)).map((s) => s.id).toList();
  }

  List<Reason> validateOrder(OrderInput o) {
    final errors = <Reason>[];
    final cat = _m(rules['categories'])[o.category];
    if (cat == null) {
      errors.add(const Reason('unknown_category'));
    } else if (!RegExp(_m(cat)['woNumberPattern'] as String).hasMatch(o.woNumber ?? '')) {
      errors.add(const Reason('bad_wo_number'));
    }
    if (_types[o.type] == null) errors.add(const Reason('unknown_type'));
    final nums = <String>{};
    for (final p in o.permits) {
      if (p.startDate != null && p.endDate != null && toDay(p.endDate!) < toDay(p.startDate!)) errors.add(Reason('permit_end_before_start', permit: p.number));
      if (p.appliedDate != null && p.startDate != null && toDay(p.startDate!) < toDay(p.appliedDate!)) {
        errors.add(Reason('permit_start_before_applied', permit: p.number));
      }
      if (p.number != null) {
        if (nums.contains(p.number)) errors.add(Reason('duplicate_permit', permit: p.number));
        nums.add(p.number!);
      }
    }
    for (final s in o.segments) {
      if (!['soil', 'asphalt'].contains(s.base)) errors.add(Reason('bad_segment_base', segment: s.id));
      if (![40, 80].contains(s.width)) errors.add(Reason('bad_segment_width', segment: s.id));
      if (!(s.lengthM > 0)) errors.add(Reason('bad_segment_length', segment: s.id));
    }
    return errors;
  }
}
