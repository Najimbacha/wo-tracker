// Demo work orders for trying the app's screens: every type, status, stage and alert.
// Every order is built by running the real actions (markDone, putOnHold, merge ...),
// so the data always obeys the rules. Same seed → same data.
//
// NEVER load this into the real database: nothing there can be deleted permanently.
// The app shows it only in Demo mode, which keeps it on the device and never syncs.
//
// Write the asset: node tools/sample/demo.mjs
import { writeFileSync } from 'node:fs';
import { toDay, fromDay, evaluate } from '../rules-check/engine.mjs';
import * as A from '../rules-check/actions.mjs';

export const DEMO_TODAY = '2026-10-11';

const CONTRACTORS = [
  'Al-Bina Contracting', 'Rawabi Electric', 'Nasr Al-Jazeera', 'Masar Al-Taqa', 'Dar Al-Itqan', 'Sahm Al-Sharq',
  'Afaq Engineering', 'Al-Wafa Electrical', 'Bawabat Al-Noor', 'Qimam Contracting', 'Al-Falak Power', 'Tamkeen Works',
];
// Real Taif districts. The same district is sometimes typed in English and in Arabic, as on real orders.
const DISTRICTS = ['Al Faisaliyah', 'Al Hawiyah', 'Al Qumariyah', 'Al Wurud', 'Al Sadad', 'Nakhab', 'Al Sharafiyah', 'Al Rayyan', 'Shihar', 'حي الجودية', 'حي الحوية', 'العرفاء'];
const STREETS = ['King Fahd Rd', 'Olaya St', 'Anas Bin Malik Rd', 'Prince Turki St', 'Takhassusi St', 'شارع الأمير سلطان', 'Imam Saud Rd', 'Abu Bakr Rd'];
const NOTES = [
  'Customer asked to finish before school starts.',
  'Close to a gas line, dig by hand near the corner.',
  'المقاول طلب تأجيل الحفر بسبب مدرسة قريبة',
  'Baladiya inspector visits on Sundays.',
  'Second meter for the annex.',
  'يوجد كابل اتصالات قريب من مسار الحفر',
  null, null, null, null,
];

