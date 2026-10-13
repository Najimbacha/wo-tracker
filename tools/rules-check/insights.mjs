// Screen and report logic, built on the rules engine. Mirrored by app/lib/domain/insights.dart
// and checked against app/test/fixtures/insights.json.
import { evaluate, generate, activeDays, toDay, fromDay, orderPackages, currentPermit } from './engine.mjs';

const ACTIVE = new Set(['open', 'on_hold']);
// Plain character-code order, identical to Dart's String.compareTo.
export const cmpStr = (a, b) => { a = String(a ?? ''); b = String(b ?? ''); return a < b ? -1 : a > b ? 1 : 0; };
const SEVERITY_RANK = { critical: 2, warning: 1 };

/**
 * The order as it stood at the end of `asOf`: null if not yet received; steps done
 * later, tasreeh applied for later and holds that started later are left out.
 * Reports for past periods use this so they show the situation as it was then.
 * A cancelled or merged order counts as active before the day it was cancelled or merged
 * (orders saved before that date was stored count as cancelled throughout).
 */
export function snapshot(order, asOf) {
  const t = toDay(asOf);
  if (order.receivedDate && toDay(order.receivedDate) > t) return null;
  const steps = Object.fromEntries(Object.entries(order.steps || {}).filter(([, r]) => !(r.done && toDay(r.done) > t)));
  const permits = (order.permits || []).filter((p) => !(p.appliedDate && toDay(p.appliedDate) > t));
  const st = order.status || { state: 'open', holdPeriods: [] };
  const holdPeriods = (st.holdPeriods || []).filter((h) => toDay(h.from) <= t).map((h) => (h.to && toDay(h.to) > t ? { ...h, to: null } : h));
  let state = st.state || 'open';
  let status = { ...st };
  if ((state === 'cancelled' || state === 'merged') && st.date && toDay(st.date) > t) {
    state = 'open';
    delete status.reason; delete status.mergedInto; delete status.date;
  }
  if (state === 'open' || state === 'on_hold') state = holdPeriods.some((h) => !h.to) ? 'on_hold' : 'open';
  let lastChangeDate = order.lastChangeDate;
  if (lastChangeDate && toDay(lastChangeDate) > t) {
    const dates = [order.receivedDate, ...Object.values(steps).map((r) => r.done), ...permits.map((p) => p.appliedDate)].filter(Boolean).map(toDay);
    lastChangeDate = dates.length ? fromDay(Math.max(...dates)) : null;
  }
  return { ...order, steps, permits, status: { ...status, state, holdPeriods }, lastChangeDate };
}

export function evaluateAll(rules, orders, today, settings) {
  return orders.filter((o) => !o.deleted).map((order) => ({ order, ev: evaluate(rules, order, today, settings) }));
}

function firstPermitStart(order) {
  const s = (order.permits || []).filter((p) => p.startDate).map((p) => toDay(p.startDate));
  return s.length ? fromDay(Math.min(...s)) : null;
}

/**
 * The day an order was completed: when its documents were submitted to SEC, or, if that
 * step was marked Not applicable, the latest date any of its steps was done.
 */
export function completedOn(ev) {
  if (ev.status !== 'completed') return null;
  const docs = ev.steps.find((s) => s.key === 'documents_submitted');
  if (docs && docs.doneDate) return docs.doneDate;
  const dates = ev.steps.filter((s) => s.doneDate).map((s) => toDay(s.doneDate));
  return dates.length ? fromDay(Math.max(...dates)) : null;
}

function maxSeverity(alerts) {
  return alerts.reduce((m, a) => (SEVERITY_RANK[a.severity] > SEVERITY_RANK[m || ''] || !m ? a.severity : m), null);
}
function sevRank(s) { return SEVERITY_RANK[s] || 0; }

// The date a step started waiting: the latest completion date of its dependencies,
// the tasreeh start date for gated field steps, or the received date for the first step.
export function waitingSince(order, ev, stepId) {
  const s = ev.steps.find((x) => x.id === stepId);
  const dates = s.deps.map((d) => ev.steps.find((x) => x.id === d)).filter((x) => x && x.doneDate).map((x) => toDay(x.doneDate));
  if (['excavation', 'poles'].includes(s.key) && order.category !== 'emergency') {
    const start = firstPermitStart(order);
    if (start) dates.push(toDay(start));
  }
  if (dates.length) return fromDay(Math.max(...dates));
  return order.receivedDate || null;
}
export function daysWaiting(order, ev, stepId, today) {
  const since = waitingSince(order, ev, stepId);
  if (!since || toDay(since) > toDay(today)) return 0;
  return activeDays(since, today, (order.status && order.status.holdPeriods) || []);
}

