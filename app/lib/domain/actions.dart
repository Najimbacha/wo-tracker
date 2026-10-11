// Every change the user can make to a work order. Mirrors tools/rules-check/actions.mjs;
// both are tested on test/fixtures/actions.json. Orders are immutable: each action
// returns a changed copy, or the reasons it was refused.
import 'insights.dart';
import 'order_input.dart';
import 'rules_engine.dart';

class ActionResult {
  final bool ok;
  final List<Reason> errors;
  final OrderInput? order;
  final bool completed; // this action finished the last step
  final List<String> cleared; // clearStep: every step that was cleared
  final List<String> alsoClears; // clearPreview: later steps that would be cleared too
  final OrderInput? target; // merge: the order that replaces this one
  final List<String> carried; // merge: steps copied to the target
  final List<String> notCarried; // merge: finished steps that were not copied

  const ActionResult._({
    required this.ok,
    this.errors = const [],
    this.order,
    this.completed = false,
    this.cleared = const [],
    this.alsoClears = const [],
    this.target,
    this.carried = const [],
    this.notCarried = const [],
  });

  factory ActionResult.fail(List<Reason> errors) => ActionResult._(ok: false, errors: errors);
}

class BulkResult {
  final List<OrderInput> orders;
  final List<({String id, List<String> steps})> updated;
  final List<({String id, List<Reason> errors})> skipped;
  const BulkResult(this.orders, this.updated, this.skipped);
}

class FormSpec {
  final bool type, excavationSwitch, tasreeh, segments, cableRuns, meters, oldMeterNumber, workBeforeTasreeh;
  final String? woNumberPattern;
  const FormSpec({
    required this.type,
    this.excavationSwitch = false,
    this.tasreeh = false,
    this.segments = false,
    this.cableRuns = false,
    this.meters = false,
    this.oldMeterNumber = false,
    this.workBeforeTasreeh = false,
    this.woNumberPattern,
  });
  Object? operator [](String k) => switch (k) {
        'type' => type,
        'excavationSwitch' => excavationSwitch,
        'tasreeh' => tasreeh,
        'segments' => segments,
        'cableRuns' => cableRuns,
        'meters' => meters,
        'oldMeterNumber' => oldMeterNumber,
        'workBeforeTasreeh' => workBeforeTasreeh,
        'woNumberPattern' => woNumberPattern,
        _ => throw ArgumentError(k),
      };
}

class Actions {
  final RulesEngine engine;
  Actions(this.engine);

  Map<String, dynamic> get _rules => engine.rules;

  static bool _isClosed(OrderInput o, String id) => o.steps[id]?.closed ?? false;
  static String? _note(OrderInput o, String id) => o.steps[id]?.note;
  static bool _blank(String? s) => s == null || s.trim().isEmpty;
  static String? _maxDate(String? a, String? b) => a == null ? b : (b == null ? a : (toDay(a) >= toDay(b) ? a : b));
  bool _known(OrderInput o, String stepId) => engine.generate(o).any((s) => s.id == stepId);
  bool _justCompleted(OrderInput before, OrderInput after, String today) =>
      engine.evaluate(after, today).status == 'completed' && engine.evaluate(before, today).status != 'completed';
  static ActionResult _notActive(OrderInput o) => o.state == 'cancelled' || o.state == 'merged'
      ? ActionResult.fail([Reason('not_active', extra: {'state': o.state})])
      : const ActionResult._(ok: true);

  // ---------------- Steps ----------------

  ActionResult markDone(OrderInput o, String stepId, String date, String today) {
    final na = _notActive(o);
    if (!na.ok) return na;
    final errors = engine.validateMarkDone(o, stepId, date, today);
    if (errors.isNotEmpty) return ActionResult.fail(errors);
    final next = o.copyWith(
        steps: {...o.steps, stepId: StepRecord(done: date, note: _note(o, stepId))}, lastChangeDate: _maxDate(o.lastChangeDate, date));
    return ActionResult._(ok: true, order: next, completed: _justCompleted(o, next, today));
  }

  ActionResult markNA(OrderInput o, String stepId, String? reason, String today) {
    final na = _notActive(o);
    if (!na.ok) return na;
    if (!_known(o, stepId)) return ActionResult.fail(const [Reason('unknown_step')]);
    final errors = <Reason>[
      if (_isClosed(o, stepId)) const Reason('already_closed'),
      if (_blank(reason)) const Reason('reason_required'),
    ];
    if (errors.isNotEmpty) return ActionResult.fail(errors);
    final next = o.copyWith(
      steps: {...o.steps, stepId: StepRecord(na: true, reason: reason!.trim(), note: _note(o, stepId))},
      lastChangeDate: _maxDate(o.lastChangeDate, today),
    );
    return ActionResult._(ok: true, order: next, completed: _justCompleted(o, next, today));
  }

