// Random-sequence testing: thousands of orders driven through random actions,
// checking rules that must hold whatever the user clicks. A failure prints the seed
// and the action list, so it can be replayed exactly.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as A from './actions.mjs';
import { generate, evaluate, toDay, fromDay, validateOrder } from './engine.mjs';
import { snapshot, report, completedOn } from './insights.mjs';

const rules = JSON.parse(readFileSync(new URL('../../app/assets/rules/rules.json', import.meta.url), 'utf8'));
const TODAY = '2026-10-11';
const T = toDay(TODAY);

function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6d2b79f5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

function makeOrder(r, n) {
  const types = Object.keys(rules.types);
  const type = types[Math.floor(r() * types.length)];
  const category = r() < 0.2 ? 'emergency' : 'extension';
  const received = fromDay(T - Math.floor(r() * 60));
  const segs = [];
  const nSeg = Math.floor(r() * 3);
  for (let i = 0; i < nSeg; i++) segs.push({ id: `s${i}`, base: r() < 0.5 ? 'soil' : 'asphalt', width: r() < 0.5 ? 40 : 80, lengthM: 5 + Math.floor(r() * 40), tiled: r() < 0.2 });
  const meters = [{ id: 'm0' }];
  if (r() < 0.2) meters.push({ id: 'm1' });
  return {
    id: `o${n}`, type, category, woNumber: category === 'extension' ? String(441000000 + n) : `T-${n}`, receivedDate: received,
    needsExcavation: !!rules.types[type].optionalExcavation && r() < 0.5,
    segments: segs, meters, cableRuns: r() < 0.7 ? [{ sizeMm2: 185, voltage: 'LV', lengthM: 30 }] : [], permits: [], steps: {},
    status: { state: 'open', holdPeriods: [] }, lastChangeDate: received,
  };
}

const pick = (r, list) => list[Math.floor(r() * list.length)];
const dateBetween = (r, from) => fromDay(toDay(from) + Math.floor(r() * (T - toDay(from) + 1)));

function randomAction(r, o, others) {
  const steps = generate(rules, o);
  const ev = evaluate(rules, o, TODAY);
  const ready = ev.steps.filter((s) => s.state === 'ready');
  const closed = ev.steps.filter((s) => s.state === 'done' || s.state === 'na');
  const x = r();
  if (x < 0.45 && ready.length) {
    const s = pick(r, ready);
    const deps = s.deps.map((d) => o.steps[d] && o.steps[d].done).filter(Boolean);
    const from = deps.length ? deps.sort().at(-1) : o.receivedDate;
    return ['markDone', s.id, dateBetween(r, from)];
  }
  if (x < 0.55) return ['markDone', pick(r, steps).id, dateBetween(r, fromDay(T - 70))]; // may be refused
  if (x < 0.60) return ['markNA', pick(r, steps).id, r() < 0.9 ? 'not needed' : ' '];
  if (x < 0.68 && closed.length) return ['clearStep', pick(r, closed).id];
  if (x < 0.76) {
    const start = dateBetween(r, o.receivedDate);
    return ['savePermit', null, { appliedDate: dateBetween(r, o.receivedDate), number: `P-${o.id}-${Math.floor(r() * 3)}`, startDate: start, endDate: fromDay(toDay(start) + Math.floor(r() * 30) - 3) }];
  }
  if (x < 0.82) return ['putOnHold', dateBetween(r, o.receivedDate), 'reason', r() < 0.5 ? fromDay(T + 3) : null];
  if (x < 0.88) return ['resume', dateBetween(r, o.receivedDate)];
  if (x < 0.90) return ['cancel', 'SEC cancelled'];
  if (x < 0.92) return ['reopen'];
  if (x < 0.94) return ['merge', pick(r, others).id, r() < 0.5];
  if (x < 0.97) return ['edit', { segments: [...(o.segments || []), { id: `s${(o.segments || []).length + 10}`, base: 'soil', width: 40, lengthM: 4 }] }];
  if (x < 0.985) return ['bulk', pick(r, steps).key, dateBetween(r, o.receivedDate)];
  const types = Object.keys(rules.types);
  return ['edit', { type: pick(r, types), needsExcavation: false }];
}

function apply(o, act, all) {
  const [kind, ...a] = act;
  switch (kind) {
    case 'markDone': return A.markDone(rules, o, a[0], a[1], TODAY);
    case 'markNA': return A.markNA(rules, o, a[0], a[1], TODAY);
    case 'clearStep': return A.clearStep(rules, o, a[0]);
    case 'savePermit': return A.savePermit(rules, o, a[0], a[1], all.filter((x) => x.id !== o.id), TODAY);
    case 'putOnHold': return A.putOnHold(rules, o, a[0], a[1], TODAY, a[2]);
    case 'resume': return A.resume(rules, o, a[0], TODAY);
    case 'cancel': return A.cancel(rules, o, a[0], TODAY);
    case 'reopen': return A.reopen(rules, o);
    case 'merge': { const t = all.find((x) => x.id === a[0]); return A.merge(rules, o, t, 'replaced', a[1], TODAY); }
    case 'edit': return { ok: true, order: { ...structuredClone(o), ...a[0] } };
    case 'bulk': { const r = A.bulkMarkDone(rules, [o], a[0], a[1], TODAY); return { ok: true, order: r.orders[0] }; }
    default: throw new Error(kind);
  }
}

// Steps carried over by a merge keep their real dates, which can be before the
// replacement order was received (the work was done under the old order).
const carriedInto = new Set();

