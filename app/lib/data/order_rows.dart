// Work orders ↔ database rows. Pure functions, so the mapping is tested without a
// database: rows → OrderInput (reading), and before/after OrderInput → row writes
// (saving). Writes never delete: a removed segment, meter, cable run, tasreeh or hold
// gets deleted_at; a cleared step keeps its row with the date and N/A removed.
//
// Row values use SQLite types: dates as 'YYYY-MM-DD', booleans as 0/1.
import '../domain/order_input.dart';
import 'ids.dart';

typedef Row = Map<String, Object?>;

/// One row to write. [insert] rows carry every column; updates only the changed ones.
/// Step rows are [upsert]: their id is the same on every device, so the row may already
/// exist (written by the other device) even when this order didn't show it.
class RowWrite {
  final String table;
  final String id;
  final String kind; // insert | update | upsert
  final Row values;
  const RowWrite(this.table, this.id, this.kind, this.values);
  @override
  String toString() => '$kind $table $id $values';
}

/// Everything about one order as stored, grouped by table.
class OrderRows {
  final Row order;
  final List<Row> segments, meters, cableRuns, permits, holds, steps;
  const OrderRows(this.order,
      {this.segments = const [], this.meters = const [], this.cableRuns = const [], this.permits = const [], this.holds = const [], this.steps = const []});
}

