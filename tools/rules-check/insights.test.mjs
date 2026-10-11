import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { pipeline, startsByDay, board, followUp, search, filterOrders, report, dailyReport, weekRange, monthRange, normalizeText, evaluateAll } from './insights.mjs';
import { toDay, fromDay } from './engine.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const rules = JSON.parse(readFileSync(join(root, 'app', 'assets', 'rules', 'rules.json'), 'utf8'));
const fx = JSON.parse(readFileSync(join(root, 'app', 'test', 'fixtures', 'insights.json'), 'utf8'));
const { orders, today } = fx;

const pick = (obj, keys) => Object.fromEntries(keys.map((k) => [k, obj[k]]));

test('pipeline: ready and total per step, tasreeh buckets', () => {
  const p = pipeline(rules, orders, today);
  assert.equal(p.activeCount, fx.pipeline.activeCount);
  for (const [k, v] of Object.entries(fx.pipeline.steps)) assert.deepEqual(p.steps[k], v, k);
  assert.deepEqual(p.buckets, fx.pipeline.buckets);
});

test('starts by day: next 7 days', () => {
  const s = startsByDay(rules, orders, today, 7);
  assert.equal(s.length, 7);
  fx.startsByDay.forEach((e, i) => {
    assert.equal(s[i].date, e.date);
    assert.equal(s[i].count, e.count, e.date);
    if (e.orders) assert.deepEqual(s[i].orders, e.orders);
  });
});

test('board: columns, order, next step and days waiting', () => {
  const b = board(rules, orders, today);
  assert.deepEqual(b.map((c) => c.stage), Object.keys(fx.board));
  for (const col of b) {
    const exp = fx.board[col.stage];
    assert.equal(col.cards.length, exp.length, col.stage);
    exp.forEach((e, i) => assert.deepEqual(pick(col.cards[i], Object.keys(e)), e, `${col.stage}[${i}]`));
  }
});

test('follow-up: contractors, groups and items in urgency order', () => {
  const f = followUp(rules, orders, today);
  assert.equal(f.length, fx.followUp.length);
  fx.followUp.forEach((ec, i) => {
    const c = f[i];
    assert.deepEqual(pick(c, ['contractor', 'orders', 'late']), pick(ec, ['contractor', 'orders', 'late']));
    assert.deepEqual(c.groups.map((g) => g.group), ec.groups.map((g) => g.group), ec.contractor);
    ec.groups.forEach((eg, j) => {
      assert.equal(c.groups[j].severity, eg.severity, `${ec.contractor}/${eg.group} severity`);
      assert.deepEqual(c.groups[j].items.map((it) => pick(it, Object.keys(eg.items[0]))), eg.items, `${ec.contractor}/${eg.group}`);
    });
  });
});

for (const s of fx.search) {
  test(`search: "${s.query}"`, () => {
    const r = search(rules, orders, s.query, today).map((x) => [x.id, x.kind, x.value]);
    assert.deepEqual(r, s.results);
  });
}

for (const f of fx.filters) {
  test(`filter: ${f.name}`, () => assert.deepEqual(filterOrders(rules, orders, today, f.criteria), f.ids));
}

test('daily report: every figure', () => {
  const d = dailyReport(rules, orders, fx.daily.date);
  for (const k of ['received', 'receivedPrev', 'stepsCompleted', 'ordersTouched', 'completed', 'completedPrev', 'open', 'attention', 'attentionByCode', 'byStage', 'stepsByKey', 'contractors', 'quantities']) {
    assert.deepEqual(d[k], fx.daily[k], k);
  }
  assert.deepEqual(d.completedList.map((x) => pick(x, ['id', 'days'])), fx.daily.completedList);
  assert.deepEqual(d.delays.map((x) => pick(x, ['id', 'code', 'days', 'severity'])), fx.daily.delays);
  assert.equal(d.trend.length, fx.daily.trendLength);
  for (const p of fx.daily.trendPoints) assert.deepEqual(d.trend.find((t) => t.date === p.date), p, p.date);
});

test('monthly report: totals and quantities', () => {
  const m = fx.monthly;
  const r = report(rules, orders, m.from, m.to, m.today);
  assert.equal(r.received, m.received);
  assert.equal(r.stepsCompleted, m.stepsCompleted);
  assert.equal(r.completed, m.completed);
  assert.deepEqual(r.quantities, m.quantities);
  assert.equal(r.series.length, 31);
});