// Small seeded random generator (mulberry32), so the data is the same every run.
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// volume: how many ordinary orders to add over the last `spanDays` days. The default
// (14 over 85 days) is the Demo mode file; a large volume is for report previews and speed tests.
export function buildDemo(rules, today = DEMO_TODAY, seed = 1448, { volume = 14, spanDays = 85 } = {}) {
  const rand = rng(seed);
  const pick = (list) => list[Math.floor(rand() * list.length)];
  const int = (lo, hi) => lo + Math.floor(rand() * (hi - lo + 1));
  const ago = (n) => fromDay(toDay(today) - n);
  const usedNumbers = new Set();
  const uniqueNumber = (make) => { let n; do n = make(); while (usedNumbers.has(n)); usedNumbers.add(n); return n; };
  let permitSeq = 0;

  const orders = [];
  const byRef = {};

  function create(sc, index) {
    const id = `demo-${String(index + 1).padStart(3, '0')}`;
    const type = rules.types[sc.type];
    const pkgs = [...type.packages, ...(sc.excavation ? rules.optionalExcavationPackages : [])];
    const o = {
      id,
      type: sc.type,
      category: sc.cat || 'extension',
      woNumber: sc.cat === 'emergency' ? uniqueNumber(() => `T-${int(10000, 99999)}`) : uniqueNumber(() => `4417${int(10000, 99999)}`),
      receivedDate: ago(sc.recv),
      needsExcavation: !!sc.excavation,
      contractor: sc.contractor === null ? null : sc.contractor || pick(CONTRACTORS),
      district: pick(DISTRICTS),
      street: rand() < 0.7 ? pick(STREETS) : null,
      networkRef: rand() < 0.6 ? `SS-${pick(['ULY', 'MLQ', 'NKH', 'YSM', 'HTN'])} / F${int(1, 24)} / TR-${int(1000, 9999)}` : null,
      notes: sc.note !== undefined ? sc.note : pick(NOTES),
      segments: [],
      meters: [],
      cableRuns: [],
      permits: [],
      steps: {},
      status: { state: 'open', holdPeriods: [] },
      lastChangeDate: ago(sc.recv),
    };
    if (pkgs.includes('restoration')) {
      const kinds = sc.segments || Array.from({ length: int(1, 2) }, () => pick(['soil', 'asphalt_40', 'asphalt_40', 'asphalt_80']));
      o.segments = kinds.map((k, i) => {
        const tiled = k.endsWith('+tiles');
        const kind = k.replace('+tiles', '');
        return { id: `${id}-s${i + 1}`, base: kind === 'soil' ? 'soil' : 'asphalt', width: kind === 'asphalt_80' ? 80 : 40, lengthM: int(6, 120), tiled };
      });
    }
    if (pkgs.includes('civil')) {
      const mv = ['transformer'].some((p) => pkgs.includes(p));
      o.cableRuns = [{ sizeMm2: mv ? pick([300, 500]) : pick([70, 185, 185, 300]), voltage: mv ? 'MV' : 'LV', lengthM: int(20, 260) }];
      if (mv && rand() < 0.5) o.cableRuns.push({ sizeMm2: 185, voltage: 'LV', lengthM: int(15, 80) });
    }
    if (pkgs.some((p) => rules.packages[p].scope === 'meter')) {
      const n = sc.meters || 1;
      const old = pkgs.includes('meter_change') || pkgs.includes('meter_relocate');
      o.meters = Array.from({ length: n }, (_, i) => {
        const m = { id: `${id}-m${i + 1}`, number: uniqueNumber(() => String(int(10000000, 99999999))) };
        if (old) m.oldNumber = uniqueNumber(() => String(int(10000000, 99999999)));
        return m;
      });
    }
    return o;
  }

  const must = (r, what) => {
    if (!r.ok) throw new Error(`${what}: ${JSON.stringify(r.errors)}`);
    return r;
  };

  // Marks the next ready steps one at a time, dated evenly from `fromAgo` to `toAgo`.
  // `until` is a number of steps, a step key (all its instances), or 'all'.
  function run(o, until, fromAgo, toAgo, pace = null) {
    const sim = () => {
      let c = structuredClone(o), n = 0;
      for (;;) {
        if (typeof until === 'number' && n >= until) return n;
        const ev = evaluate(rules, c, '2100-01-01');
        if (typeof until === 'string' && until !== 'all' && ev.steps.filter((s) => s.key === until).every((s) => s.state === 'done' || s.state === 'na')) return n;
        const ready = ev.steps.find((s) => s.state === 'ready');
        if (!ready) return n;
        c.steps[ready.id] = { done: '2100-01-01' };
        n++;
      }
    };
    let count = sim();
    if (pace) {
      // Steady pace: the whole order would take `pace.duration` days; mark what fits until today.
      const total = (() => { const u = until; until = 'all'; const n = sim(); until = u; return n; })();
      const step = pace.duration / Math.max(total, 1);
      count = Math.min(total, Math.floor(fromAgo / step) + 1);
      toAgo = Math.round(fromAgo - (count - 1) * step);
      until = 'all';
    }
    let last = null;
    for (let i = 0; i < count; i++) {
      const planned = count === 1 ? toAgo : Math.round(fromAgo - ((fromAgo - toAgo) * i) / (count - 1));
      const ev = evaluate(rules, o, today);
      const ready = ev.steps.find((s) => s.state === 'ready') ||
        ev.steps.find((s) => s.state === 'locked' && s.reasons.every((r) => r.code === 'tasreeh_starts'));
      if (!ready) throw new Error(`${o.id}: nothing ready (${i}/${count})`);
      let date = ago(Math.max(planned, 0));
      if (last && toDay(date) < toDay(last)) date = last;
      const recs = ready.deps.map((d) => o.steps[d] && o.steps[d].done).filter(Boolean);
      for (const d of recs) if (toDay(d) > toDay(date)) date = d;
      const start = o.permits.map((p) => p.startDate).filter(Boolean).sort()[0];
      if (ready.gate === 'tasreehStarted' && o.category !== 'emergency' && start && toDay(start) > toDay(date)) date = start;
      if (toDay(date) > toDay(today)) throw new Error(`${o.id}: ${ready.id} would be in the future`);
      o = must(A.markDone(rules, o, ready.id, date, today), `${o.id} ${ready.id} ${date}`).order;
      last = date;
    }
    return o;
  }

  function permit(o, appliedAgo, startAgo, endAgo) {
    permitSeq++;
    const p = { number: `BL-48-${String(10400 + permitSeq * 7)}` };
    if (appliedAgo !== null) p.appliedDate = ago(appliedAgo);
    if (startAgo !== null) { p.startDate = ago(startAgo); p.endDate = ago(endAgo); }
    return { ...o, permits: [...o.permits, p] };
  }

  // Each scenario: type, category, days since received, then steps applied in order.
  //   ['run', until, fromAgo, toAgo]      mark steps (see run)
  //   ['permit', appliedAgo, startAgo, endAgo]   negative = days from now
  //   ['na', stepId suffix, reason, ago]  ['hold', fromAgo, reason, toAgo|null, reviewInDays]
  //   ['cancel', reason, daysAgo]  ['merge', ref, carry, daysAgo]  ['delete']
  const S = [
    // Kashfeya and tasreeh
    { type: '402', recv: 0 },
    { type: '804', recv: 1, note: null },
    { type: '803', recv: 3, ops: [['run', 'kashfeya', 2, 2]] },
    { type: '804', recv: 6, ops: [['run', 'tasreeh_applied', 5, 3]] },
    { type: '402', recv: 7, ops: [['run', 'tasreeh_applied', 6, 4], ['permit', 4, -3, -33]] },
    { type: '403', recv: 9, ops: [['run', 'tasreeh_applied', 8, 6], ['permit', 6, -1, -30]] },
    { type: '802', recv: 5, ops: [['run', 'tasreeh_applied', 4, 3], ['permit', 3, -5, -35]] },
    { type: '409', recv: 9, excavation: true, ops: [['run', 'tasreeh_applied', 8, 6], ['permit', 6, -2, -20]] },
    { type: '403', recv: 40, ops: [['run', 'tasreeh_applied', 22, 20]] }, // stalled, no tasreeh dates
    // Late starts
    { type: '402', recv: 12, ops: [['run', 'tasreeh_applied', 11, 7], ['permit', 7, 2, -28]] },
    { type: '802', recv: 20, ops: [['run', 'tasreeh_applied', 18, 12], ['permit', 12, 8, -22]] },
    { type: '803', recv: 15, ops: [['run', 'tasreeh_applied', 14, 9], ['permit', 9, 3, -27]] },
    // Field work
    { type: '402', recv: 10, ops: [['run', 'tasreeh_applied', 9, 7], ['permit', 7, 4, -26], ['run', 'cable_installed', 3, 1]] },
    { type: '404', recv: 25, meters: 2, ops: [['run', 'tasreeh_applied', 24, 20], ['permit', 20, 13, -17], ['run', 'warning_tape', 9, 8]] }, // open trench
    { type: '402', recv: 18, segments: ['asphalt_40', 'soil', 'asphalt_80+tiles'], ops: [['run', 'tasreeh_applied', 17, 15], ['permit', 15, 13, -17], ['run', 'warning_tape', 12, 10], ['run', 1, 9, 9]] }, // restoration overdue
    { type: '802', recv: 32, segments: ['asphalt_80', 'asphalt_40'], ops: [['run', 'tasreeh_applied', 31, 29], ['permit', 29, 27, 13], ['permit', 14, 12, -18], ['run', 'warning_tape', 25, 16], ['run', 2, 6, 2]] }, // second tasreeh
    { type: '804', recv: 26, ops: [['run', 'tasreeh_applied', 25, 23], ['permit', 23, 22, -4], ['run', 'warning_tape', 20, 14], ['run', 1, 3, 3]] }, // tasreeh ending
    { type: '402', recv: 40, segments: ['asphalt_40'], ops: [['run', 'tasreeh_applied', 39, 37], ['permit', 37, 35, 5], ['run', 'concrete', 33, 12]] }, // tasreeh expired
    { type: '803', recv: 14, ops: [['run', 'tasreeh_applied', 13, 10], ['permit', 10, 7, -23], ['run', 'poles', 4, 4]] },
    { type: '805', recv: 22, ops: [['run', 'tasreeh_applied', 21, 18], ['permit', 18, 16, -14], ['run', 'stringing', 12, 6], ['run', 'foundation', 2, 2]] },
    { type: '403', recv: 20, ops: [['run', 'tasreeh_applied', 19, 17], ['permit', 17, 15, -15], ['run', 'meter_installed', 13, 5]] }, // meter not on
    // Meter and close-out
    { type: '402', recv: 35, ops: [['run', 'tasreeh_applied', 34, 31], ['permit', 31, 29, -1], ['run', 'meter_on', 28, 2]] },
    { type: '404', recv: 45, meters: 2, ops: [['run', 'tasreeh_applied', 44, 41], ['permit', 41, 39, 9], ['permit', 10, 8, -22], ['run', 'form_200', 37, 2]] },
    { type: '801', recv: 4, ops: [['run', 1, 1, 1]] },
    { type: '801', recv: 2 },
    { type: '401', recv: 3, ops: [['run', 1, 1, 1]] },
    { type: '409', recv: 6, ops: [['run', 2, 4, 1]] },
    { type: '402', recv: 50, ops: [['run', 'tasreeh_applied', 49, 46], ['permit', 46, 44, 14], ['permit', 15, 13, -17], ['run', 'form_200', 42, 3]] },
    { type: '803', recv: 38, ops: [['run', 'tasreeh_applied', 37, 34], ['permit', 34, 32, 2], ['run', 'certificate', 30, 4]] },
    // Completed
    { type: '402', recv: 60, ops: [['run', 'tasreeh_applied', 59, 56], ['permit', 56, 54, 24], ['permit', 25, 23, -7], ['run', 'all', 52, 10]] },
    { type: '801', recv: 12, ops: [['run', 'all', 10, 3]] },
    { type: '401', recv: 7, ops: [['run', 'all', 5, 1]] },
    { type: '803', recv: 55, ops: [['run', 'tasreeh_applied', 54, 51], ['permit', 51, 49, 19], ['run', 'all', 47, 22]] },
    { type: '804', recv: 80, ops: [['run', 'tasreeh_applied', 79, 75], ['permit', 75, 73, 43], ['permit', 44, 42, 12], ['run', 'all', 70, 14]] },
    { type: '409', recv: 20, excavation: true, ops: [['run', 'tasreeh_applied', 19, 16], ['permit', 16, 15, -15], ['run', 'all', 14, 5]] },
    { type: '402', recv: 33, ops: [['run', 'tasreeh_applied', 32, 30], ['permit', 30, 28, -2], ['run', 'all', 27, 0]] }, // completed today
    { type: '802', recv: 46, ops: [['run', 'tasreeh_applied', 45, 43], ['permit', 43, 41, 11], ['run', 'all', 40, 15]] },
    // Emergency
    { type: '402', cat: 'emergency', recv: 3, ops: [['run', 'kashfeya', 3, 3], ['emergencyDig', 2]] }, // dug, no tasreeh yet
    { type: '802', cat: 'emergency', recv: 10, ops: [['run', 'kashfeya', 10, 10], ['emergencyDig', 9], ['run', 'tasreeh_applied', 6, 6], ['permit', 6, 5, -25], ['run', 2, 5, 2]] },
    { type: '803', cat: 'emergency', recv: 1, ops: [['run', 'kashfeya', 1, 1], ['emergencyDig', 0]] },
    { type: '801', cat: 'emergency', recv: 6, ops: [['run', 'all', 5, 1]] },
    // Hold, cancel, merge, delete
    { type: '402', recv: 16, ops: [['run', 'tasreeh_applied', 15, 12], ['permit', 12, 9, -21], ['hold', 6, 'Customer objection', null, 4]] },
    { type: '804', recv: 48, ops: [['run', 'tasreeh_applied', 47, 44], ['permit', 44, 42, 2], ['permit', 3, 1, -29], ['run', 'excavation', 40, 40], ['hold', 38, 'No material', 28], ['run', 'warning_tape', 27, 20], ['run', 2, 10, 4]] },
    { type: '802', recv: 11, ops: [['run', 'kashfeya', 10, 10], ['cancel', 'SEC cancelled: customer withdrew the request', 9]] },
    { ref: 'replacement', type: '402', recv: 8, ops: [['run', 'kashfeya', 7, 7]] },
    { type: '402', recv: 21, ops: [['run', 'tasreeh_applied', 20, 18], ['permit', 18, 16, -14], ['run', 'excavation', 14, 14], ['merge', 'replacement', true, 7]] },
    { type: '803', recv: 2, note: 'Entered twice by mistake', ops: [['delete']] },
    // Not applicable steps, no contractor
    { type: '402', recv: 28, segments: ['soil', 'soil'], ops: [['run', 'tasreeh_applied', 27, 25], ['permit', 25, 23, -7], ['run', 'cable_installed', 21, 18], ['na', 'warning_tape', 'Cable laid in an existing duct', 17], ['run', 1, 12, 12], ['na', 'compaction@2', 'Segment inside customer yard, customer restores', 11]] },
    { type: '802', recv: 4, contractor: null, ops: [['run', 'kashfeya', 3, 3]] },
  ];

  // Ordinary orders spread over the last 3 months, for realistic report numbers.
  const everyday = ['402', '402', '402', '801', '801', '401', '803', '802', '403', '409'];
  for (let i = 0; i < volume; i++) {
    const type = everyday[i % everyday.length];
    if (volume > 14) { S.push(steadyOrder(type)); continue; }
    const recv = int(1, spanDays);
    const sc = { type, recv, ops: [] };
    const hasTasreeh = rules.types[type].packages.includes('tasreeh');
    if (hasTasreeh && recv > 6) {
      const applied = recv - 2;
      const start = applied - 2;
      const end = start - 30;
      sc.ops.push(['run', 'tasreeh_applied', recv - 1, applied], ['permit', applied, start, end]);
      if (start > 1) sc.ops.push(recv > 45 ? ['run', 'all', start, Math.max(start - 35, 0)] : ['run', int(1, 4), start, Math.max(start - 8, 0)]);
    } else if (!hasTasreeh) {
      sc.ops.push(recv > 10 ? ['run', 'all', recv - 1, Math.max(recv - 9, 0)] : ['run', int(0, 2), recv, 0]);
    }
    S.push(sc);
  }

  // High-volume orders that move like real work: most finish in 2-5 weeks, a few fall behind.
  function steadyOrder(type) {
    const recv = int(0, spanDays);
    const sc = { type, recv, ops: [] };
    const behind = rand() < 0.04;
    if (rules.types[type].packages.includes('tasreeh')) {
      if (recv < 3) return sc;
      const applied = recv - int(1, 2);
      const start = Math.max(applied - int(1, 3), 0);
      sc.ops.push(['run', 'tasreeh_applied', recv - 1, applied], ['permit', applied, start, start - 35]);
      if (start === 0) return sc;
      if (behind) { if (start > 3) sc.ops.push(['run', int(1, 3), start, start - 2]); }
      else sc.ops.push(['pace', start, int(12, 30)]);
    } else {
      if (recv < 1) return sc;
      if (behind) sc.ops.push(['run', 1, recv, recv]);
      else sc.ops.push(['pace', recv, int(2, 8)]);
    }
    return sc;
  }

  S.forEach((sc, i) => {
    let o = create(sc, i);
    for (const op of sc.ops || []) {
      const [kind, ...a] = op;
      if (kind === 'run') o = run(o, a[0], a[1], a[2]);
      else if (kind === 'pace') o = run(o, 'all', a[0], 0, { duration: a[1] });
      else if (kind === 'permit') o = permit(o, a[0], a[1], a[2]);
      else if (kind === 'emergencyDig') {
        // Emergency work may start before any tasreeh exists.
        const step = rules.types[o.type].packages.includes('overhead') ? 'poles' : 'excavation';
        o = must(A.markDone(rules, o, step, ago(a[0]), today), `${o.id} ${step}`).order;
      } else if (kind === 'na') {
        const stepId = a[0].includes('@') ? `${a[0].split('@')[0]}@${o.id}-s${a[0].split('@')[1]}` : a[0];
        o = must(A.markNA(rules, o, stepId, a[1], ago(a[2])), `${o.id} na`).order;
      } else if (kind === 'hold') {
        o = must(A.putOnHold(rules, o, ago(a[0]), a[1], today, a[3] ? fromDay(toDay(today) + a[3]) : null), `${o.id} hold`).order;
        if (a[2] !== null) o = must(A.resume(rules, o, ago(a[2]), today), `${o.id} resume`).order;
      } else if (kind === 'cancel') o = must(A.cancel(rules, o, a[0], ago(a[1] ?? 0)), `${o.id} cancel`).order;
      else if (kind === 'merge') {
        const target = byRef[a[0]];
        const r = must(A.merge(rules, o, orders[target], 'Replaced by a new work order from SEC', a[1], ago(a[2] ?? 0)), `${o.id} merge`);
        o = r.order;
        orders[target] = r.target;
      } else if (kind === 'delete') o = { ...o, deleted: true };
      else throw new Error(`unknown op ${kind}`);
    }
    if (sc.ref) byRef[sc.ref] = orders.length;
    orders.push(o);
  });
  return orders;
}