bool _flag(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
String? _date(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int? _int(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
bool _live(Row r) => r['deleted_at'] == null;
int _cmpStr(Object? a, Object? b) => (a == null ? '￿' : '$a').compareTo(b == null ? '￿' : '$b');

/// Rows → the order the screens and rules work with. Contractor and district come in
/// as names (looked up by the caller).
OrderInput orderFromRows(OrderRows r, {String? contractorName, String? districtName}) {
  final o = r.order;
  final segs = r.segments.where(_live).toList()..sort((a, b) => _cmpStr(a['created_at'], b['created_at']) != 0 ? _cmpStr(a['created_at'], b['created_at']) : _cmpStr(a['id'], b['id']));
  final meters = r.meters.where(_live).toList()
    ..sort((a, b) {
      final s = (_int(a['seq']) ?? 0) - (_int(b['seq']) ?? 0);
      return s != 0 ? s : _cmpStr(a['created_at'], b['created_at']);
    });
  final cables = r.cableRuns.where(_live).toList()..sort((a, b) => _cmpStr(a['created_at'], b['created_at']) != 0 ? _cmpStr(a['created_at'], b['created_at']) : _cmpStr(a['id'], b['id']));
  String? permitKey(Row p) => _date(p['start_date']) ?? _date(p['applied_date']);
  final permits = r.permits.where(_live).toList()
    ..sort((a, b) {
      final s = _cmpStr(permitKey(a), permitKey(b));
      return s != 0 ? s : _cmpStr(a['created_at'], b['created_at']);
    });
  final holds = r.holds.where(_live).toList()..sort((a, b) => _cmpStr(_date(a['from_date']), _date(b['from_date'])));

  final steps = <String, StepRecord>{};
  for (final s in r.steps.where(_live)) {
    final done = _date(s['done_date']);
    final na = _flag(s['not_applicable']);
    final note = s['note'] as String?;
    if (done == null && !na && (note == null || note.isEmpty)) continue;
    final inst = (s['segment_id'] ?? s['meter_id']) as String?;
    final key = inst == null ? s['step_key'] as String : '${s['step_key']}@$inst';
    steps[key] = StepRecord(done: na ? null : done, na: na, reason: na ? s['na_reason'] as String? : null, note: (note == null || note.isEmpty) ? null : note);
  }

  return OrderInput(
    id: o['id'] as String,
    type: o['type_code'] as String,
    category: o['category'] as String,
    woNumber: o['wo_number'] as String?,
    receivedDate: _date(o['received_date']),
    needsExcavation: _flag(o['needs_excavation']),
    segments: [
      for (final s in segs)
        Segment(id: s['id'] as String, base: s['base'] as String, width: _int(s['width_cm']) ?? 40, lengthM: _num(s['length_m']), tiled: _flag(s['tiled'])),
    ],
    meters: [
      for (final m in meters)
        Meter(m['id'] as String,
            number: m['meter_number'] as String?,
            oldNumber: m['old_meter_number'] as String?,
            meterType: m['meter_type'] as String?,
            breakerAmps: _int(m['breaker_amps'])),
    ],
    cableRuns: [
      for (final c in cables)
        CableRun(id: c['id'] as String, sizeMm2: _int(c['size_mm2']) ?? 0, voltage: c['voltage'] as String, lengthM: c['length_m'] == null ? null : _num(c['length_m'])),
    ],
    permits: [
      for (final p in permits)
        Permit(
            id: p['id'] as String,
            number: p['permit_number'] as String?,
            appliedDate: _date(p['applied_date']),
            startDate: _date(p['start_date']),
            endDate: _date(p['end_date'])),
    ],
    steps: steps,
    state: (o['state'] as String?) ?? 'open',
    stateReason: o['state_reason'] as String?,
    stateDate: _date(o['state_date']),
    mergedInto: o['merged_into'] as String?,
    holdPeriods: [
      for (final h in holds)
        HoldPeriod(
            id: h['id'] as String,
            from: _date(h['from_date'])!,
            to: _date(h['to_date']),
            reason: h['reason'] as String?,
            review: _date(h['review_date'])),
    ],
    lastChangeDate: _date(o['last_change_date']),
    contractor: contractorName,
    district: districtName,
    street: o['street'] as String?,
    networkRef: o['network_ref'] as String?,
    notes: o['notes'] as String?,
    deleted: o['deleted_at'] != null,
    deletedReason: o['deleted_reason'] as String?,
  );
}

/// Cached figures written with the order, for fast lists on the server side.
class OrderCache {
  final String status;
  final String? stage;
  final int closed, total;
  const OrderCache(this.status, this.stage, this.closed, this.total);
}

Row _orderValues(OrderInput o, String? contractorId, String? districtId, OrderCache cache, String nowIso) => {
      'wo_number': o.woNumber,
      'category': o.category,
      'type_code': o.type,
      'received_date': o.receivedDate,
      'district_id': districtId,
      'street': _blankToNull(o.street),
      'network_ref': _blankToNull(o.networkRef),
      'contractor_id': contractorId,
      'needs_excavation': o.needsExcavation ? 1 : 0,
      'state': o.state,
      'state_reason': o.stateReason,
      'state_date': o.stateDate,
      'merged_into': o.mergedInto,
      'notes': _blankToNull(o.notes),
      'last_change_date': o.lastChangeDate,
      'status_cache': cache.status,
      'stage_cache': cache.stage,
      'progress_closed': cache.closed,
      'progress_total': cache.total,
      'deleted_reason': o.deleted ? o.deletedReason : null,
    };

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

Row _changed(Row before, Row after) => {
      for (final e in after.entries)
        if (!_same(before[e.key], e.value)) e.key: e.value,
    };

bool _same(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return a == b;
}

/// The rows to write so the database holds [after]. [before] is the order as it was
/// read (null for a new order). [newId] makes ids for new child rows.
/// [segmentStepKeys]: step keys recorded per surface segment (the rest of the
/// instance steps are per meter), from rules.json.
List<RowWrite> orderWrites(
  OrderInput? before,
  OrderInput after, {
  required String? contractorId,
  required String? districtId,
  String? beforeContractorId,
  String? beforeDistrictId,
  required OrderCache cache,
  OrderCache? beforeCache,
  required String nowIso,
  required String Function() newId,
  required Set<String> segmentStepKeys,
}) {
  final id = after.id!;
  final out = <RowWrite>[];

  // The order row.
  final values = _orderValues(after, contractorId, districtId, cache, nowIso);
  if (before == null) {
    out.add(RowWrite('work_orders', id, 'insert', {...values, if (after.deleted) 'deleted_at': nowIso}));
  } else {
    final old = _orderValues(before, beforeContractorId, beforeDistrictId, beforeCache ?? cache, nowIso);
    final ch = _changed(old, values);
    if (after.deleted != before.deleted) ch['deleted_at'] = after.deleted ? nowIso : null;
    if (ch.isNotEmpty) out.add(RowWrite('work_orders', id, 'update', ch));
  }

  // Child rows with their own ids. valuesOf gets the item and its position in its list.
  void children<T>(String table, List<T> beforeList, List<T> afterList, String? Function(T) idOf, Row Function(T, int) valuesOf) {
    final beforeVals = <String, Row>{};
    for (var i = 0; i < beforeList.length; i++) {
      final bid = idOf(beforeList[i]);
      if (bid != null) beforeVals[bid] = valuesOf(beforeList[i], i);
    }
    final seen = <String>{};
    for (var i = 0; i < afterList.length; i++) {
      final a = afterList[i];
      final aid = idOf(a);
      final vals = valuesOf(a, i);
      if (aid == null || !beforeVals.containsKey(aid)) {
        final rid = aid ?? newId();
        seen.add(rid);
        // Upsert: an id we already know may still have its (soft-deleted) row, e.g.
        // when Undo puts back a segment or tasreeh that was removed. It comes back live.
        out.add(RowWrite(table, rid, aid == null ? 'insert' : 'upsert', {'work_order_id': id, ...vals, if (aid != null) 'deleted_at': null}));
      } else {
        seen.add(aid);
        final ch = _changed(beforeVals[aid]!, vals);
        if (ch.isNotEmpty) out.add(RowWrite(table, aid, 'update', ch));
      }
    }
    for (final bid in beforeVals.keys) {
      if (!seen.contains(bid)) out.add(RowWrite(table, bid, 'update', {'deleted_at': nowIso}));
    }
  }

  children<Segment>('segments', before?.segments ?? const [], after.segments, (s) => s.id,
      (s, _) => {'base': s.base, 'width_cm': s.width, 'length_m': s.lengthM, 'tiled': s.tiled ? 1 : 0});
  children<Meter>('meters', before?.meters ?? const [], after.meters, (m) => m.id, (m, i) => {
        'seq': i + 1,
        'meter_number': _blankToNull(m.number),
        'meter_type': m.meterType,
        'breaker_amps': m.breakerAmps,
        'old_meter_number': _blankToNull(m.oldNumber),
      });
  children<CableRun>('cable_runs', before?.cableRuns ?? const [], after.cableRuns, (c) => c.id,
      (c, _) => {'size_mm2': c.sizeMm2, 'voltage': c.voltage, 'length_m': c.lengthM});
  children<Permit>('permits', before?.permits ?? const [], after.permits, (p) => p.id, (p, _) => {
        'permit_number': _blankToNull(p.number),
        'applied_date': p.appliedDate,
        'start_date': p.startDate,
        'end_date': p.endDate,
      });
  children<HoldPeriod>('hold_periods', before?.holdPeriods ?? const [], after.holdPeriods, (h) => h.id, (h, _) => {
        'from_date': h.from,
        'to_date': h.to,
        'reason': h.reason ?? '',
        'review_date': h.review,
      });

  // Step rows: same id on every device; a cleared step keeps its row.
  final keys = <String>{...?before?.steps.keys, ...after.steps.keys};
  for (final key in keys) {
    final b = before?.steps[key];
    final a = after.steps[key];
    if (b != null && a != null && b.done == a.done && b.na == a.na && b.reason == a.reason && b.note == a.note) continue;
    if (b == null && a == null) continue;
    final at = key.indexOf('@');
    final stepKey = at < 0 ? key : key.substring(0, at);
    final inst = at < 0 ? null : key.substring(at + 1);
    final segmentId = inst != null && segmentStepKeys.contains(stepKey) ? inst : null;
    final meterId = inst != null && segmentId == null ? inst : null;
    final na = a?.na ?? false;
    out.add(RowWrite('steps', StepIds.stepRowId(id, stepKey, segmentId: segmentId, meterId: meterId), 'upsert', {
      'work_order_id': id,
      'step_key': stepKey,
      'segment_id': segmentId,
      'meter_id': meterId,
      'done_date': (a == null || na) ? null : a.done,
      'not_applicable': na ? 1 : 0,
      'na_reason': na ? a!.reason : null,
      'note': a?.note,
      'deleted_at': null,
    }));
  }
  return out;
}

/// Step keys recorded per surface segment, from rules.json.
Set<String> segmentStepKeysOf(Map<String, dynamic> rules) {
  final out = <String>{};
  for (final recipe in (rules['segmentRecipes'] as Map).values) {
    out.addAll((recipe as List).cast<String>());
  }
  final tiled = rules['tiledStep'];
  if (tiled is String) out.add(tiled);
  return out;
}
