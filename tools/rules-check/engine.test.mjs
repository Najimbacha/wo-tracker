import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { generate, evaluate, validateMarkDone, clearImpact, validateOrder, activeDays, orderPackages, segmentRecipe } from './engine.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const rules = JSON.parse(readFileSync(join(root, 'app', 'assets', 'rules', 'rules.json'), 'utf8'));
const golden = JSON.parse(readFileSync(join(root, 'app', 'test', 'fixtures', 'golden.json'), 'utf8'));

const sorted = (a) => [...a].sort();

// ---------- Golden scenarios (shared with the Dart tests) ----------
for (const c of golden.cases) {
  test(`golden: ${c.name}`, () => {
    if (c.expect) {
      const r = evaluate(rules, c.order, c.today);
      const e = c.expect;
      if ('total' in e) assert.equal(r.progress.total, e.total, 'total steps');
      if ('status' in e) assert.equal(r.status, e.status, 'status');
      if ('stage' in e) assert.equal(r.stage, e.stage, 'stage');
      if ('ready' in e) assert.deepEqual(sorted(r.next), sorted(e.ready), 'ready steps');
      if ('alerts' in e) {
        assert.equal(r.alerts.length, e.alerts.length, `alert count: ${JSON.stringify(r.alerts)}`);
        e.alerts.forEach((ea, i) => {
          for (const [k, v] of Object.entries(ea)) assert.deepEqual(r.alerts[i][k], v, `alert ${i} ${k}`);
        });
      }
      for (const [id, codes] of Object.entries(e.reasons || {})) {
        const s = r.steps.find((x) => x.id === id);
        assert.ok(s, `step ${id} exists`);
        assert.equal(s.state, 'locked', `${id} locked`);
        assert.deepEqual(s.reasons.map((x) => x.code), codes, `${id} reasons`);
      }
      for (const [id, waits] of Object.entries(e.waitingFor || {})) {
        const s = r.steps.find((x) => x.id === id);
        assert.deepEqual(s.reasons.find((x) => x.code === 'waiting_for').steps, waits, `${id} waits for`);
      }
    }
    for (const v of c.validate || []) {
      const errs = validateMarkDone(rules, c.order, v.step, v.date, c.today).map((x) => x.code);
      assert.deepEqual(errs, v.errors, `validate ${v.step} on ${v.date}`);
    }
  });
}
for (const c of golden.clearImpact) {
  test(`golden clear: ${c.name}`, () => assert.deepEqual(clearImpact(rules, c.order, c.step), c.expect));
}
for (const c of golden.validateOrder) {
  test(`golden order check: ${c.name}`, () => assert.deepEqual(validateOrder(rules, c.order).map((x) => x.code), c.errors));
}

// ---------- Rules file integrity ----------
test('rules: every package step and recipe step is defined', () => {
  for (const [k, p] of Object.entries(rules.packages)) for (const s of p.steps || []) assert.ok(rules.steps[s], `${k}.${s}`);
  for (const [k, r] of Object.entries(rules.segmentRecipes)) for (const s of r) assert.ok(rules.steps[s], `${k}.${s}`);
  assert.ok(rules.steps[rules.tiledStep]);
  for (const [k, t] of Object.entries(rules.types)) for (const p of t.packages) assert.ok(rules.packages[p], `${k}.${p}`);
});
test('rules: every step has English and Arabic labels', () => {
  for (const [k, s] of Object.entries(rules.steps)) { assert.ok(s.en, k); assert.ok(s.ar, k); }
  for (const [k, t] of Object.entries(rules.types)) { assert.ok(t.en, k); assert.ok(t.ar, k); }
});
test('rules: every package maps to a stage', () => {
  const staged = new Set(rules.stages.flatMap((s) => s.packages || []));
  for (const p of Object.keys(rules.packages)) assert.ok(staged.has(p), p);
});
test('days: calendar days with hold periods removed', () => {
  assert.equal(activeDays('2026-10-06', '2026-10-11'), 5);
  assert.equal(activeDays('2026-10-06', '2026-10-11', [{ from: '2026-10-07', to: '2026-10-09' }]), 3);
  assert.equal(activeDays('2026-10-06', '2026-10-11', [{ from: '2026-10-08', to: null }]), 2);
  assert.equal(activeDays('2026-12-30', '2027-01-02'), 3);
  assert.equal(activeDays('2028-02-28', '2028-03-01'), 2, 'leap year');
  assert.equal(activeDays('2026-10-11', '2026-10-01'), 0);
});

