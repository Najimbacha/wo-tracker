// Reference rules engine. The Dart engine in app/lib/domain mirrors this file;
// both are checked against the same golden fixtures in rules/fixtures.
// Dates are plain 'YYYY-MM-DD' strings in Riyadh local time. Days are calendar days.

const DAY_MS = 86400000;

export function toDay(s) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) throw new Error(`Bad date: ${s}`);
  const [y, m, d] = s.split('-').map(Number);
  const t = Date.UTC(y, m - 1, d);
  const back = new Date(t);
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== m - 1 || back.getUTCDate() !== d) throw new Error(`Bad date: ${s}`);
  return Math.round(t / DAY_MS);
}
export function fromDay(n) {
  return new Date(n * DAY_MS).toISOString().slice(0, 10);
}

// Calendar days from `from` to `to` (to - from), not counting days spent on hold.
// A hold period covers [from, to) ; an open hold (to = null) runs until `to` of the query.
export function activeDays(from, to, holds = []) {
  const a = toDay(from), b = toDay(to);
  if (b <= a) return 0;
  let held = 0;
  for (const h of holds) {
    const hs = Math.max(a, toDay(h.from));
    const he = Math.min(b, h.to ? toDay(h.to) : b);
    if (he > hs) held += he - hs;
  }
  return Math.max(0, b - a - held);
}

export function segmentRecipe(rules, seg) {
  let key;
  if (seg.base === 'soil') key = 'soil';
  else if (seg.base === 'asphalt') key = seg.width >= 80 ? 'asphalt_80' : 'asphalt_40';
  else throw new Error(`Unknown segment base: ${seg.base}`);
  const steps = [...rules.segmentRecipes[key]];
  if (seg.tiled) steps.push(rules.tiledStep);
  return steps;
}

export function orderPackages(rules, order) {
  const type = rules.types[order.type];
  if (!type) throw new Error(`Unknown type: ${order.type}`);
  let pkgs = [...type.packages];
  if (type.optionalExcavation && order.needsExcavation) {
    pkgs = [...rules.optionalExcavationPackages, ...pkgs];
  }
  return pkgs;
}

function meterList(order) {
  return order.meters && order.meters.length ? order.meters : [{ id: 'm1' }];
}

// Builds every step instance for the order with its direct dependencies.
export function generate(rules, order) {
  const pkgs = orderPackages(rules, order);
  const has = new Set(pkgs);
  const emergency = order.category === 'emergency';
  const out = [];
  const byPackage = {};
  const add = (s) => { out.push(s); (byPackage[s.package] ||= []).push(s.id); };

  const resolveEntry = (pkg) => {
    const rulesFor = rules.entryDeps[pkg] || [];
    const rule = rulesFor.find((r) => !r.whenPackage || has.has(r.whenPackage));
    if (!rule) return [];
    let deps = [...rule.deps];
    if (emergency && rule.emergencyDrops) deps = deps.filter((d) => !rule.emergencyDrops.includes(d));
    const ids = [];
    for (const d of deps) {
      if (d === '@restoration') ids.push(...(byPackage.restoration || []));
      else if (d === '@all') ids.push(...out.filter((s) => s.package !== pkg).map((s) => s.id));
      else {
        const found = out.filter((s) => s.key === d && s.scope === 'order');
        if (!found.length) throw new Error(`Entry dependency ${d} of ${pkg} not generated for type ${order.type}`);
        ids.push(...found.map((s) => s.id));
      }
    }
    return ids;
  };

  for (const pkg of pkgs) {
    const def = rules.packages[pkg];
    if (def.scope === 'order') {
      let prev = null;
      def.steps.forEach((key, i) => {
        const deps = i === 0 ? resolveEntry(pkg) : [prev];
        const s = { id: key, key, package: pkg, scope: 'order', instance: null, deps, gate: rules.steps[key].gate || null };
        add(s); prev = s.id;
      });
    } else if (def.scope === 'segment') {
      const entry = resolveEntry(pkg);
      for (const seg of order.segments || []) {
        let prev = null;
        segmentRecipe(rules, seg).forEach((key, i) => {
          const id = `${key}@${seg.id}`;
          add({ id, key, package: pkg, scope: 'segment', instance: seg.id, deps: i === 0 ? [...entry] : [prev], gate: null });
          prev = id;
        });
      }
    } else if (def.scope === 'meter') {
      const entry = resolveEntry(pkg);
      for (const m of meterList(order)) {
        let prev = null;
        def.steps.forEach((key, i) => {
          const id = `${key}@${m.id}`;
          add({ id, key, package: pkg, scope: 'meter', instance: m.id, deps: i === 0 ? [...entry] : [prev], gate: null });
          prev = id;
        });
      }
    } else throw new Error(`Unknown scope ${def.scope}`);
  }
  return out;
}