  ActionResult clearPreview(OrderInput o, String stepId) {
    if (!_known(o, stepId)) return ActionResult.fail(const [Reason('unknown_step')]);
    if (!_isClosed(o, stepId)) return ActionResult.fail(const [Reason('not_closed')]);
    return ActionResult._(ok: true, alsoClears: engine.clearImpact(o, stepId));
  }

  ActionResult clearStep(OrderInput o, String stepId) {
    final p = clearPreview(o, stepId);
    if (!p.ok) return p;
    final cleared = [stepId, ...p.alsoClears];
    final steps = Map<String, StepRecord>.from(o.steps);
    for (final id in cleared) {
      // A note written on the step stays; only the done date or N/A is removed.
      final note = steps[id]?.note;
      if (note != null) {
        steps[id] = StepRecord(note: note);
      } else {
        steps.remove(id);
      }
    }
    return ActionResult._(ok: true, order: o.copyWith(steps: steps), cleared: cleared);
  }

  BulkResult bulkMarkDone(List<OrderInput> orders, String stepKey, String date, String today) {
    final results = <OrderInput>[];
    final updated = <({String id, List<String> steps})>[];
    final skipped = <({String id, List<Reason> errors})>[];
    for (final order in orders) {
      final instances = engine.generate(order).where((s) => s.key == stepKey).toList();
      if (instances.isEmpty) {
        skipped.add((id: order.id ?? '', errors: const [Reason('unknown_step')]));
        results.add(order);
        continue;
      }
      final open = instances.where((s) => !_isClosed(order, s.id)).toList();
      if (open.isEmpty) {
        skipped.add((id: order.id ?? '', errors: const [Reason('already_closed')]));
        results.add(order);
        continue;
      }
      var cur = order;
      final marked = <String>[];
      List<Reason>? firstErrors;
      for (final s in open) {
        final r = markDone(cur, s.id, date, today);
        if (r.ok) {
          cur = r.order!;
          marked.add(s.id);
        } else {
          firstErrors ??= r.errors;
        }
      }
      if (marked.isNotEmpty) {
        updated.add((id: order.id ?? '', steps: marked));
      } else {
        skipped.add((id: order.id ?? '', errors: firstErrors ?? const []));
      }
      results.add(cur);
    }
    return BulkResult(results, updated, skipped);
  }

  // ---------------- Status ----------------

  ActionResult putOnHold(OrderInput o, String from, String? reason, String today, {String? reviewDate}) {
    final st = engine.evaluate(o, today).status;
    final ends = o.holdPeriods.where((h) => h.to != null).map((h) => toDay(h.to!)).toList();
    final lastEnd = ends.isEmpty ? null : ends.reduce((a, b) => a > b ? a : b);
    final errors = <Reason>[
      if (st == 'on_hold') const Reason('already_on_hold') else if (st != 'open') Reason('not_active', extra: {'state': st}),
      if (_blank(reason)) const Reason('reason_required'),
      if (toDay(from) > toDay(today)) const Reason('future_date'),
      if (o.receivedDate != null && toDay(from) < toDay(o.receivedDate!)) const Reason('before_received'),
      if (lastEnd != null && toDay(from) < lastEnd) Reason('hold_overlap', date: fromDay(lastEnd)),
      if (reviewDate != null && toDay(reviewDate) < toDay(from)) const Reason('review_before_hold'),
    ];
    if (errors.isNotEmpty) return ActionResult.fail(errors);
    final period = HoldPeriod(from: from, reason: reason!.trim(), review: reviewDate);
    return ActionResult._(ok: true, order: o.copyWith(state: 'on_hold', holdPeriods: [...o.holdPeriods, period]));
  }

  ActionResult resume(OrderInput o, String date, String today) {
    final i = o.holdPeriods.indexWhere((h) => h.to == null);
    if (o.state != 'on_hold' || i < 0) return ActionResult.fail(const [Reason('not_on_hold')]);
    final open = o.holdPeriods[i];
    final errors = <Reason>[
      if (toDay(date) > toDay(today)) const Reason('future_date'),
      if (toDay(date) < toDay(open.from)) Reason('before_hold_start', date: open.from),
    ];
    if (errors.isNotEmpty) return ActionResult.fail(errors);
    final hp = [...o.holdPeriods]..[i] = open.endedOn(date);
    return ActionResult._(ok: true, order: o.copyWith(state: 'open', holdPeriods: hp));
  }