// ---------------- Pipeline ----------------
export function pipeline(rules, orders, today, settings) {
  const all = evaluateAll(rules, orders, today, settings).filter((x) => ACTIVE.has(x.ev.status));
  const steps = {};
  for (const key of Object.keys(rules.steps)) steps[key] = { ready: 0, total: 0 };
  const buckets = { kashfeyaNotDone: 0, tasreehNotApplied: 0, appliedNoDates: 0, startsInFuture: 0, expiredWorkOpen: 0, lateStart: 0 };
  for (const { order, ev } of all) {
    const keys = new Set(ev.steps.map((s) => s.key));
    for (const key of keys) {
      const inst = ev.steps.filter((s) => s.key === key);
      if (inst.some((s) => s.state === 'ready')) steps[key].ready++;
      if (inst.some((s) => s.state === 'ready' || s.state === 'locked')) steps[key].total++;
    }
    const get = (k) => ev.steps.find((s) => s.key === k);
    const k = get('kashfeya');
    if (k && k.state !== 'done' && k.state !== 'na') buckets.kashfeyaNotDone++;
    const t = get('tasreeh_applied');
    if (t) {
      const tClosed = t.state === 'done' || t.state === 'na';
      if (!tClosed) buckets.tasreehNotApplied++;
      const start = firstPermitStart(order);
      // Not applicable means no tasreeh is needed, so it is not waiting for dates.
      if (t.state === 'done' && !start) buckets.appliedNoDates++;
      const gated = ev.steps.find((s) => ['excavation', 'poles'].includes(s.key));
      if (start && toDay(start) > toDay(today) && gated && gated.state !== 'done' && gated.state !== 'na') buckets.startsInFuture++;
    }
    if (ev.alerts.some((a) => a.code === 'no_active_tasreeh')) buckets.expiredWorkOpen++;
    if (ev.alerts.some((a) => a.code === 'late_start')) buckets.lateStart++;
  }
  return { activeCount: all.length, steps, buckets };
}

export function startsByDay(rules, orders, today, days = 7, settings) {
  const all = evaluateAll(rules, orders, today, settings).filter((x) => ACTIVE.has(x.ev.status));
  const t0 = toDay(today);
  const out = [];
  for (let i = 0; i < days; i++) out.push({ date: fromDay(t0 + i), count: 0, orders: [] });
  for (const { order, ev } of all) {
    const gated = ev.steps.find((s) => ['excavation', 'poles'].includes(s.key));
    if (!gated || gated.state === 'done' || gated.state === 'na') continue;
    const start = firstPermitStart(order);
    if (!start) continue;
    const i = toDay(start) - t0;
    if (i >= 0 && i < days) { out[i].count++; out[i].orders.push(order.id); }
  }
  return out;
}

// ---------------- Board ----------------
function cardFor(order, ev, today) {
  const nextId = ev.next[0] || (ev.steps.find((s) => s.state !== 'done' && s.state !== 'na') || {}).id || null;
  const sev = maxSeverity(ev.alerts);
  return {
    id: order.id,
    woNumber: order.woNumber,
    type: order.type,
    district: order.district || null,
    contractor: order.contractor || null,
    next: nextId,
    nextKey: nextId ? ev.steps.find((s) => s.id === nextId).key : null,
    daysWaiting: nextId ? daysWaiting(order, ev, nextId, today) : 0,
    startsOn: ev.stage === 'starting' ? firstPermitStart(order) : null,
    severity: sev,
    onHold: ev.status === 'on_hold',
  };
}
function cardSort(a, b) {
  return sevRank(b.severity) - sevRank(a.severity) || b.daysWaiting - a.daysWaiting || cmpStr(a.woNumber, b.woNumber);
}
export function board(rules, orders, today, settings) {
  const all = evaluateAll(rules, orders, today, settings).filter((x) => ACTIVE.has(x.ev.status));
  return rules.stages.map((st) => ({
    stage: st.key,
    cards: all.filter((x) => x.ev.stage === st.key).map((x) => cardFor(x.order, x.ev, today)).sort(cardSort),
  }));
}