// ---------- Exhaustive: every type x category x excavation switch x surfaces x meters ----------
const SEGMENT_SETS = [
  [],
  [{ id: 's1', base: 'soil', width: 40, lengthM: 10, tiled: false }],
  [{ id: 's1', base: 'soil', width: 80, lengthM: 10, tiled: true }],
  [{ id: 's1', base: 'asphalt', width: 40, lengthM: 10, tiled: false }],
  [{ id: 's1', base: 'asphalt', width: 80, lengthM: 10, tiled: false }],
  [{ id: 's1', base: 'asphalt', width: 40, lengthM: 10, tiled: true }],
  [{ id: 's1', base: 'asphalt', width: 80, lengthM: 10, tiled: true }],
  [{ id: 's1', base: 'asphalt', width: 40, lengthM: 10, tiled: false }, { id: 's2', base: 'asphalt', width: 80, lengthM: 10, tiled: false }],
  [{ id: 's1', base: 'soil', width: 40, lengthM: 10, tiled: false }, { id: 's2', base: 'asphalt', width: 40, lengthM: 10, tiled: true }, { id: 's3', base: 'asphalt', width: 80, lengthM: 10, tiled: true }],
];
const METER_SETS = [[{ id: 'm1' }], [{ id: 'm1' }, { id: 'm2' }, { id: 'm3' }]];

function* allOrders() {
  for (const type of Object.keys(rules.types)) {
    for (const category of ['extension', 'emergency']) {
      for (const needsExcavation of rules.types[type].optionalExcavation ? [false, true] : [false]) {
        for (const segments of SEGMENT_SETS) {
          for (const meters of METER_SETS) {
            yield { type, category, needsExcavation, woNumber: category === 'extension' ? '441000000' : 'T-1', receivedDate: '2026-09-01', segments, meters, cableRuns: [{ sizeMm2: 185, voltage: 'LV', lengthM: 10 }], steps: {} };
          }
        }
      }
    }
  }
}

function expectedTotal(order) {
  let n = 0;
  for (const p of orderPackages(rules, order)) {
    const def = rules.packages[p];
    if (def.scope === 'order') n += def.steps.length;
    else if (def.scope === 'meter') n += def.steps.length * order.meters.length;
    else for (const s of order.segments) n += segmentRecipe(rules, s).length;
  }
  return n;
}

let combos = 0;
test('exhaustive: structure of every generated order', () => {
  for (const order of allOrders()) {
    combos++;
    const label = `${order.type}/${order.category}/exc=${order.needsExcavation}/segs=${order.segments.length}/m=${order.meters.length}`;
    const steps = generate(rules, order);
    const ids = steps.map((s) => s.id);
    const pkgs = orderPackages(rules, order);
    assert.equal(new Set(ids).size, ids.length, `${label}: unique ids`);
    assert.equal(steps.length, expectedTotal(order), `${label}: total`);
    const seen = new Set();
    for (const s of steps) {
      for (const d of s.deps) assert.ok(seen.has(d), `${label}: ${s.id} depends on later/unknown ${d}`);
      seen.add(s.id);
    }
    const byId = Object.fromEntries(steps.map((s) => [s.id, s]));
    // Close-out: certificate waits for everything, documents only for the certificate.
    const cert = byId.certificate;
    assert.ok(cert, `${label}: certificate present`);
    assert.deepEqual(sorted(cert.deps), sorted(ids.filter((i) => i !== 'certificate' && i !== 'documents_submitted')), `${label}: certificate waits for all`);
    assert.deepEqual(byId.documents_submitted.deps, ['certificate'], `${label}: documents after certificate`);
    assert.equal(ids[ids.length - 1], 'documents_submitted', `${label}: documents last`);
    // Kashfeya and tasreeh.
    if (byId.tasreeh_applied) assert.deepEqual(byId.tasreeh_applied.deps, ['kashfeya'], `${label}: tasreeh after kashfeya`);
    for (const g of ['excavation', 'poles']) {
      if (!byId[g]) continue;
      assert.equal(byId[g].gate, 'tasreehStarted', `${label}: ${g} gated`);
      assert.deepEqual(byId[g].deps, order.category === 'emergency' ? [] : ['tasreeh_applied'], `${label}: ${g} deps`);
    }
    // Kashfeya only where there is digging or poles.
    assert.equal(!!byId.kashfeya, pkgs.includes('civil') || pkgs.includes('overhead'), `${label}: kashfeya only with digging or poles`);
    // Segments.
    for (const seg of order.segments) {
      const segSteps = steps.filter((s) => s.instance === seg.id);
      if (!pkgs.includes('restoration')) { assert.equal(segSteps.length, 0, `${label}: no restoration steps`); continue; }
      assert.deepEqual(segSteps.map((s) => s.key), segmentRecipe(rules, seg), `${label}: recipe ${seg.id}`);
      assert.deepEqual(segSteps[0].deps, ['warning_tape'], `${label}: ${seg.id} starts after warning tape`);
      if (seg.tiled) assert.equal(segSteps[segSteps.length - 1].key, 'tiles', `${label}: tiles last`);
      if (seg.base === 'asphalt' && seg.width >= 80) assert.ok(!segSteps.some((s) => s.key === 'concrete'), `${label}: no concrete at 80 cm`);
      if (seg.base === 'asphalt' && seg.width < 80) assert.equal(segSteps[0].key, 'concrete', `${label}: concrete first at 40 cm`);
      if (seg.base === 'soil') assert.equal(segSteps[0].key, 'compaction', `${label}: soil compaction`);
    }
    // Meters.
    const meterPkg = pkgs.find((p) => rules.packages[p].scope === 'meter');
    if (meterPkg) {
      for (const m of order.meters) {
        const ms = steps.filter((s) => s.instance === m.id);
        assert.deepEqual(ms.map((s) => s.key), rules.packages[meterPkg].steps, `${label}: meter ${m.id} steps`);
        const restoration = steps.filter((s) => s.package === 'restoration').map((s) => s.id);
        let expectDeps = [];
        if (pkgs.includes('restoration')) expectDeps = ['warning_tape', ...restoration];
        else if (pkgs.includes('overhead')) expectDeps = ['stringing'];
        assert.deepEqual(sorted(ms[0].deps), sorted(expectDeps), `${label}: meter entry deps`);
      }
    }
    // Transformer.
    if (byId.foundation) assert.deepEqual(byId.foundation.deps, [pkgs.includes('civil') ? 'cable_installed' : 'stringing'], `${label}: transformer entry`);
  }
  assert.ok(combos > 400, `checked ${combos} combinations`);
});

