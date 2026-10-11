// What goes into the two Excel files, as plain data. The Excel writer only lays it out.
//   reportWorkbook: the report with every row (Summary, Needs attention, Contractors,
//                   Completed, Open orders), in English or Arabic.
//   dataWorkbook:   a complete copy of every order, one sheet per kind of record, that
//                   ordersFromDataWorkbook can turn back into the orders (tested).
// app/lib/report/export_doc.dart mirrors this file.
import { toDay, evaluate } from './engine.mjs';
import { report, snapshot, completedOn } from './insights.mjs';
import { reportDocument } from './report-doc.mjs';
import { textFor } from './i18n.mjs';

const col = (key, label, type = 'text', width = 14) => ({ key, label, type, width });

export function reportWorkbook(rules, orders, kind, date, today, opts) {
  const doc = reportDocument(rules, orders, kind, date, today, opts);
  const x = textFor(opts.lang, opts.text, opts.english, rules);
  const { t } = x;
  const range = doc.period;
  const asOf = toDay(range.to) < toDay(today) ? range.to : today;
  const r = report(rules, orders, range.from, range.to, asOf);
  const byId = new Map(orders.map((o) => [o.id, o]));

  // Summary: the report's headline figures, one per row.
  const summary = [
    { kind: 'title', label: `${doc.header.eyebrow} · ${doc.header.title}` },
    ...(doc.header.hijri ? [{ kind: 'subtitle', label: doc.header.hijri }] : []),
    { kind: 'subtitle', label: `${doc.header.preparedBy} · ${doc.header.generated}` },
    { kind: 'blank' },
    { kind: 'heading', label: t('report.keyFigures') },
    ...doc.kpis.map((k) => ({ kind: 'item', label: k.label, value: k.value, note: k.note, style: k.tone === 'alert' && k.value ? 'critical' : null })),
    { kind: 'blank' },
    { kind: 'heading', label: doc.stages.title },
    ...doc.stages.rows.map((s) => ({ kind: 'item', label: s.label, value: s.value })),
    { kind: 'blank' },
    { kind: 'heading', label: doc.steps.title },
    ...(doc.steps.rows.length ? doc.steps.rows.map((s) => ({ kind: 'item', label: s.label, value: s.value })) : [{ kind: 'item', label: doc.empty }]),
    { kind: 'blank' },
    { kind: 'heading', label: `${doc.quantities.title} (${doc.quantities.subtitle})` },
    ...doc.quantities.items.map((q) => ({ kind: 'item', label: q.label, value: q.value })),
  ];

  const attention = {
    name: t('report.sheet.attention'),
    kind: 'table',
    columns: [
      col('wo', t('report.col.wo'), 'text', 13), col('type', t('report.col.type'), 'text', 7), col('district', t('report.col.district'), 'text', 16),
      col('contractor', t('report.col.contractor'), 'text', 20), col('issue', t('report.col.issue'), 'text', 38), col('days', t('report.col.days'), 'int', 7),
      col('severity', t('report.col.severity'), 'text', 10),
    ],
    rows: doc.delays.rows.map((d) => ({ ...d, severity: t(`severity.${d.severity}`), style: d.severity === 'critical' ? 'critical' : null })),
  };

  // Every contractor, with formulas for the average and the totals.
  const contractors = {
    name: t('report.sheet.contractors'),
    kind: 'table',
    columns: [
      col('contractor', t('report.col.contractor'), 'text', 24), col('open', t('report.open'), 'int', 8), col('completed', t('report.completedInPeriod'), 'int', 11),
      col('lateStarts', t('report.lateStarts'), 'int', 10), col('finished', t('report.col.finished'), 'int', 14), col('totalDays', t('report.col.totalDays'), 'int', 14),
      col('avgDays', t('report.avgDaysToFinish'), 'int', 14),
    ],
    rows: r.contractors.map((c) => ({
      contractor: c.contractor === '(not assigned)' ? t('common.unassigned') : c.contractor,
      open: c.open, completed: c.completedInPeriod, lateStarts: c.lateStarts, finished: c.finished, totalDays: c.finishDaysTotal,
      avgDays: c.avgDaysToFinish,
    })),
    rowFormulas: { avgDays: { ratio: ['totalDays', 'finished'] } },
    totals: { label: t('report.total'), sum: ['open', 'completed', 'lateStarts', 'finished', 'totalDays'], formulas: { avgDays: { ratio: ['totalDays', 'finished'] } } },
  };

  const doneOn = (o) => completedOn(evaluate(rules, o, asOf));
  const completed = {
    name: t('report.sheet.completed'),
    kind: 'table',
    columns: [
      col('wo', t('report.col.wo'), 'text', 13), col('type', t('report.col.type'), 'text', 7), col('district', t('report.col.district'), 'text', 16),
      col('contractor', t('report.col.contractor'), 'text', 20), col('received', t('report.col.received'), 'date', 12), col('completedOn', t('report.col.completedOn'), 'date', 12),
      col('days', t('report.col.days'), 'int', 7),
    ],
    rows: r.completedList.map((c) => {
      const o = byId.get(c.id);
      return { wo: c.woNumber, type: c.type, district: o.district || '', contractor: o.contractor || t('common.unassigned'), received: o.receivedDate, completedOn: doneOn(o), days: c.days };
    }),
  };

  // Every order still open at the end of the period.
  const open = {
    name: t('report.sheet.open'),
    kind: 'table',
    columns: [
      col('wo', t('report.col.wo'), 'text', 13), col('type', t('report.col.type'), 'text', 7), col('category', t('report.col.category'), 'text', 11),
      col('district', t('report.col.district'), 'text', 16), col('contractor', t('report.col.contractor'), 'text', 20), col('received', t('report.col.received'), 'date', 12),
      col('status', t('report.col.status'), 'text', 10), col('stage', t('report.col.stage'), 'text', 16), col('next', t('report.col.next'), 'text', 26),
      col('closed', t('report.col.progress'), 'int', 10), col('total', t('report.total'), 'int', 7), col('alerts', t('report.col.alerts'), 'text', 30),
    ],
    rows: orders
      .filter((o) => !o.deleted)
      .map((o) => snapshot(o, asOf))
      .filter(Boolean)
      .map((o) => ({ o, ev: evaluate(rules, o, asOf) }))
      .filter(({ ev }) => ev.status === 'open' || ev.status === 'on_hold')
      .sort((a, b) => toDay(a.o.receivedDate) - toDay(b.o.receivedDate) || (a.o.woNumber < b.o.woNumber ? -1 : a.o.woNumber > b.o.woNumber ? 1 : 0))
      .map(({ o, ev }) => ({
        wo: o.woNumber, type: o.type, category: t(`category.${o.category}`), district: o.district || '', contractor: o.contractor || t('common.unassigned'),
        received: o.receivedDate, status: t(`status.${ev.status}`), stage: ev.stage ? t(`stage.${ev.stage}`) : '',
        next: [...new Set(ev.next.map((id) => x.step(id.split('@')[0])))].join(', '),
        closed: ev.progress.closed, total: ev.progress.total,
        alerts: [...new Set(ev.alerts.map((a) => t(`alertShort.${a.code}`)))].join(' · '),
        style: ev.alerts.some((a) => a.severity === 'critical') ? 'critical' : null,
      })),
  };

  const periodName = kind === 'daily' ? range.from : kind === 'weekly' ? `${range.from}_to_${range.to}` : range.from.slice(0, 7);
  return {
    fileName: `${kind}-report-${periodName}${opts.lang === 'ar' ? '-ar' : ''}.xlsx`,
    dir: doc.dir,
    sheets: [
      { name: t('report.sheet.summary'), kind: 'summary', columns: [col('label', t('report.col.item'), 'text', 34), col('value', t('report.col.value'), 'int', 10), col('note', t('report.col.note'), 'text', 46)], rows: summary },
      attention, contractors, completed, open,
    ],
  };
}

