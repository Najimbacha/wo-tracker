// What goes into the two Excel files, as plain data (mirrors tools/rules-check/export-doc.mjs;
// test/export_doc_test.dart checks both give the same workbooks).
//   reportWorkbook: the report with every row, in English or Arabic.
//   dataWorkbook:   a complete copy of every order; ordersFromDataWorkbook reads it back.
import '../domain/hijri.dart';
import '../domain/insights.dart';
import '../domain/order_input.dart';
import '../domain/rules_engine.dart';
import '../i18n/strings.dart';
import 'report_doc.dart';

Map<String, Object?> _col(String key, String label, [String type = 'text', int width = 14, bool computed = false]) =>
    {'key': key, 'label': label, 'type': type, 'width': width, if (computed) 'computed': true};

class ExportDoc {
  final Insights insights;
  ExportDoc(this.insights);

  RulesEngine get _engine => insights.engine;
  Map<String, dynamic> get _rules => insights.rules;

  Map<String, Object?> reportWorkbook(
    List<OrderInput> orders,
    String kind,
    String date,
    String today, {
    required Strings s,
    HijriCalendar? hijri,
    required String preparedBy,
    String? generatedAt,
  }) {
    final doc = ReportDoc(insights).build(orders, kind, date, today, s: s, hijri: hijri, preparedBy: preparedBy, generatedAt: generatedAt);
    final period = doc['period'] as Map<String, Object?>;
    final from = period['from'] as String, to = period['to'] as String;
    final asOf = toDay(to) < toDay(today) ? to : today;
    final r = insights.report(orders, from, to, today: asOf);
    final byId = {for (final o in orders) o.id: o};
    final header = doc['header'] as Map<String, Object?>;
    List<Map<String, Object?>> rowsOf(String section) => ((doc[section] as Map)['rows'] as List).cast<Map<String, Object?>>();

    final summary = <Map<String, Object?>>[
      {'kind': 'title', 'label': '${header['eyebrow']} · ${header['title']}'},
      if ((header['hijri'] as String).isNotEmpty) {'kind': 'subtitle', 'label': header['hijri']},
      {'kind': 'subtitle', 'label': '${header['preparedBy']} · ${header['generated']}'},
      {'kind': 'blank'},
      {'kind': 'heading', 'label': s.t('report.keyFigures')},
      for (final k in (doc['kpis'] as List).cast<Map<String, Object?>>())
        {'kind': 'item', 'label': k['label'], 'value': k['value'], 'note': k['note'], 'style': k['tone'] == 'alert' && (k['value'] as int) > 0 ? 'critical' : null},
      {'kind': 'blank'},
      {'kind': 'heading', 'label': (doc['stages'] as Map)['title']},
      for (final st in rowsOf('stages')) {'kind': 'item', 'label': st['label'], 'value': st['value']},
      {'kind': 'blank'},
      {'kind': 'heading', 'label': (doc['steps'] as Map)['title']},
      if (rowsOf('steps').isEmpty)
        {'kind': 'item', 'label': doc['empty']}
      else
        for (final st in rowsOf('steps')) {'kind': 'item', 'label': st['label'], 'value': st['value']},
      {'kind': 'blank'},
      {'kind': 'heading', 'label': '${(doc['quantities'] as Map)['title']} (${(doc['quantities'] as Map)['subtitle']})'},
      for (final q in ((doc['quantities'] as Map)['items'] as List).cast<Map<String, Object?>>()) {'kind': 'item', 'label': q['label'], 'value': q['value']},
    ];

    final attention = {
      'name': s.t('report.sheet.attention'),
      'kind': 'table',
      'columns': [
        _col('wo', s.t('report.col.wo'), 'text', 13), _col('type', s.t('report.col.type'), 'text', 7), _col('district', s.t('report.col.district'), 'text', 16),
        _col('contractor', s.t('report.col.contractor'), 'text', 20), _col('issue', s.t('report.col.issue'), 'text', 38), _col('days', s.t('report.col.days'), 'int', 7),
        _col('severity', s.t('report.col.severity'), 'text', 10),
      ],
      'rows': [
        for (final d in rowsOf('delays')) {...d, 'severity': s.t('severity.${d['severity']}'), 'style': d['severity'] == 'critical' ? 'critical' : null},
      ],
    };

    final contractors = {
      'name': s.t('report.sheet.contractors'),
      'kind': 'table',
      'columns': [
        _col('contractor', s.t('report.col.contractor'), 'text', 24), _col('open', s.t('report.open'), 'int', 8), _col('completed', s.t('report.completedInPeriod'), 'int', 11),
        _col('lateStarts', s.t('report.lateStarts'), 'int', 10), _col('finished', s.t('report.col.finished'), 'int', 14), _col('totalDays', s.t('report.col.totalDays'), 'int', 14),
        _col('avgDays', s.t('report.avgDaysToFinish'), 'int', 14),
      ],
      'rows': [
        for (final c in r.contractors)
          {
            'contractor': c.contractor == unassignedContractor ? s.t('common.unassigned') : c.contractor,
            'open': c.open, 'completed': c.completedInPeriod, 'lateStarts': c.lateStarts,
            'finished': c.finished, 'totalDays': c.finishDaysTotal, 'avgDays': c.avgDaysToFinish,
          },
      ],
      'rowFormulas': {
        'avgDays': {'ratio': ['totalDays', 'finished']},
      },
      'totals': {
        'label': s.t('report.total'),
        'sum': ['open', 'completed', 'lateStarts', 'finished', 'totalDays'],
        'formulas': {
          'avgDays': {'ratio': ['totalDays', 'finished']},
        },
      },
    };

    String? doneOn(OrderInput o) => Insights.completedOn(_engine.evaluate(o, asOf));
    final completed = {
      'name': s.t('report.sheet.completed'),
      'kind': 'table',
      'columns': [
        _col('wo', s.t('report.col.wo'), 'text', 13), _col('type', s.t('report.col.type'), 'text', 7), _col('district', s.t('report.col.district'), 'text', 16),
        _col('contractor', s.t('report.col.contractor'), 'text', 20), _col('received', s.t('report.col.received'), 'date', 12), _col('completedOn', s.t('report.col.completedOn'), 'date', 12),
        _col('days', s.t('report.col.days'), 'int', 7),
      ],
      'rows': [
        for (final c in r.completedList)
          {
            'wo': c.woNumber, 'type': c.type, 'district': byId[c.id]!.district ?? '', 'contractor': byId[c.id]!.contractor ?? s.t('common.unassigned'),
            'received': byId[c.id]!.receivedDate, 'completedOn': doneOn(byId[c.id]!), 'days': c.days,
          },
      ],
    };

    final openOrders = <({OrderInput o, Evaluation ev})>[];
    for (final o in orders) {
      if (o.deleted) continue;
      final snap = Insights.snapshot(o, asOf);
      if (snap == null) continue;
      final ev = _engine.evaluate(snap, asOf);
      if (ev.status == 'open' || ev.status == 'on_hold') openOrders.add((o: snap, ev: ev));
    }
    openOrders.sort((a, b) {
      final d = toDay(a.o.receivedDate!) - toDay(b.o.receivedDate!);
      return d != 0 ? d : (a.o.woNumber ?? '').compareTo(b.o.woNumber ?? '');
    });
    final open = {
      'name': s.t('report.sheet.open'),
      'kind': 'table',
      'columns': [
        _col('wo', s.t('report.col.wo'), 'text', 13), _col('type', s.t('report.col.type'), 'text', 7), _col('category', s.t('report.col.category'), 'text', 11),
        _col('district', s.t('report.col.district'), 'text', 16), _col('contractor', s.t('report.col.contractor'), 'text', 20), _col('received', s.t('report.col.received'), 'date', 12),
        _col('status', s.t('report.col.status'), 'text', 10), _col('stage', s.t('report.col.stage'), 'text', 16), _col('next', s.t('report.col.next'), 'text', 26),
        _col('closed', s.t('report.col.progress'), 'int', 10), _col('total', s.t('report.total'), 'int', 7), _col('alerts', s.t('report.col.alerts'), 'text', 30),
      ],
      'rows': [
        for (final x in openOrders)
          {
            'wo': x.o.woNumber, 'type': x.o.type, 'category': s.t('category.${x.o.category}'), 'district': x.o.district ?? '',
            'contractor': x.o.contractor ?? s.t('common.unassigned'), 'received': x.o.receivedDate, 'status': s.t('status.${x.ev.status}'),
            'stage': x.ev.stage == null ? '' : s.t('stage.${x.ev.stage}'),
            'next': {for (final id in x.ev.next) s.step(id.split('@').first)}.join(', '),
            'closed': x.ev.closed, 'total': x.ev.total,
            'alerts': {for (final a in x.ev.alerts) s.t('alertShort.${a.code}')}.join(' · '),
            'style': x.ev.alerts.any((a) => a.severity == 'critical') ? 'critical' : null,
          },
      ],
    };

    final periodName = kind == 'daily' ? from : (kind == 'weekly' ? '${from}_to_$to' : from.substring(0, 7));
    return {
      'fileName': '$kind-report-$periodName${s.isRtl ? '-ar' : ''}.xlsx',
      'dir': doc['dir'],
      'sheets': [
        {
          'name': s.t('report.sheet.summary'),
          'kind': 'summary',
          'columns': [_col('label', s.t('report.col.item'), 'text', 34), _col('value', s.t('report.col.value'), 'int', 10), _col('note', s.t('report.col.note'), 'text', 46)],
          'rows': summary,
        },
        attention, contractors, completed, open,
      ],
    };
  }