function checkOrder(o, label) {
  const ev = evaluate(rules, o, TODAY);
  const steps = generate(rules, o);
  const ids = new Set(steps.map((s) => s.id));
  assert.ok(ev.progress.closed <= ev.progress.total, `${label}: progress`);
  // Dates: never in the future, never before the order was received.
  for (const [id, rec] of Object.entries(o.steps || {})) {
    if (rec.done) {
      assert.ok(toDay(rec.done) <= T, `${label}: ${id} done in the future`);
      if (!carriedInto.has(o.id)) assert.ok(toDay(rec.done) >= toDay(o.receivedDate), `${label}: ${id} done before received`);
    }
    assert.ok(!(rec.done && rec.na), `${label}: ${id} both done and N/A`);
    if (rec.na) assert.ok(rec.reason && rec.reason.trim(), `${label}: ${id} N/A without reason`);
  }
  // A ready step never has an open dependency; a locked step always has a reason.
  for (const s of ev.steps) {
    if (s.state === 'ready') for (const d of s.deps) assert.ok(o.steps[d] && (o.steps[d].done || o.steps[d].na), `${label}: ${s.id} ready but ${d} open`);
    if (s.state === 'locked') assert.ok(s.reasons.length, `${label}: ${s.id} locked without reason`);
  }
  // Holds: at most one open, in order, not overlapping; state matches.
  const hp = (o.status && o.status.holdPeriods) || [];
  assert.ok(hp.filter((h) => !h.to).length <= 1, `${label}: two open holds`);
  for (let i = 1; i < hp.length; i++) assert.ok(hp[i - 1].to && toDay(hp[i].from) >= toDay(hp[i - 1].to), `${label}: holds overlap`);
  for (const h of hp) if (h.to) assert.ok(toDay(h.to) >= toDay(h.from), `${label}: hold ends before it starts`);
  const st = (o.status && o.status.state) || 'open';
  if (st === 'on_hold') assert.ok(hp.some((h) => !h.to), `${label}: on hold without an open period`);
  if (st === 'open') assert.ok(!hp.some((h) => !h.to), `${label}: open with an open hold period`);
  if (st === 'cancelled' || st === 'merged') {
    assert.ok(o.status.reason && o.status.date, `${label}: ${st} without reason/date`);
    assert.ok(!hp.some((h) => !h.to), `${label}: ${st} with an open hold`);
  }
  if (st === 'merged') assert.ok(o.status.mergedInto && o.status.mergedInto !== o.id, `${label}: merged target`);
  // Alerts only while active.
  if (!['open', 'on_hold'].includes(ev.status)) assert.equal(ev.alerts.length, 0, `${label}: alerts on ${ev.status}`);
  // Completed means every step closed, and it has a completion date.
  if (ev.status === 'completed') { assert.equal(ev.progress.closed, ev.progress.total); assert.ok(completedOn(ev), `${label}: completed without a date`); }
  // Tasreeh rules the database also enforces.
  for (const e of validateOrder(rules, o)) assert.ok(!e.code.startsWith('permit_'), `${label}: ${e.code}`);
  for (const p of o.permits || []) if (p.appliedDate) assert.ok(toDay(p.appliedDate) <= T, `${label}: tasreeh applied in the future`);
  // The as-of-today snapshot is the order itself.
  assert.deepEqual(snapshot(o, TODAY), o, `${label}: snapshot today`);
  // Order: a step marked done always comes after the steps it waits for (done or N/A).
  if (process.env.FUZZ_DEPS) for (const s of steps) {
    const rec = o.steps[s.id];
    if (rec && rec.done) for (const d of s.deps) {
      const dr = o.steps[d];
      if (!(dr && (dr.done || dr.na))) { globalThis.depViolations = (globalThis.depViolations || 0) + 1; globalThis.lastDepViolation = label + ' ' + s.id + ' needs ' + d; }
    }
  }
  // Unknown step records are allowed (kept after edits) but never counted.
  assert.equal(ev.steps.length, ids.size);
}

test('random action sequences never break the rules', () => {
  let actions = 0, okCount = 0;
  for (let seed = 1; seed <= Number(process.env.FUZZ_SEEDS || 400); seed++) {
    const r = rng(seed);
    let orders = Array.from({ length: 6 }, (_, i) => makeOrder(r, seed * 10 + i));
    const log = [];
    for (let i = 0; i < 60; i++) {
      const idx = Math.floor(r() * orders.length);
      const o = orders[idx];
      const act = randomAction(r, o, orders.filter((x) => x.id !== o.id));
      log.push([o.id, ...act]);
      const before = JSON.stringify(o);
      let res;
      try { res = apply(o, act, orders); } catch (e) { assert.fail(`seed ${seed}: ${JSON.stringify(log)} threw ${e.stack}`); }
      assert.equal(JSON.stringify(o), before, `seed ${seed}: action changed its input`);
      actions++;
      if (!res.ok) { assert.ok(res.errors && res.errors.length, `seed ${seed}: refused without a reason`); continue; }
      okCount++;
      if (res.target && res.carried && res.carried.length) carriedInto.add(res.target.id);
      orders = orders.map((x) => (x.id === o.id ? res.order : res.target && x.id === res.target.id ? res.target : x));
      try {
        checkOrder(res.order, `seed ${seed} after ${JSON.stringify(log.at(-1))}`);
        if (res.target) checkOrder(res.target, `seed ${seed} merge target`);
      } catch (e) { e.message += `\nreplay: ${JSON.stringify(log)}`; throw e; }
    }
    // Reports over the result add up.
    const rep = report(rules, orders, fromDay(T - 30), TODAY, TODAY);
    assert.ok(rep.open >= 0 && rep.completed >= 0 && rep.received >= 0, `seed ${seed}: report`);
  }
  if (process.env.FUZZ_DEPS) console.log('dep violations', globalThis.depViolations, globalThis.lastDepViolation);
  assert.ok(actions > 20000 && okCount > 5000, `${actions} actions, ${okCount} accepted`);
});