// ---------------- Complete data copy ----------------
// Language-neutral column names, so the file can always be read back.
const DATA = {
  orders: [
    col('id', 'Order id', 'text', 12), col('woNumber', 'Work order number', 'text', 14), col('category', 'Category', 'text', 11), col('type', 'Type', 'text', 6),
    col('receivedDate', 'Received', 'date', 12), col('district', 'District', 'text', 16), col('street', 'Street', 'text', 16), col('networkRef', 'Network reference', 'text', 22),
    col('contractor', 'Contractor', 'text', 20), col('needsExcavation', 'Needs excavation', 'bool', 9), col('state', 'State', 'text', 10), col('stateReason', 'Reason', 'text', 24),
    col('stateDate', 'Cancelled / merged on', 'date', 12), col('mergedInto', 'Merged into (order id)', 'text', 12), col('notes', 'Notes', 'text', 30), col('lastChangeDate', 'Last change', 'date', 12), col('deleted', 'Deleted', 'bool', 8),
    { ...col('status', 'Status now (calculated)', 'text', 12), computed: true }, { ...col('stage', 'Stage now (calculated)', 'text', 12), computed: true },
  ],
  steps: [col('orderId', 'Order id', 'text', 12), col('woNumber', 'Work order number', 'text', 14), col('stepId', 'Step id', 'text', 28), { ...col('step', 'Step', 'text', 22), computed: true }, col('done', 'Done on', 'date', 12), col('na', 'Not applicable', 'bool', 9), col('reason', 'Reason', 'text', 30), col('note', 'Note', 'text', 30)],
  permits: [col('orderId', 'Order id', 'text', 12), col('woNumber', 'Work order number', 'text', 14), col('seq', 'No.', 'int', 5), col('number', 'Tasreeh number', 'text', 16), col('appliedDate', 'Applied', 'date', 12), col('startDate', 'Start', 'date', 12), col('endDate', 'End', 'date', 12)],
  segments: [col('orderId', 'Order id', 'text', 12), col('woNumber', 'Work order number', 'text', 14), col('id', 'Segment id', 'text', 16), col('base', 'Base', 'text', 9), col('width', 'Width (cm)', 'int', 9), col('lengthM', 'Length (m)', 'decimal', 10), col('tiled', 'Tiled', 'bool', 7)],
  meters: [col('orderId', 'Order id', 'text', 12), col('woNumber', 'Work order number', 'text', 14), col('id', 'Meter id', 'text', 16), col('number', 'Meter number', 'text', 14), col('oldNumber', 'Old meter number', 'text', 14), col('meterType', 'Meter type', 'text', 12), col('breakerAmps', 'Breaker (A)', 'int', 9)],
  cableRuns: [col('orderId', 'Order id', 'text', 12), col('woNumber', 'Work order number', 'text', 14), col('seq', 'No.', 'int', 5), col('sizeMm2', 'Size (mm²)', 'int', 9), col('voltage', 'Voltage', 'text', 8), col('lengthM', 'Length (m)', 'decimal', 10)],
  holds: [col('orderId', 'Order id', 'text', 12), col('woNumber', 'Work order number', 'text', 14), col('seq', 'No.', 'int', 5), col('from', 'From', 'date', 12), col('to', 'To', 'date', 12), col('reason', 'Reason', 'text', 24), col('review', 'Review on', 'date', 12)],
};
const SHEET_NAMES = { orders: 'Orders', steps: 'Steps', permits: 'Tasreeh', segments: 'Surface segments', meters: 'Meters', cableRuns: 'Cable runs', holds: 'Holds' };