  // ---------------- Complete data copy ----------------
  static final _data = <String, List<Map<String, Object?>>>{
    'orders': [
      _col('id', 'Order id', 'text', 12), _col('woNumber', 'Work order number', 'text', 14), _col('category', 'Category', 'text', 11), _col('type', 'Type', 'text', 6),
      _col('receivedDate', 'Received', 'date', 12), _col('district', 'District', 'text', 16), _col('street', 'Street', 'text', 16), _col('networkRef', 'Network reference', 'text', 22),
      _col('contractor', 'Contractor', 'text', 20), _col('needsExcavation', 'Needs excavation', 'bool', 9), _col('state', 'State', 'text', 10), _col('stateReason', 'Reason', 'text', 24),
      _col('stateDate', 'Cancelled / merged on', 'date', 12), _col('mergedInto', 'Merged into (order id)', 'text', 12), _col('notes', 'Notes', 'text', 30), _col('lastChangeDate', 'Last change', 'date', 12), _col('deleted', 'Deleted', 'bool', 8), _col('deletedReason', 'Why deleted', 'text', 20),
      _col('status', 'Status now (calculated)', 'text', 12, true), _col('stage', 'Stage now (calculated)', 'text', 12, true),
    ],
    'steps': [
      _col('orderId', 'Order id', 'text', 12), _col('woNumber', 'Work order number', 'text', 14), _col('stepId', 'Step id', 'text', 28), _col('step', 'Step', 'text', 22, true),
      _col('done', 'Done on', 'date', 12), _col('na', 'Not applicable', 'bool', 9), _col('reason', 'Reason', 'text', 30), _col('note', 'Note', 'text', 30),
    ],
    'permits': [
      _col('orderId', 'Order id', 'text', 12), _col('woNumber', 'Work order number', 'text', 14), _col('seq', 'No.', 'int', 5), _col('number', 'Tasreeh number', 'text', 16),
      _col('appliedDate', 'Applied', 'date', 12), _col('startDate', 'Start', 'date', 12), _col('endDate', 'End', 'date', 12),
    ],
    'segments': [
      _col('orderId', 'Order id', 'text', 12), _col('woNumber', 'Work order number', 'text', 14), _col('id', 'Segment id', 'text', 16), _col('base', 'Base', 'text', 9),
      _col('width', 'Width (cm)', 'int', 9), _col('lengthM', 'Length (m)', 'decimal', 10), _col('tiled', 'Tiled', 'bool', 7),
    ],
    'meters': [
      _col('orderId', 'Order id', 'text', 12), _col('woNumber', 'Work order number', 'text', 14), _col('id', 'Meter id', 'text', 16), _col('number', 'Meter number', 'text', 14),
      _col('oldNumber', 'Old meter number', 'text', 14), _col('meterType', 'Meter type', 'text', 12), _col('breakerAmps', 'Breaker (A)', 'int', 9),
    ],
    'cableRuns': [
      _col('orderId', 'Order id', 'text', 12), _col('woNumber', 'Work order number', 'text', 14), _col('seq', 'No.', 'int', 5), _col('sizeMm2', 'Size (mm²)', 'int', 9),
      _col('voltage', 'Voltage', 'text', 8), _col('lengthM', 'Length (m)', 'decimal', 10),
    ],
    'holds': [
      _col('orderId', 'Order id', 'text', 12), _col('woNumber', 'Work order number', 'text', 14), _col('seq', 'No.', 'int', 5), _col('from', 'From', 'date', 12),
      _col('to', 'To', 'date', 12), _col('reason', 'Reason', 'text', 24), _col('review', 'Review on', 'date', 12),
    ],
  };
  static const _sheetNames = {
    'orders': 'Orders', 'steps': 'Steps', 'permits': 'Tasreeh', 'segments': 'Surface segments',
    'meters': 'Meters', 'cableRuns': 'Cable runs', 'holds': 'Holds',
  };

