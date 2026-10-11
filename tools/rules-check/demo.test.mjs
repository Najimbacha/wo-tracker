// Checks the demo orders (app/assets/demo/demo_orders.json): each one obeys the rules
// when replayed from scratch, and together they show every situation the screens handle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildDemo, demoFile, shiftDates, DEMO_TODAY } from '../sample/demo.mjs';
import { evaluate, generate, validateOrder, toDay, fromDay } from './engine.mjs';
import { markDone, markNA, validateDraft } from './actions.mjs';
import { pipeline, followUp, filterOrders, dailyReport, report, ACTION_GROUPS, QUICK_FILTERS } from './insights.mjs';

const root = new URL('../../', import.meta.url);
const json = (p) => JSON.parse(readFileSync(new URL(p, root), 'utf8'));
const rules = json('app/assets/rules/rules.json');
const file = json('app/assets/demo/demo_orders.json');
const orders = file.orders;
const live = orders.filter((o) => !o.deleted);
const T = file.today;
const evs = live.map((o) => evaluate(rules, o, T));
const count = (xs) => xs.reduce((m, k) => ((m[k] = (m[k] || 0) + 1), m), {});

test('the file is up to date with the generator, and the generator is repeatable', () => {
  assert.equal(T, DEMO_TODAY);
  assert.deepEqual(buildDemo(rules), buildDemo(rules));
  assert.deepEqual(file, JSON.parse(JSON.stringify(demoFile(rules))), 'run: node tools/sample/demo.mjs');
});

test('every order is valid and no number is used twice', () => {
  for (const o of orders) {
    assert.deepEqual(validateOrder(rules, o), [], o.id);
    const others = orders.filter((x) => x.id !== o.id);
    assert.deepEqual(validateDraft(rules, o, others, T).map((e) => e.code), [], o.id);
  }
});

test('every order replays from scratch through the real actions', () => {
  for (const o of orders) {
    const order = generate(rules, o).map((s) => s.id);
    // Steps carried over from an order merged into this one keep their original dates
    // (the work was done under the old number), so they are taken as they are.
    const carried = {};
    for (const src of orders.filter((x) => x.status.mergedInto === o.id)) {
      for (const [id, r] of Object.entries(src.steps)) if (JSON.stringify(o.steps[id]) === JSON.stringify(r)) carried[id] = r;
    }
    let cur = { ...structuredClone(o), steps: { ...carried }, status: { state: 'open', holdPeriods: [] }, lastChangeDate: o.receivedDate };
    const recs = Object.entries(o.steps).filter(([id]) => !(id in carried));
    for (const id of Object.keys(o.steps)) assert.ok(order.includes(id), `${o.id}: record for unknown step ${id}`);
    for (const [id, r] of recs.filter(([, r]) => r.na)) {
      const res = markNA(rules, cur, id, r.reason, T);
      assert.ok(res.ok, `${o.id} N/A ${id}: ${JSON.stringify(res.errors)}`);
      cur = res.order;
    }
    const done = recs.filter(([, r]) => r.done).sort((a, b) => toDay(a[1].done) - toDay(b[1].done) || order.indexOf(a[0]) - order.indexOf(b[0]));
    for (const [id, r] of done) {
      const res = markDone(rules, cur, id, r.done, T);
      assert.ok(res.ok, `${o.id} ${id} on ${r.done}: ${JSON.stringify(res.errors)}`);
      cur = res.order;
    }
  }
});

test('every type, category and status', () => {
  assert.deepEqual(Object.keys(count(live.map((o) => o.type))).sort(), Object.keys(rules.types).sort());
  assert.deepEqual(Object.keys(count(live.map((o) => o.category))).sort(), ['emergency', 'extension']);
  const st = count(evs.map((e) => e.status));
  for (const s of ['open', 'on_hold', 'completed', 'cancelled', 'merged']) assert.ok(st[s] > 0, `no ${s} order`);
  assert.ok(st.open >= 30, 'enough open orders to fill the screens');
  assert.ok(st.completed >= 10, 'enough completed orders for reports');
});