// Walk every order from new to finished by marking whatever is ready, checking each
// mark is accepted by validation and that nothing becomes ready too early.
test('exhaustive: every order can be completed step by step, in valid order only', () => {
  let walked = 0;
  for (const base of allOrders()) {
    const order = structuredClone(base);
    order.permits = [{ number: 'P-1', appliedDate: '2026-09-02', startDate: '2026-09-03', endDate: '2026-12-31' }];
    const today = '2026-10-11';
    let day = 0;
    for (let guard = 0; guard < 200; guard++) {
      const r = evaluate(rules, order, today);
      if (r.status === 'completed') break;
      if (!r.next.length) break;
      const date = new Date(Date.UTC(2026, 8, 4 + Math.min(day, 30))).toISOString().slice(0, 10);
      for (const id of r.next) {
        const errs = validateMarkDone(rules, order, id, date, today);
        assert.deepEqual(errs, [], `${order.type}/${order.category}: ${id} on ${date} rejected ${JSON.stringify(errs)}`);
        order.steps[id] = { done: date };
      }
      day++;
    }
    const r = evaluate(rules, order, today);
    const needsSegments = orderPackages(rules, order).includes('restoration') && order.segments.length === 0;
    if (needsSegments) {
      assert.notEqual(r.status, 'completed', 'cannot complete without surface segments');
      const cert = r.steps.find((s) => s.id === 'certificate');
      assert.ok(cert.reasons.some((x) => x.code === 'missing_segments'));
    } else {
      assert.equal(r.status, 'completed', `${order.type}/${order.category}/segs=${order.segments.length} should complete`);
      assert.equal(r.progress.closed, r.progress.total);
    }
    walked++;
  }
  assert.ok(walked > 400);
});

test('exhaustive: a step is never ready while any dependency is open', () => {
  for (const base of allOrders()) {
    const order = structuredClone(base);
    order.permits = [{ number: 'P-1', appliedDate: '2026-09-02', startDate: '2026-09-03', endDate: '2026-12-31' }];
    const steps = generate(rules, order);
    // Close every other step to create many partial states.
    steps.forEach((s, i) => { if (i % 2 === 0) order.steps[s.id] = { done: '2026-09-10' }; });
    const r = evaluate(rules, order, '2026-10-11');
    for (const s of r.steps.filter((x) => x.state === 'ready')) {
      for (const d of s.deps) assert.ok(order.steps[d], `${s.id} ready while ${d} open`);
    }
  }
});

test('exhaustive: clearing a step lists exactly the closed steps that depend on it', () => {
  for (const base of allOrders()) {
    if (base.segments.length > 2 || base.meters.length > 1) continue;
    const order = structuredClone(base);
    const steps = generate(rules, order);
    for (const s of steps) order.steps[s.id] = { done: '2026-09-10' };
    for (const s of steps) {
      const impact = new Set(clearImpact(rules, order, s.id));
      assert.ok(!impact.has(s.id));
      for (const t of steps) {
        if (t.deps.includes(s.id)) assert.ok(impact.has(t.id), `${s.id} -> ${t.id} missing`);
      }
    }
  }
});