  Map<String, Object?> dataWorkbook(List<OrderInput> orders, String today, [String? generatedAt]) {
    final rows = {for (final k in _data.keys) k: <Map<String, Object?>>[]};
    final steps = _rules['steps'] as Map;
    for (final o in orders) {
      final ev = _engine.evaluate(o, today);
      rows['orders']!.add({
        'id': o.id, 'woNumber': o.woNumber, 'category': o.category, 'type': o.type, 'receivedDate': o.receivedDate,
        'district': o.district, 'street': o.street, 'networkRef': o.networkRef, 'contractor': o.contractor,
        'needsExcavation': o.needsExcavation, 'state': o.state, 'stateReason': o.stateReason, 'stateDate': o.stateDate, 'mergedInto': o.mergedInto,
        'notes': o.notes, 'lastChangeDate': o.lastChangeDate, 'deleted': o.deleted, 'deletedReason': o.deletedReason, 'status': ev.status, 'stage': ev.stage,
      });
      final pos = <String, int>{};
      final all = _engine.evaluate(o, '2100-01-01').steps;
      for (var i = 0; i < all.length; i++) {
        pos[all[i].id] = i;
      }
      final recs = o.steps.entries.toList()
        ..sort((a, b) {
          final d = (pos[a.key] ?? 1000000000) - (pos[b.key] ?? 1000000000);
          return d != 0 ? d : a.key.compareTo(b.key);
        });
      for (final e in recs) {
        final def = steps[e.key.split('@').first] as Map?;
        rows['steps']!.add({
          'orderId': o.id, 'woNumber': o.woNumber, 'stepId': e.key, 'step': def == null ? e.key : def['en'],
          'done': e.value.done, 'na': e.value.na, 'reason': e.value.reason, 'note': e.value.note,
        });
      }
      for (var i = 0; i < o.permits.length; i++) {
        final p = o.permits[i];
        rows['permits']!.add({'orderId': o.id, 'woNumber': o.woNumber, 'seq': i + 1, 'number': p.number, 'appliedDate': p.appliedDate, 'startDate': p.startDate, 'endDate': p.endDate});
      }
      for (final g in o.segments) {
        rows['segments']!.add({'orderId': o.id, 'woNumber': o.woNumber, 'id': g.id, 'base': g.base, 'width': g.width, 'lengthM': g.lengthM, 'tiled': g.tiled});
      }
      for (final m in o.meters) {
        rows['meters']!.add({
          'orderId': o.id, 'woNumber': o.woNumber, 'id': m.id, 'number': m.number, 'oldNumber': m.oldNumber,
          'meterType': m.meterType, 'breakerAmps': m.breakerAmps,
        });
      }
      for (var i = 0; i < o.cableRuns.length; i++) {
        final c = o.cableRuns[i];
        rows['cableRuns']!.add({'orderId': o.id, 'woNumber': o.woNumber, 'seq': i + 1, 'sizeMm2': c.sizeMm2, 'voltage': c.voltage, 'lengthM': c.lengthM});
      }
      for (var i = 0; i < o.holdPeriods.length; i++) {
        final h = o.holdPeriods[i];
        rows['holds']!.add({'orderId': o.id, 'woNumber': o.woNumber, 'seq': i + 1, 'from': h.from, 'to': h.to, 'reason': h.reason, 'review': h.review});
      }
    }
    return {
      'fileName': 'wo-tracker-data-$today.xlsx',
      'dir': 'ltr',
      'about': {
        'generatedAt': generatedAt ?? today,
        'orders': orders.length,
        'format': 3,
        'notIncluded': 'Photos and SEC PDFs (kept in Google Drive), contractor phone numbers, follow-up notes, saved views and settings are not in this file. They are in the nightly database backup.',
      },
      'sheets': [
        for (final k in _data.keys) {'name': _sheetNames[k], 'key': k, 'kind': 'table', 'columns': _data[k], 'rows': rows[k]},
      ],
    };
  }