// ---------------- Follow-up ----------------
export const ACTION_GROUPS = [
  ['start_field_work', ['excavation', 'poles']],
  ['close_trench', ['concrete', 'compaction', 'sub_base']],
  ['surface', ['asphalt', 'asphalt_stage_1', 'asphalt_stage_2', 'tiles']],
  ['cable_tape', ['cable_installed', 'warning_tape']],
  ['overhead', ['stringing', 'stay_earthing', 'line_energized']],
  ['transformer', ['foundation', 'transformer_installed', 'earthing', 'transformer_energized']],
  ['meter_closeout', ['meter_installed', 'breaker_meter_changed', 'meter_relocated', 'meter_on', 'form_190', 'form_200', 'certificate', 'documents_submitted']],
  ['paperwork', ['kashfeya', 'tasreeh_applied']],
  ['upcoming', []],
];
const GROUP_OF = Object.fromEntries(ACTION_GROUPS.flatMap(([g, keys]) => keys.map((k) => [k, g])));
const GROUP_ORDER = Object.fromEntries(ACTION_GROUPS.map(([g], i) => [g, i]));
export const UNASSIGNED = '(not assigned)';

export function followUp(rules, orders, today, settings) {
  const all = evaluateAll(rules, orders, today, settings).filter((x) => x.ev.status === 'open');
  const byCon = new Map();
  for (const { order, ev } of all) {
    const con = order.contractor || UNASSIGNED;
    if (!byCon.has(con)) byCon.set(con, { contractor: con, orders: 0, late: 0, groups: new Map() });
    const c = byCon.get(con);
    c.orders++;
    if (ev.alerts.length) c.late++;
    const sev = maxSeverity(ev.alerts);
    const ready = ev.steps.filter((s) => s.state === 'ready');
    const perGroup = new Map();
    if (ready.length) {
      for (const s of ready) {
        const g = GROUP_OF[s.key];
        if (!perGroup.has(g)) perGroup.set(g, []);
        perGroup.get(g).push(s.id);
      }
    } else {
      perGroup.set('upcoming', []);
    }
    for (const [g, stepIds] of perGroup) {
      if (!c.groups.has(g)) c.groups.set(g, { group: g, severity: null, items: [] });
      const grp = c.groups.get(g);
      const days = stepIds.length ? Math.max(...stepIds.map((id) => daysWaiting(order, ev, id, today))) : 0;
      grp.items.push({ id: order.id, woNumber: order.woNumber, steps: stepIds, daysWaiting: days, severity: sev, startsOn: g === 'upcoming' ? firstPermitStart(order) : null });
      if (sevRank(sev) > sevRank(grp.severity)) grp.severity = sev;
    }
  }
  const out = [...byCon.values()].map((c) => ({
    contractor: c.contractor,
    orders: c.orders,
    late: c.late,
    groups: [...c.groups.values()]
      .map((g) => ({ ...g, items: g.items.sort(cardSort) }))
      .sort((a, b) => sevRank(b.severity) - sevRank(a.severity) || GROUP_ORDER[a.group] - GROUP_ORDER[b.group]),
  }));
  out.sort((a, b) => (a.contractor === UNASSIGNED) - (b.contractor === UNASSIGNED) || b.orders - a.orders || cmpStr(a.contractor, b.contractor));
  return out;
}

// ---------------- Search ----------------
export function normalizeText(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/[ً-ٰٟـ]/g, '')
    .replace(/[آأإٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06F0))
    .trim();
}
const compact = (s) => s.replace(/[\s\-\/_.]/g, '');
const STATUS_RANK = { open: 0, on_hold: 0, completed: 1, cancelled: 2, merged: 2 };

export const SEARCH_KINDS = ['workOrder', 'tasreeh', 'meter', 'network', 'place', 'contractor', 'note'];