function rec(order, id) {
  return (order.steps && order.steps[id]) || null;
}
function isClosed(order, id) {
  const r = rec(order, id);
  return !!(r && (r.done || r.na));
}

export function currentPermit(order, today) {
  const t = toDay(today);
  const ps = (order.permits || []).filter((p) => p.startDate && p.endDate && toDay(p.startDate) <= t && t <= toDay(p.endDate));
  ps.sort((a, b) => toDay(b.startDate) - toDay(a.startDate));
  return ps[0] || null;
}
function firstPermitStart(order) {
  const starts = (order.permits || []).filter((p) => p.startDate).map((p) => toDay(p.startDate));
  return starts.length ? fromDay(Math.min(...starts)) : null;
}
// Tasreeh marked Not applicable (e.g. work inside private property): no permit dates
// will ever come, so field work is not held back by them.
function tasreehWaived(order) {
  const r = rec(order, 'tasreeh_applied');
  return !!(r && r.na);
}
function gateOpen(order, today) {
  if (tasreehWaived(order)) return true;
  const s = firstPermitStart(order);
  return !!(s && toDay(s) <= toDay(today));
}

export function evaluate(rules, order, today, settings = {}) {
  const th = { ...rules.alertDefaults, ...(settings.alerts || {}) };
  const steps = generate(rules, order);
  const pkgs = orderPackages(rules, order);
  const emergency = order.category === 'emergency';
  const holds = (order.status && order.status.holdPeriods) || [];

  const evaluated = steps.map((s) => {
    const r = rec(order, s.id);
    const base = { id: s.id, key: s.key, package: s.package, instance: s.instance, deps: s.deps };
    if (r && r.done) return { ...base, state: 'done', doneDate: r.done };
    if (r && r.na) return { ...base, state: 'na', reason: r.reason || '' };
    const lockedBy = s.deps.filter((d) => !isClosed(order, d));
    const reasons = [];
    if (lockedBy.length) reasons.push({ code: 'waiting_for', steps: lockedBy });
    if (s.gate === 'tasreehStarted' && !emergency && !gateOpen(order, today)) {
      const start = firstPermitStart(order);
      reasons.push(start ? { code: 'tasreeh_starts', date: start } : { code: 'no_tasreeh_dates' });
    }
    if (s.key === 'certificate') {
      for (const [pkg, req] of Object.entries(rules.requiredData)) {
        if (pkgs.includes(pkg) && req.blocks === 'certificate' && req.kind === 'segments' && !(order.segments || []).length) {
          reasons.push({ code: 'missing_segments' });
        }
      }
    }
    return reasons.length ? { ...base, state: 'locked', reasons } : { ...base, state: 'ready' };
  });

  const total = evaluated.length;
  const closed = evaluated.filter((e) => e.state === 'done' || e.state === 'na').length;
  const allDone = total > 0 && closed === total;

  const state = (order.status && order.status.state) || 'open';
  let status;
  if (state === 'cancelled' || state === 'merged') status = state;
  else if (allDone) status = 'completed';
  else if (state === 'on_hold') status = 'on_hold';
  else status = 'open';

  let stage = null;
  if (status === 'open' || status === 'on_hold') {
    const first = evaluated.find((e) => e.state !== 'done' && e.state !== 'na');
    if (first) {
      const codes = first.state === 'locked' ? first.reasons.map((r) => r.code) : [];
      if (codes.includes('tasreeh_starts')) stage = 'starting';
      // Applied but no dates from Baladiya yet: still waiting for the tasreeh, not field work.
      else if (codes.includes('no_tasreeh_dates')) stage = 'tasreeh';
      else stage = rules.stages.find((st) => st.packages && st.packages.includes(first.package)).key;
    }
  }

  const alerts = status === 'open' ? computeAlerts(rules, order, today, th, evaluated, pkgs, holds, stage) : [];
  return {
    steps: evaluated,
    progress: { closed, total },
    status,
    stage,
    next: evaluated.filter((e) => e.state === 'ready').map((e) => e.id),
    alerts,
  };
}