  /// Rebuilds the orders from a data workbook (each sheet's rows, by column key).
  static List<OrderInput> ordersFromDataWorkbook(Map<String, Object?> wb) {
    List<Map<String, Object?>> sheet(String k) =>
        (((wb['sheets'] as List).cast<Map>().firstWhere((s) => s['key'] == k))['rows'] as List).map((r) => Map<String, Object?>.from(r as Map)).toList();
    Map<String, List<Map<String, Object?>>> by(String k) {
      final m = <String, List<Map<String, Object?>>>{};
      for (final r in sheet(k)) {
        m.putIfAbsent(r['orderId'] as String, () => []).add(r);
      }
      for (final list in m.values) {
        if (list.isNotEmpty && list.first.containsKey('seq')) list.sort((a, b) => (a['seq'] as num).compareTo(b['seq'] as num));
      }
      return m;
    }

    final steps = by('steps'), permits = by('permits'), segments = by('segments'), meters = by('meters'), cables = by('cableRuns'), holds = by('holds');
    return [
      for (final r in sheet('orders'))
        OrderInput(
          id: r['id'] as String,
          type: r['type'] as String,
          category: r['category'] as String,
          woNumber: r['woNumber'] as String?,
          receivedDate: r['receivedDate'] as String?,
          needsExcavation: r['needsExcavation'] == true,
          contractor: r['contractor'] as String?,
          district: r['district'] as String?,
          street: r['street'] as String?,
          networkRef: r['networkRef'] as String?,
          notes: r['notes'] as String?,
          segments: [
            for (final g in segments[r['id']] ?? const <Map<String, Object?>>[])
              Segment(id: g['id'] as String, base: g['base'] as String, width: (g['width'] as num).toInt(), lengthM: (g['lengthM'] as num).toDouble(), tiled: g['tiled'] == true),
          ],
          meters: [
            for (final m in meters[r['id']] ?? const <Map<String, Object?>>[])
              Meter(m['id'] as String,
                  number: m['number'] as String?,
                  oldNumber: m['oldNumber'] as String?,
                  meterType: m['meterType'] as String?,
                  breakerAmps: (m['breakerAmps'] as num?)?.toInt()),
          ],
          cableRuns: [
            for (final c in cables[r['id']] ?? const <Map<String, Object?>>[])
              CableRun(sizeMm2: (c['sizeMm2'] as num).toInt(), voltage: c['voltage'] as String, lengthM: (c['lengthM'] as num).toDouble()),
          ],
          permits: [
            for (final p in permits[r['id']] ?? const <Map<String, Object?>>[])
              Permit(number: p['number'] as String?, appliedDate: p['appliedDate'] as String?, startDate: p['startDate'] as String?, endDate: p['endDate'] as String?),
          ],
          steps: {
            for (final s in steps[r['id']] ?? const <Map<String, Object?>>[])
              s['stepId'] as String: s['na'] == true
                  ? StepRecord(na: true, reason: s['reason'] as String?, note: s['note'] as String?)
                  : StepRecord(done: s['done'] as String?, note: s['note'] as String?),
          },
          state: r['state'] as String? ?? 'open',
          stateReason: r['stateReason'] as String?,
          stateDate: r['stateDate'] as String?,
          mergedInto: r['mergedInto'] as String?,
          holdPeriods: [
            for (final h in holds[r['id']] ?? const <Map<String, Object?>>[])
              HoldPeriod(from: h['from'] as String, to: h['to'] as String?, reason: h['reason'] as String?, review: h['review'] as String?),
          ],
          lastChangeDate: r['lastChangeDate'] as String?,
          deleted: r['deleted'] == true,
          deletedReason: r['deletedReason'] as String?,
        ),
    ];
  }
}