export function search(rules, orders, query, today, settings) {
  const q = normalizeText(query);
  if (!q) return [];
  const qc = compact(q);
  const results = [];
  for (const { order, ev } of evaluateAll(rules, orders, today, settings)) {
    const fields = [['workOrder', order.woNumber]];
    for (const p of order.permits || []) fields.push(['tasreeh', p.number]);
    for (const m of order.meters || []) { fields.push(['meter', m.number]); fields.push(['meter', m.oldNumber]); }
    fields.push(['network', order.networkRef], ['place', order.district], ['place', order.street], ['contractor', order.contractor], ['note', order.notes]);
    const seen = new Set();
    for (const [kind, raw] of fields) {
      if (!raw) continue;
      const v = normalizeText(raw);
      let at = v.indexOf(q);
      if (at < 0 && qc.length >= 3) at = compact(v).indexOf(qc) >= 0 ? compact(v).indexOf(qc) : -1;
      if (at < 0) continue;
      const k = `${kind}|${raw}`;
      if (seen.has(k)) continue;
      seen.add(k);
      results.push({ id: order.id, woNumber: order.woNumber, kind, value: raw, prefix: at === 0, status: ev.status });
    }
  }
  results.sort((a, b) => (b.prefix - a.prefix) || STATUS_RANK[a.status] - STATUS_RANK[b.status] || cmpStr(a.woNumber, b.woNumber) || cmpStr(a.kind, b.kind) || cmpStr(a.value, b.value));
  return results;
}

// ---------------- Filters ----------------
function segKind(s) {
  if (s.base === 'soil') return 'soil';
  return s.width >= 80 ? 'asphalt_80' : 'asphalt_40';
}
function tasreehState(order, today, ev) {
  const pkgs = ev.steps.map((s) => s.package);
  if (!pkgs.includes('tasreeh')) return 'not_needed';
  const applied = ev.steps.find((s) => s.key === 'tasreeh_applied');
  if (applied && applied.state === 'na') return 'not_needed';
  const permits = (order.permits || []).filter((p) => p.startDate && p.endDate);
  if (!permits.length) return 'none';
  const t = toDay(today);
  const cur = currentPermit(order, today);
  if (cur) return ev.alerts.some((a) => a.code === 'next_tasreeh_needed') ? 'ending' : 'active';
  if (permits.some((p) => toDay(p.startDate) > t)) return 'future';
  return 'expired';
}
function stepMatches(ev, cond) {
  const inst = ev.steps.filter((s) => s.key === cond.step);
  if (!inst.length) return false;
  if (cond.state === 'ready') return inst.some((s) => s.state === 'ready');
  if (cond.state === 'not_done') return inst.some((s) => s.state !== 'done' && s.state !== 'na');
  if (cond.state === 'done') {
    if (!inst.every((s) => s.state === 'done' || s.state === 'na')) return false;
    if (!cond.from && !cond.to) return true;
    const dates = inst.filter((s) => s.doneDate).map((s) => toDay(s.doneDate));
    if (!dates.length) return false;
    const last = Math.max(...dates);
    return (!cond.from || last >= toDay(cond.from)) && (!cond.to || last <= toDay(cond.to));
  }
  throw new Error(`Unknown step state ${cond.state}`);
}
const QUICK = {
  needs_attention: (o, ev) => ev.alerts.length > 0,
  late_start: (o, ev) => ev.alerts.some((a) => a.code === 'late_start'),
  tasreeh_ending: (o, ev) => ev.alerts.some((a) => a.code === 'next_tasreeh_needed'),
  expired: (o, ev) => ev.alerts.some((a) => a.code === 'no_active_tasreeh'),
  emergency: (o) => o.category === 'emergency',
  on_hold: (o, ev) => ev.status === 'on_hold',
  received_today: (o, ev, today) => o.receivedDate === today,
};
export const QUICK_FILTERS = Object.keys(QUICK);