function computeAlerts(rules, order, today, th, ev, pkgs, holds, stage) {
  const alerts = [];
  const emergency = order.category === 'emergency';
  const get = (id) => ev.find((e) => e.id === id);
  const days = (from) => activeDays(from, today, holds);

  // Late start: tasreeh started, field work (excavation / poles) not begun.
  if (!emergency) {
    const start = firstPermitStart(order);
    for (const e of ev.filter((x) => ['excavation', 'poles'].includes(x.key))) {
      if (e.state === 'done' || e.state === 'na' || !start || toDay(start) > toDay(today)) continue;
      const d = days(start);
      if (d >= th.lateStartDays) alerts.push({ code: 'late_start', step: e.id, days: d, severity: d >= 5 ? 'critical' : 'warning' });
    }
  }

  // Open trench: excavated, but a segment's first restoration step is not done.
  const exc = get('excavation');
  if (exc && exc.state === 'done' && pkgs.includes('restoration')) {
    const segs = order.segments || [];
    const openSeg = segs.length === 0 || segs.some((s) => {
      const first = ev.find((e) => e.instance === s.id && e.package === 'restoration');
      return first && first.state !== 'done' && first.state !== 'na';
    });
    const d = days(exc.doneDate);
    if (openSeg && d >= th.openTrenchDays) alerts.push({ code: 'open_trench', days: d, severity: 'critical' });
  }

  // Restoration overdue: a segment started but not finished.
  for (const s of order.segments || []) {
    const segSteps = ev.filter((e) => e.instance === s.id && e.package === 'restoration');
    if (!segSteps.length) continue;
    const first = segSteps[0], last = segSteps[segSteps.length - 1];
    if (first.state === 'done' && last.state !== 'done' && last.state !== 'na') {
      const d = days(first.doneDate);
      if (d >= th.restorationOverdueDays) alerts.push({ code: 'restoration_overdue', segment: s.id, days: d, severity: 'warning' });
    }
  }

  // Tasreeh coverage while field work is open.
  const fieldPkgs = ['civil', 'overhead', 'restoration', 'transformer'];
  const fieldOpen = ev.some((e) => fieldPkgs.includes(e.package) && e.state !== 'done' && e.state !== 'na');
  const permits = (order.permits || []).filter((p) => p.startDate && p.endDate);
  if (fieldOpen && permits.length) {
    const t = toDay(today);
    const cur = currentPermit(order, today);
    const firstStart = Math.min(...permits.map((p) => toDay(p.startDate)));
    if (!cur && t > firstStart) {
      const ended = permits.filter((p) => toDay(p.endDate) < t).map((p) => toDay(p.endDate));
      const future = permits.some((p) => toDay(p.startDate) > t);
      alerts.push({ code: 'no_active_tasreeh', since: ended.length ? fromDay(Math.max(...ended) + 1) : null, nextStarts: future, severity: 'critical' });
    } else if (cur) {
      const left = toDay(cur.endDate) - t;
      const hasNext = permits.some((p) => toDay(p.startDate) > toDay(cur.startDate));
      if (left <= th.tasreehEndingDays && !hasNext) alerts.push({ code: 'next_tasreeh_needed', daysLeft: left, severity: 'warning' });
    }
  }

  // Meter installed but not switched on.
  for (const m of order.meters && order.meters.length ? order.meters : [{ id: 'm1' }]) {
    const first = ev.find((e) => e.instance === m.id && ['meter_installed', 'breaker_meter_changed', 'meter_relocated'].includes(e.key));
    const on = get(`meter_on@${m.id}`);
    if (first && on && first.state === 'done' && on.state !== 'done' && on.state !== 'na') {
      const d = days(first.doneDate);
      if (d >= th.meterNotOnDays) alerts.push({ code: 'meter_not_on', meter: m.id, days: d, severity: 'warning' });
    }
  }

  // Emergency work started without a tasreeh entered.
  if (emergency && pkgs.includes('tasreeh')) {
    const fieldStarted = ev.find((e) => (e.key === 'excavation' || e.key === 'poles') && e.state === 'done');
    const ta = get('tasreeh_applied');
    if (fieldStarted && ta && ta.state !== 'done' && ta.state !== 'na') {
      const d = days(fieldStarted.doneDate);
      if (d >= th.tawariTasreehMissingDays) alerts.push({ code: 'tawari_tasreeh_missing', days: d, severity: 'warning' });
    }
  }

  // Stalled: nothing changed for a long time. Not while the next work is simply waiting
  // for a tasreeh start date in the future: nobody can do anything until then.
  if (order.lastChangeDate && stage !== 'starting') {
    const d = days(order.lastChangeDate);
    if (d >= th.stalledDays) alerts.push({ code: 'stalled', days: d, severity: 'warning' });
  }
  return alerts;
}