export function dataWorkbook(rules, orders, today, generatedAt) {
  const rows = Object.fromEntries(Object.keys(DATA).map((k) => [k, []]));
  for (const o of orders) {
    const ev = evaluate(rules, o, today);
    const st = o.status || {};
    rows.orders.push({
      id: o.id, woNumber: o.woNumber, category: o.category, type: o.type, receivedDate: o.receivedDate ?? null,
      district: o.district ?? null, street: o.street ?? null, networkRef: o.networkRef ?? null, contractor: o.contractor ?? null,
      needsExcavation: !!o.needsExcavation, state: st.state || 'open', stateReason: st.reason ?? null, stateDate: st.date ?? null, mergedInto: st.mergedInto ?? null,
      notes: o.notes ?? null, lastChangeDate: o.lastChangeDate ?? null, deleted: !!o.deleted, status: ev.status, stage: ev.stage ?? null,
    });
    const order = new Map(stepPositions(rules, o));
    for (const [stepId, r] of Object.entries(o.steps || {}).sort((a, b) => (order.get(a[0]) ?? 1e9) - (order.get(b[0]) ?? 1e9) || (a[0] < b[0] ? -1 : 1))) {
      rows.steps.push({ orderId: o.id, woNumber: o.woNumber, stepId, step: rules.steps[stepId.split('@')[0]] ? rules.steps[stepId.split('@')[0]].en : stepId, done: r.done ?? null, na: !!r.na, reason: r.reason ?? null, note: r.note ?? null });
    }
    (o.permits || []).forEach((p, i) => rows.permits.push({ orderId: o.id, woNumber: o.woNumber, seq: i + 1, number: p.number ?? null, appliedDate: p.appliedDate ?? null, startDate: p.startDate ?? null, endDate: p.endDate ?? null }));
    for (const s of o.segments || []) rows.segments.push({ orderId: o.id, woNumber: o.woNumber, id: s.id, base: s.base, width: s.width, lengthM: s.lengthM, tiled: !!s.tiled });
    for (const m of o.meters || []) rows.meters.push({ orderId: o.id, woNumber: o.woNumber, id: m.id, number: m.number ?? null, oldNumber: m.oldNumber ?? null, meterType: m.meterType ?? null, breakerAmps: m.breakerAmps ?? null });
    (o.cableRuns || []).forEach((c, i) => rows.cableRuns.push({ orderId: o.id, woNumber: o.woNumber, seq: i + 1, sizeMm2: c.sizeMm2, voltage: c.voltage, lengthM: c.lengthM }));
    (st.holdPeriods || []).forEach((h, i) => rows.holds.push({ orderId: o.id, woNumber: o.woNumber, seq: i + 1, from: h.from, to: h.to ?? null, reason: h.reason ?? null, review: h.review ?? null }));
  }
  return {
    fileName: `wo-tracker-data-${today}.xlsx`,
    dir: 'ltr',
    about: {
      generatedAt: generatedAt || today, orders: orders.length, format: 3,
      notIncluded: 'Photos and SEC PDFs (kept in Google Drive), contractor phone numbers, follow-up notes, saved views and settings are not in this file. They are in the nightly database backup.',
    },
    sheets: Object.keys(DATA).map((k) => ({ name: SHEET_NAMES[k], key: k, kind: 'table', columns: DATA[k], rows: rows[k] })),
  };
}