/** Moves every date in an order by `days` (Demo mode keeps the data current). */
export function shiftDates(order, days) {
  const sh = (d) => (d ? fromDay(toDay(d) + days) : d);
  const o = structuredClone(order);
  o.receivedDate = sh(o.receivedDate);
  o.lastChangeDate = sh(o.lastChangeDate);
  o.permits = (o.permits || []).map((p) => ({ ...p, appliedDate: sh(p.appliedDate), startDate: sh(p.startDate), endDate: sh(p.endDate) }));
  o.steps = Object.fromEntries(Object.entries(o.steps || {}).map(([k, r]) => [k, r.done ? { ...r, done: sh(r.done) } : { ...r }]));
  if (o.status) o.status = { ...o.status, ...(o.status.date ? { date: sh(o.status.date) } : {}), holdPeriods: (o.status.holdPeriods || []).map((h) => ({ ...h, from: sh(h.from), to: sh(h.to), ...(h.review ? { review: sh(h.review) } : {}) })) };
  return o;
}

export function demoFile(rules) {
  return {
    note: 'Demo data only. Never load into the real database. Dates are for "today" below; Demo mode shifts them to the real date.',
    today: DEMO_TODAY,
    orders: buildDemo(rules),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { readFileSync } = await import('node:fs');
  const rules = JSON.parse(readFileSync(new URL('../../app/assets/rules/rules.json', import.meta.url), 'utf8'));
  const file = demoFile(rules);
  writeFileSync(new URL('../../app/assets/demo/demo_orders.json', import.meta.url), JSON.stringify(file, null, 1) + '\n');
  console.log(`wrote ${file.orders.length} demo orders`);
}