export function filterOrders(rules, orders, today, criteria = {}, settings) {
  const c = criteria;
  const pool = c.includeDeleted ? orders.map((order) => ({ order, ev: evaluate(rules, order, today, settings) })) : evaluateAll(rules, orders, today, settings);
  const inList = (list, v) => !list || !list.length || list.includes(v);
  const out = pool.filter(({ order, ev }) => {
    if (!inList(c.status, ev.status)) return false;
    if (!inList(c.categories, order.category)) return false;
    if (!inList(c.types, order.type)) return false;
    if (c.contractors && c.contractors.length && !c.contractors.includes(order.contractor || UNASSIGNED)) return false;
    if (!inList(c.districts, order.district)) return false;
    if (c.voltages && c.voltages.length && !(order.cableRuns || []).some((r) => c.voltages.includes(r.voltage))) return false;
    if (c.cableSizes && c.cableSizes.length && !(order.cableRuns || []).some((r) => c.cableSizes.includes(r.sizeMm2))) return false;
    if (c.surfaces && c.surfaces.length) {
      const kinds = new Set((order.segments || []).map(segKind));
      if ((order.segments || []).some((s) => s.tiled)) kinds.add('tiled');
      if (!orderPackages(rules, order).includes('civil')) kinds.add('no_digging');
      if (!c.surfaces.some((s) => kinds.has(s))) return false;
    }
    if (c.received) {
      if (!order.receivedDate) return false;
      if (c.received.from && toDay(order.receivedDate) < toDay(c.received.from)) return false;
      if (c.received.to && toDay(order.receivedDate) > toDay(c.received.to)) return false;
    }
    if (c.tasreeh && c.tasreeh.length && !c.tasreeh.includes(tasreehState(order, today, ev))) return false;
    for (const cond of c.steps || []) if (!stepMatches(ev, cond)) return false;
    for (const q of c.quick || []) if (!QUICK[q](order, ev, today)) return false;
    return true;
  });
  out.sort((a, b) => toDay(b.order.receivedDate || '1970-01-01') - toDay(a.order.receivedDate || '1970-01-01') || cmpStr(a.order.woNumber, b.order.woNumber));
  return out.map((x) => x.order.id);
}

// ---------------- Reports ----------------
export function weekRange(date) {
  // Saturday to Friday containing `date`. 1970-01-01 was a Thursday.
  const d = toDay(date);
  const dow = ((d + 4) % 7 + 7) % 7; // 0 = Sunday ... 6 = Saturday
  const sinceSat = (dow + 1) % 7;
  return { from: fromDay(d - sinceSat), to: fromDay(d - sinceSat + 6) };
}
export function monthRange(date) {
  const [y, m] = date.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const mm = String(m).padStart(2, '0');
  return { from: `${y}-${mm}-01`, to: `${y}-${mm}-${String(last).padStart(2, '0')}` };
}

function inRange(date, from, to) {
  return !!date && toDay(date) >= toDay(from) && toDay(date) <= toDay(to);
}