// Returns error codes; an empty list means the step may be marked done on `date`.
export function validateMarkDone(rules, order, stepId, date, today) {
  const steps = generate(rules, order);
  const s = steps.find((x) => x.id === stepId);
  if (!s) return [{ code: 'unknown_step' }];
  const errors = [];
  if (isClosed(order, stepId)) errors.push({ code: 'already_closed' });
  const open = s.deps.filter((d) => !isClosed(order, d));
  if (open.length) errors.push({ code: 'waiting_for', steps: open });
  if (toDay(date) > toDay(today)) errors.push({ code: 'future_date' });
  if (order.receivedDate && toDay(date) < toDay(order.receivedDate)) errors.push({ code: 'before_received' });
  const depDates = s.deps.map((d) => rec(order, d)).filter((r) => r && r.done).map((r) => toDay(r.done));
  if (depDates.length && toDay(date) < Math.max(...depDates)) errors.push({ code: 'before_previous_step', date: fromDay(Math.max(...depDates)) });
  if (s.gate === 'tasreehStarted' && order.category !== 'emergency' && !tasreehWaived(order)) {
    const start = firstPermitStart(order);
    if (!start) errors.push({ code: 'no_tasreeh_dates' });
    else if (toDay(date) < toDay(start)) errors.push({ code: 'before_tasreeh_start', date: start });
  }
  if (rules.steps[s.key].requires === 'cableRuns' && !(order.cableRuns || []).length) errors.push({ code: 'needs_cable_runs' });
  if (s.key === 'certificate' && orderPackages(rules, order).includes('restoration') && !(order.segments || []).length) errors.push({ code: 'missing_segments' });
  return errors;
}

// Steps that depend (directly or indirectly) on stepId and are currently closed.
// Clearing stepId must also clear these, so the app asks first and lists them.
export function clearImpact(rules, order, stepId) {
  const steps = generate(rules, order);
  const dependents = new Set();
  let grew = true;
  while (grew) {
    grew = false;
    for (const s of steps) {
      if (dependents.has(s.id)) continue;
      if (s.deps.includes(stepId) || s.deps.some((d) => dependents.has(d))) { dependents.add(s.id); grew = true; }
    }
  }
  return steps.filter((s) => dependents.has(s.id) && isClosed(order, s.id)).map((s) => s.id);
}

export function validateOrder(rules, order) {
  const errors = [];
  const cat = rules.categories[order.category];
  if (!cat) errors.push({ code: 'unknown_category' });
  else if (!new RegExp(cat.woNumberPattern).test(order.woNumber || '')) errors.push({ code: 'bad_wo_number' });
  if (!rules.types[order.type]) errors.push({ code: 'unknown_type' });
  const nums = new Set();
  for (const p of order.permits || []) {
    if (p.startDate && p.endDate && toDay(p.endDate) < toDay(p.startDate)) errors.push({ code: 'permit_end_before_start', permit: p.number });
    if (p.appliedDate && p.startDate && toDay(p.startDate) < toDay(p.appliedDate)) errors.push({ code: 'permit_start_before_applied', permit: p.number });
    if (p.number) { if (nums.has(p.number)) errors.push({ code: 'duplicate_permit', permit: p.number }); nums.add(p.number); }
  }
  for (const s of order.segments || []) {
    if (!['soil', 'asphalt'].includes(s.base)) errors.push({ code: 'bad_segment_base', segment: s.id });
    if (![40, 80].includes(s.width)) errors.push({ code: 'bad_segment_width', segment: s.id });
    if (!(s.lengthM > 0)) errors.push({ code: 'bad_segment_length', segment: s.id });
  }
  return errors;
}