  static List<HoldPeriod> _closeOpenHold(OrderInput o, String date) => o.holdPeriods
      .map((h) => h.to != null ? h : h.endedOn(toDay(date) < toDay(h.from) ? h.from : date))
      .toList();

  ActionResult cancel(OrderInput o, String? reason, String today) {
    final st = engine.evaluate(o, today).status;
    final errors = <Reason>[
      if (st != 'open' && st != 'on_hold') Reason('not_active', extra: {'state': st}),
      if (_blank(reason)) const Reason('reason_required'),
    ];
    if (errors.isNotEmpty) return ActionResult.fail(errors);
    return ActionResult._(
      ok: true,
      order: o.copyWith(state: 'cancelled', stateReason: reason!.trim(), holdPeriods: _closeOpenHold(o, today)),
    );
  }

  ActionResult merge(OrderInput o, OrderInput? target, String? reason, bool carry, String today) {
    final st = engine.evaluate(o, today).status;
    final errors = <Reason>[
      if (st != 'open' && st != 'on_hold') Reason('not_active', extra: {'state': st}),
      if (target == null)
        const Reason('merge_target_required')
      else if (target.id == o.id)
        const Reason('merge_into_self')
      else if (target.deleted || const ['cancelled', 'merged'].contains(engine.evaluate(target, today).status))
        const Reason('merge_target_inactive'),
      if (_blank(reason)) const Reason('reason_required'),
    ];
    if (errors.isNotEmpty || target == null) return ActionResult.fail(errors);

    final from = o.copyWith(state: 'merged', stateReason: reason!.trim(), mergedInto: target.id, holdPeriods: _closeOpenHold(o, today));
    var to = target;
    final carried = <String>[];
    final notCarried = <String>[];
    if (carry) {
      final targetIds = engine.generate(target).map((s) => s.id).toSet();
      final steps = Map<String, StepRecord>.from(target.steps);
      var last = target.lastChangeDate;
      for (final s in engine.generate(o)) {
        if (!_isClosed(o, s.id)) continue;
        if (s.instance != null || s.package == 'closeout' || !targetIds.contains(s.id) || _isClosed(target, s.id)) {
          notCarried.add(s.id);
          continue;
        }
        final r = o.steps[s.id]!;
        steps[s.id] = r;
        carried.add(s.id);
        if (r.done != null) last = _maxDate(last, r.done);
      }
      to = target.copyWith(steps: steps, lastChangeDate: last);
    }
    return ActionResult._(ok: true, order: from, target: to, carried: carried, notCarried: notCarried);
  }

  ActionResult reopen(OrderInput o) {
    if (o.state != 'cancelled' && o.state != 'merged') return ActionResult.fail(const [Reason('not_cancelled')]);
    return ActionResult._(ok: true, order: o.copyWith(state: 'open', stateReason: null, mergedInto: null));
  }

  // ---------------- Editing ----------------

  List<String> editImpact(OrderInput before, OrderInput after) {
    final afterIds = engine.generate(after).map((s) => s.id).toSet();
    return engine.generate(before).where((s) => _isClosed(before, s.id) && !afterIds.contains(s.id)).map((s) => s.id).toList();
  }

  FormSpec formSpec(OrderInput draft) {
    final type = (_rules['types'] as Map)[draft.type] as Map?;
    if (type == null) return const FormSpec(type: false);
    final cat = (_rules['categories'] as Map)[draft.category] as Map?;
    final pkgs = engine.orderPackages(draft);
    final packages = _rules['packages'] as Map;
    return FormSpec(
      type: true,
      excavationSwitch: type['optionalExcavation'] == true,
      tasreeh: pkgs.contains('tasreeh'),
      segments: pkgs.contains('restoration'),
      cableRuns: pkgs.contains('civil'),
      meters: pkgs.any((p) => (packages[p] as Map)['scope'] == 'meter'),
      oldMeterNumber: pkgs.contains('meter_change') || pkgs.contains('meter_relocate'),
      woNumberPattern: cat?['woNumberPattern'] as String?,
      workBeforeTasreeh: cat?['fieldWorkBeforeTasreeh'] == true,
    );
  }