function stepPositions(rules, o) {
  // Position of each step in the order's own sequence, so the Steps sheet reads in work order.
  return evaluate(rules, o, '2100-01-01').steps.map((s, i) => [s.id, i]);
}

/** Rebuilds the orders from a data workbook (the sheets' rows, by column key). */
export function ordersFromDataWorkbook(wb) {
  const sheet = (k) => wb.sheets.find((s) => s.key === k).rows;
  const by = (k) => {
    const m = new Map();
    for (const r of sheet(k)) { if (!m.has(r.orderId)) m.set(r.orderId, []); m.get(r.orderId).push(r); }
    return m;
  };
  const steps = by('steps'), permits = by('permits'), segments = by('segments'), meters = by('meters'), cables = by('cableRuns'), holds = by('holds');
  const seq = (a, b) => a.seq - b.seq;
  return sheet('orders').map((r) => {
    const status = { state: r.state, holdPeriods: (holds.get(r.id) || []).sort(seq).map((h) => clean({ from: h.from, to: h.to ?? null, reason: h.reason, review: h.review }, ['to'])) };
    if (r.stateReason) status.reason = r.stateReason;
    if (r.mergedInto) status.mergedInto = r.mergedInto;
    if (r.stateDate) status.date = r.stateDate;
    return clean({
      id: r.id, type: r.type, category: r.category, woNumber: r.woNumber, receivedDate: r.receivedDate, needsExcavation: r.needsExcavation,
      contractor: r.contractor, district: r.district, street: r.street, networkRef: r.networkRef, notes: r.notes,
      segments: (segments.get(r.id) || []).map((s) => ({ id: s.id, base: s.base, width: s.width, lengthM: s.lengthM, tiled: s.tiled })),
      meters: (meters.get(r.id) || []).map((m) => clean({ id: m.id, number: m.number, oldNumber: m.oldNumber, meterType: m.meterType, breakerAmps: m.breakerAmps })),
      cableRuns: (cables.get(r.id) || []).sort(seq).map((c) => ({ sizeMm2: c.sizeMm2, voltage: c.voltage, lengthM: c.lengthM })),
      permits: (permits.get(r.id) || []).sort(seq).map((p) => clean({ number: p.number, appliedDate: p.appliedDate, startDate: p.startDate, endDate: p.endDate })),
      steps: Object.fromEntries((steps.get(r.id) || []).map((s) => [s.stepId, clean({ ...(s.na ? { na: true, reason: s.reason } : { done: s.done }), note: s.note })])),
      status,
      lastChangeDate: r.lastChangeDate,
      deleted: r.deleted || undefined,
    }, ['contractor', 'district', 'street', 'networkRef', 'notes', 'lastChangeDate']);
  });
}

// Drops missing values, except the keys listed in `keepNull` which stay as null.
function clean(o, keepNull = []) {
  const out = {};
  for (const [k, v] of Object.entries(o)) {
    if (v === undefined || (v === null && !keepNull.includes(k))) continue;
    out[k] = v;
  }
  return out;
}

/** Same order, ignoring how "nothing" is written (missing, null, false, empty list). */
export function canonicalOrder(o) {
  const walk = (v) => {
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === 'object') {
      const out = {};
      for (const k of Object.keys(v).sort()) {
        const w = walk(v[k]);
        if (w === null || w === undefined || w === false || (Array.isArray(w) && !w.length)) continue;
        out[k] = w;
      }
      return out;
    }
    return v;
  };
  return walk(o);
}