export function report(rules, orders, from, to, today = to, settings) {
  const all = evaluateAll(rules, orders.map((o) => snapshot(o, today)).filter(Boolean), today, settings);
  const active = all.filter((x) => ACTIVE.has(x.ev.status));
  const docsDone = completedOn;

  const received = all.filter((x) => inRange(x.order.receivedDate, from, to)).length;
  let stepsCompleted = 0;
  const touched = new Set();
  const stepsByKey = {};
  for (const { order, ev } of all) {
    for (const s of ev.steps) {
      if (s.state === 'done' && inRange(s.doneDate, from, to)) {
        stepsCompleted++;
        touched.add(order.id);
        stepsByKey[s.key] = (stepsByKey[s.key] || 0) + 1;
      }
    }
  }
  const completed = all.filter((x) => x.ev.status === 'completed' && inRange(docsDone(x.ev), from, to));

  const attentionByCode = {};
  for (const { ev } of active) for (const code of new Set(ev.alerts.map((a) => a.code))) attentionByCode[code] = (attentionByCode[code] || 0) + 1;
  const byStage = Object.fromEntries(rules.stages.map((st) => [st.key, 0]));
  for (const { ev } of active) if (ev.stage) byStage[ev.stage]++;

  const contractorsMap = new Map();
  const conOf = (o) => o.contractor || UNASSIGNED;
  const ensure = (name) => {
    if (!contractorsMap.has(name)) contractorsMap.set(name, { contractor: name, open: 0, completedInPeriod: 0, lateStarts: 0, finishDays: [] });
    return contractorsMap.get(name);
  };
  for (const { order, ev } of all) {
    const c = ensure(conOf(order));
    if (ACTIVE.has(ev.status)) c.open++;
    if (ev.status === 'open' && ev.alerts.some((a) => a.code === 'late_start')) c.lateStarts++;
    if (ev.status === 'completed') {
      const d = docsDone(ev);
      if (inRange(d, from, to)) c.completedInPeriod++;
      if (d && order.receivedDate) c.finishDays.push(activeDays(order.receivedDate, d, (order.status && order.status.holdPeriods) || []));
    }
  }
  const contractors = [...contractorsMap.values()]
    .filter((c) => c.open || c.completedInPeriod || c.lateStarts)
    .map(({ finishDays, ...c }) => {
      const total = finishDays.reduce((a, b) => a + b, 0);
      // finished / finishDaysTotal let a report combine contractors into an exact average.
      return { ...c, avgDaysToFinish: finishDays.length ? Math.round(total / finishDays.length) : null, finished: finishDays.length, finishDaysTotal: total };
    })
    .sort((a, b) => (a.contractor === UNASSIGNED) - (b.contractor === UNASSIGNED) || b.open - a.open || cmpStr(a.contractor, b.contractor));

  const quantities = { cableLV: 0, cableMV: 0, asphalt40: 0, asphalt80: 0, soil: 0, tiles: 0 };
  for (const { order, ev } of all) {
    const done = (id) => { const s = ev.steps.find((x) => x.id === id); return s && s.state === 'done' && inRange(s.doneDate, from, to); };
    if (done('cable_installed')) for (const r of order.cableRuns || []) quantities[r.voltage === 'MV' ? 'cableMV' : 'cableLV'] += r.lengthM || 0; // length is optional
    for (const seg of order.segments || []) {
      if (seg.base === 'soil' && done(`compaction@${seg.id}`)) quantities.soil += seg.lengthM;
      if (seg.base === 'asphalt' && seg.width < 80 && done(`asphalt@${seg.id}`)) quantities.asphalt40 += seg.lengthM;
      if (seg.base === 'asphalt' && seg.width >= 80 && done(`asphalt_stage_2@${seg.id}`)) quantities.asphalt80 += seg.lengthM;
      if (seg.tiled && done(`tiles@${seg.id}`)) quantities.tiles += seg.lengthM;
    }
  }

  const delays = active
    .filter((x) => x.ev.status === 'open' && x.ev.alerts.length)
    .map(({ order, ev }) => {
      const top = [...ev.alerts].sort((a, b) => sevRank(b.severity) - sevRank(a.severity) || (b.days || 0) - (a.days || 0))[0];
      return { id: order.id, woNumber: order.woNumber, type: order.type, district: order.district || null, contractor: order.contractor || null, code: top.code, days: top.days ?? null, severity: top.severity };
    })
    .sort((a, b) => sevRank(b.severity) - sevRank(a.severity) || (b.days || 0) - (a.days || 0) || cmpStr(a.woNumber, b.woNumber));

  const series = [];
  for (let d = toDay(from); d <= toDay(to); d++) {
    const day = fromDay(d);
    series.push({
      date: day,
      received: all.filter((x) => x.order.receivedDate === day).length,
      completed: all.filter((x) => x.ev.status === 'completed' && docsDone(x.ev) === day).length,
    });
  }

  return {
    from, to,
    received,
    stepsCompleted,
    ordersTouched: touched.size,
    completed: completed.length,
    completedList: completed.map(({ order, ev }) => ({ id: order.id, woNumber: order.woNumber, type: order.type, days: activeDays(order.receivedDate, docsDone(ev), (order.status && order.status.holdPeriods) || []) }))
      .sort((a, b) => cmpStr(a.woNumber, b.woNumber)),
    open: active.length,
    attention: active.filter((x) => x.ev.alerts.length).length,
    attentionByCode,
    byStage,
    stepsByKey,
    contractors,
    quantities,
    delays,
    series,
  };
}

export function dailyReport(rules, orders, date, settings) {
  const r = report(rules, orders, date, date, date, settings);
  const prev = fromDay(toDay(date) - 1);
  const p = report(rules, orders, prev, prev, prev, settings);
  const trendFrom = fromDay(toDay(date) - 13);
  const trend = report(rules, orders, trendFrom, date, date, settings).series;
  return { ...r, receivedPrev: p.received, completedPrev: p.completed, trend };
}