  static String _westernDigits(String s) => s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
        final c = m.group(0)!.codeUnitAt(0);
        return '${c >= 0x06F0 ? c - 0x06F0 : c - 0x0660}';
      });
  static String? _cleanNumber(String? s) => s == null ? null : _westernDigits(s).trim();

  /// Arabic digits → 0-9 and spaces trimmed, in the work order, tasreeh and meter numbers.
  /// With [rules], an excavation flag left over from another type is switched off
  /// (only 409 has the switch; the database refuses it on any other type).
  static OrderInput normalizeDraft(OrderInput d, {Map<String, dynamic>? rules}) {
    final type = rules == null ? null : (rules['types'] as Map)[d.type] as Map?;
    final dropExcavation = type != null && d.needsExcavation && type['optionalExcavation'] != true;
    return _normalizeNumbers(dropExcavation ? d.copyWith(needsExcavation: false) : d);
  }

  static OrderInput _normalizeNumbers(OrderInput d) => d.copyWith(
        woNumber: _cleanNumber(d.woNumber),
        permits: d.permits
            .map((p) => Permit(number: _cleanNumber(p.number), appliedDate: p.appliedDate, startDate: p.startDate, endDate: p.endDate))
            .toList(),
        meters: d.meters
            .map((m) => Meter(m.id,
                number: _cleanNumber(m.number), oldNumber: _cleanNumber(m.oldNumber), meterType: m.meterType, breakerAmps: m.breakerAmps))
            .toList(),
        networkRef: d.networkRef == null || d.networkRef!.isEmpty ? d.networkRef : _cleanNumber(d.networkRef),
      );

  List<Reason> validateDraft(OrderInput input, List<OrderInput> orders, String today) {
    final draft = normalizeDraft(input, rules: _rules);
    final errors = <Reason>[];
    if (_blank(draft.woNumber)) errors.add(const Reason('wo_number_required'));
    if (draft.receivedDate == null) {
      errors.add(const Reason('received_required'));
    } else if (toDay(draft.receivedDate!) > toDay(today)) {
      errors.add(const Reason('future_date'));
    }
    for (final e in engine.validateOrder(draft)) {
      if (!(e.code == 'bad_wo_number' && _blank(draft.woNumber))) errors.add(e);
    }
    // Meter steps are recorded per meter; an order without one would lose them when it is added.
    if ((_rules['types'] as Map)[draft.type] != null && formSpec(draft).meters && draft.meters.isEmpty) {
      errors.add(const Reason('meter_required'));
    }
    if (!_blank(draft.woNumber)) {
      final dup = findDuplicate(orders, draft.woNumber!, exceptId: draft.id);
      if (dup != null) {
        errors.add(Reason(dup.deleted ? 'duplicate_wo_deleted' : 'duplicate_wo',
            date: dup.receivedDate, extra: {'id': dup.id, 'district': dup.district ?? ''}));
      }
    }
    for (final p in draft.permits) {
      final other = findPermitOwner(orders, p.number, exceptId: draft.id);
      if (other != null) {
        errors.add(Reason(other.deleted ? 'duplicate_permit_deleted' : 'duplicate_permit_other', permit: p.number, extra: {'wo': other.woNumber}));
      }
    }
    return errors;
  }

  static String _normNumber(String? s) => Insights.normalizeText(s ?? '').replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  /// An existing order (deleted ones too, so they can be restored) with the same number.
  static OrderInput? findDuplicate(List<OrderInput> orders, String woNumber, {String? exceptId}) {
    final n = _normNumber(woNumber);
    if (n.isEmpty) return null;
    final hits = orders.where((o) => o.id != exceptId && _normNumber(o.woNumber) == n).toList();
    if (hits.isEmpty) return null;
    return hits.firstWhere((h) => !h.deleted, orElse: () => hits.first);
  }

  /// Another order that already uses this tasreeh number. Deleted orders count too: the
  /// database keeps their numbers so that restoring them can never clash.
  static OrderInput? findPermitOwner(List<OrderInput> orders, String? number, {String? exceptId}) {
    final n = _normNumber(number);
    if (n.isEmpty) return null;
    final hits = orders.where((o) => o.id != exceptId && o.permits.any((p) => _normNumber(p.number) == n)).toList();
    if (hits.isEmpty) return null;
    return hits.firstWhere((o) => !o.deleted, orElse: () => hits.first);
  }
}