test('every stage and every alert, including a critical late start', () => {
  const stages = count(evs.map((e) => e.stage).filter(Boolean));
  for (const s of rules.stages) assert.ok(stages[s.key] > 0, `no order in stage ${s.key}`);
  const alerts = count(evs.flatMap((e) => e.alerts.map((a) => a.code)));
  for (const c of ['late_start', 'open_trench', 'restoration_overdue', 'no_active_tasreeh', 'next_tasreeh_needed', 'meter_not_on', 'tawari_tasreeh_missing', 'stalled']) assert.ok(alerts[c] > 0, `no ${c} alert`);
  const severities = new Set(evs.flatMap((e) => e.alerts.filter((a) => a.code === 'late_start').map((a) => a.severity)));
  assert.deepEqual([...severities].sort(), ['critical', 'warning']);
});

test('every Pipeline bucket, Follow-up group, quick filter and tasreeh state has orders', () => {
  for (const [b, n] of Object.entries(pipeline(rules, orders, T).buckets)) assert.ok(n > 0, `pipeline bucket ${b} empty`);
  const groups = new Set(followUp(rules, orders, T).flatMap((c) => c.groups.map((g) => g.group)));
  for (const [g] of ACTION_GROUPS) assert.ok(groups.has(g), `follow-up group ${g} empty`);
  for (const q of QUICK_FILTERS) assert.ok(filterOrders(rules, orders, T, { quick: [q] }).length > 0, `quick filter ${q} empty`);
  for (const s of ['not_needed', 'none', 'active', 'ending', 'future', 'expired']) assert.ok(filterOrders(rules, orders, T, { tasreeh: [s] }).length > 0, `tasreeh state ${s} empty`);
});

test('the special cases are all present', () => {
  assert.ok(live.some((o) => o.permits.length >= 2), 'a long project with several tasreeh');
  assert.ok(live.some((o) => o.meters.length >= 2), 'several meters');
  assert.ok(live.some((o) => new Set(o.segments.map((s) => `${s.base}${s.width}`)).size >= 3), 'mixed surfaces');
  assert.ok(live.some((o) => o.segments.some((s) => s.tiled)), 'tiles');
  assert.ok(live.some((o) => Object.values(o.steps).some((r) => r.na)), 'not applicable steps');
  assert.ok(live.some((o) => o.status.holdPeriods.some((h) => h.to)), 'a finished hold');
  assert.ok(live.some((o) => o.needsExcavation), '409 with excavation');
  assert.ok(orders.some((o) => o.deleted), 'a deleted order');
  assert.ok(live.some((o) => !o.contractor), 'no contractor');
  assert.ok(new Set(live.map((o) => o.contractor).filter(Boolean)).size > 10, 'more than 10 contractors');
  assert.ok(live.some((o) => /[؀-ۿ]/.test(`${o.district} ${o.notes || ''}`)), 'Arabic text to search');
  const merged = live.find((o) => o.status.state === 'merged');
  assert.ok(live.some((o) => o.id === merged.status.mergedInto), 'merged order points to a real order');
});

test('reports have something to show today, this week and last month', () => {
  const d = dailyReport(rules, orders, T);
  assert.ok(d.received > 0 && d.stepsCompleted > 0 && d.completed > 0, JSON.stringify({ r: d.received, s: d.stepsCompleted, c: d.completed }));
  assert.ok(d.trend.filter((p) => p.received || p.completed).length >= 7, 'trend has data on most days');
  const sep = report(rules, orders, '2026-09-01', '2026-09-30', '2026-09-30');
  assert.ok(sep.received >= 15 && sep.completed >= 5, JSON.stringify({ r: sep.received, c: sep.completed }));
});

test('Demo mode can move all dates to any day without changing what the screens show', () => {
  for (const days of [1, 37, 400]) {
    const later = fromDay(toDay(T) + days);
    for (const o of orders) {
      const a = evaluate(rules, o, T);
      const b = evaluate(rules, shiftDates(o, days), later);
      assert.equal(b.status, a.status, o.id);
      assert.equal(b.stage, a.stage, o.id);
      assert.deepEqual(b.alerts.map((x) => [x.code, x.days ?? x.daysLeft ?? null]), a.alerts.map((x) => [x.code, x.days ?? x.daysLeft ?? null]), o.id);
    }
  }
});