test('week (Saturday to Friday) and month ranges', () => {
  for (const r of fx.ranges) {
    if (r.week) assert.deepEqual(weekRange(r.date), r.week, r.date);
    if (r.month) assert.deepEqual(monthRange(r.date), r.month, r.date);
  }
});

// ---------- Consistency checks that must hold for any data ----------
test('consistency: report figures add up', () => {
  for (let d = toDay('2026-09-01'); d <= toDay('2026-10-11'); d++) {
    const date = fromDay(d);
    const r = report(rules, orders, date, date, date);
    assert.equal(Object.values(r.stepsByKey).reduce((a, b) => a + b, 0), r.stepsCompleted, `${date} steps by key`);
    assert.equal(Object.values(r.byStage).reduce((a, b) => a + b, 0), r.open, `${date} stages`);
    assert.ok(r.attention <= r.open);
    assert.ok(r.ordersTouched <= r.stepsCompleted);
    assert.equal(r.contractors.reduce((a, c) => a + c.open, 0), r.open, `${date} contractor open`);
    assert.equal(r.delays.length, r.attention, `${date} delays`);
  }
});

test('consistency: board shows every active order exactly once', () => {
  const ids = board(rules, orders, today).flatMap((c) => c.cards.map((x) => x.id));
  const active = evaluateAll(rules, orders, today).filter((x) => ['open', 'on_hold'].includes(x.ev.status)).map((x) => x.order.id);
  assert.deepEqual([...ids].sort(), [...active].sort());
});

test('consistency: every order can be found by its own number, deleted ones never', () => {
  for (const o of orders) {
    const hits = search(rules, orders, o.woNumber, today).filter((x) => x.id === o.id && x.kind === 'workOrder');
    assert.equal(hits.length, o.deleted ? 0 : 1, o.woNumber);
  }
});

test('consistency: pipeline counts match the step filter', () => {
  const p = pipeline(rules, orders, today);
  for (const [key, v] of Object.entries(p.steps)) {
    const ready = filterOrders(rules, orders, today, { status: ['open', 'on_hold'], steps: [{ step: key, state: 'ready' }] });
    const notDone = filterOrders(rules, orders, today, { status: ['open', 'on_hold'], steps: [{ step: key, state: 'not_done' }] });
    assert.equal(ready.length, v.ready, `${key} ready`);
    assert.equal(notDone.length, v.total, `${key} total`);
  }
});

test('Arabic text normalisation', () => {
  assert.equal(normalizeText('أولوية'), normalizeText('اولويه'));
  assert.equal(normalizeText('إدارة'), normalizeText('اداره'));
  assert.equal(normalizeText('مستشفى'), normalizeText('مستشفي'));
  assert.equal(normalizeText('٤٤١٧'), '4417');
  assert.equal(normalizeText('۴۴۱۷'), '4417');
  assert.equal(normalizeText('مُحَمَّد'), 'محمد');
});

// Small cases for single rules (shared with the Dart tests).
for (const c of fx.extraCases) {
  test(`case: ${c.name}`, () => {
    if (c.pipelineBuckets) assert.deepEqual(pipeline(rules, c.orders, c.today).buckets, c.pipelineBuckets);
    for (const f of c.filters || []) assert.deepEqual(filterOrders(rules, c.orders, c.today, f.criteria), f.ids, JSON.stringify(f.criteria));
    if (c.report) {
      const e = c.report;
      const r = report(rules, c.orders, e.from, e.to, e.today);
      assert.equal(r.completed, e.completed);
      assert.deepEqual(r.completedList.map((x) => [x.id, x.days]), e.completedList);
      for (const [date, n] of e.completedOn) assert.equal(r.series.find((p) => p.date === date).completed, n, date);
      assert.deepEqual(r.contractors.map((x) => [x.contractor, x.completedInPeriod, x.finished, x.avgDaysToFinish]), e.contractors);
    }
    for (const [contractor, group, steps, days] of c.followUpGroups || []) {
      const con = followUp(rules, c.orders, c.today).find((x) => x.contractor === contractor);
      const g = con.groups.find((x) => x.group === group);
      assert.ok(g, `${contractor} has no ${group} group: ${con.groups.map((x) => x.group)}`);
      assert.deepEqual(g.items.map((i) => i.steps), [steps]);
      assert.equal(g.items[0].daysWaiting, days);
    }
  });
}
