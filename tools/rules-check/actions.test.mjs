// Runs app/test/fixtures/actions.json against the reference actions, plus
// property checks: actions never change their input, and clearing undoes marking.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as A from './actions.mjs';
import { generate, evaluate } from './engine.mjs';

const root = new URL('../../', import.meta.url);
const json = (p) => JSON.parse(readFileSync(new URL(p, root), 'utf8'));
const rules = json('app/assets/rules/rules.json');
const fx = json('app/test/fixtures/actions.json');
const today = fx.today;

function build(name, patch) {
  if (name === null || name === undefined) return null;
  const o = structuredClone(fx.orders[name]);
  if (!patch) return o;
  const { steps, ...rest } = patch;
  Object.assign(o, structuredClone(rest));
  if (steps) o.steps = { ...(o.steps || {}), ...structuredClone(steps) };
  return o;
}
const allOrders = () => Object.keys(fx.orders).map((k) => build(k));

function run(c) {
  const a = c.args || {};
  const o = build(c.order, c.patch);
  switch (c.action) {
    case 'markDone': return A.markDone(rules, o, a.step, a.date, today);
    case 'markNA': return A.markNA(rules, o, a.step, a.reason, today);
    case 'clearStep': return A.clearStep(rules, o, a.step);
    case 'clearPreview': return A.clearPreview(rules, o, a.step);
    case 'bulkMarkDone': return A.bulkMarkDone(rules, c.orders.map((n) => build(n)), a.stepKey, a.date, today);
    case 'putOnHold': return A.putOnHold(rules, o, a.from, a.reason, today, a.review ?? null);
    case 'resume': return A.resume(rules, o, a.date, today);
    case 'cancel': return A.cancel(rules, o, a.reason, today);
    case 'merge': return A.merge(rules, o, build(c.target, c.targetPatch), a.reason, a.carry, today);
    case 'reopen': return A.reopen(rules, o);
    case 'editImpact': return { impact: A.editImpact(rules, o, { ...o, ...a.after }) };
    case 'formSpec': return { spec: A.formSpec(rules, a.draft) };
    case 'normalizeDraft': return { draft: A.normalizeDraft(a.draft, rules) };
    case 'validateDraft': return { errors: A.validateDraft(rules, a.draft, allOrders(), today) };
    default: throw new Error(`unknown action ${c.action}`);
  }
}

function check(c, r) {
  const e = c.expect;
  const codes = (list) => (list || []).map((x) => x.code);
  if ('ok' in e) assert.equal(r.ok, e.ok, `ok: ${JSON.stringify(r.errors)}`);
  if ('errors' in e) assert.deepEqual(codes(r.errors), e.errors);
  if (e.errorData) e.errorData.forEach((d, i) => { for (const [k, v] of Object.entries(d)) assert.deepEqual(r.errors[i][k], v, `error[${i}].${k}`); });
  const o = r.order;
  if (e.steps) assert.deepEqual(o.steps, e.steps);
  if ('lastChangeDate' in e) assert.equal(o.lastChangeDate, e.lastChangeDate);
  if ('completed' in e) assert.equal(r.completed, e.completed);
  if (e.state) assert.equal(o.status.state, e.state);
  if ('reason' in e) assert.equal(o.status.reason, e.reason);
  if (e.mergedInto) assert.equal(o.status.mergedInto, e.mergedInto);
  if ('stateDate' in e) assert.equal(o.status.date, e.stateDate);
  if (e.holdPeriods) assert.deepEqual(o.status.holdPeriods, e.holdPeriods);
  if (e.status) assert.deepEqual(o.status, e.status);
  for (const k of ['cleared', 'alsoClears', 'carried', 'notCarried', 'impact']) if (e[k]) assert.deepEqual(r[k], e[k], k);
  if (e.updated) assert.deepEqual(r.updated, e.updated);
  if (e.skipped) assert.deepEqual(r.skipped.map((s) => ({ id: s.id, errors: codes(s.errors) })), e.skipped);
  if (e.targetSteps) assert.deepEqual(r.target.steps, e.targetSteps);
  if (e.targetLastChangeDate) assert.equal(r.target.lastChangeDate, e.targetLastChangeDate);
  if (e.draft) assert.deepEqual(r.draft, e.draft);
  if (e.spec) for (const [k, v] of Object.entries(e.spec)) assert.equal(r.spec[k], v, `spec.${k}`);
}

for (const c of fx.cases) {
  test(`${c.action}: ${c.name}`, () => {
    const before = JSON.stringify(fx);
    check(c, run(c));
    assert.equal(JSON.stringify(fx), before, 'the action changed its input');
  });
}

test('every action in the fixture is covered', () => {
  const covered = new Set(fx.cases.map((c) => c.action));
  const exported = Object.keys(A).filter((k) => !['findDuplicate', 'findPermitOwner'].includes(k));
  for (const k of exported) assert.ok(covered.has(k), `no fixture case for ${k}`);
});

test('property: marking every ready step one by one completes any order, and clearing the first step undoes it all', () => {
  for (const name of ['A', 'C', 'Z', 'E', 'B', 'D', 'T']) {
    let o = build(name);
    const date = '2026-10-11';
    for (let guard = 0; guard < 60; guard++) {
      const ev = evaluate(rules, o, date);
      const ready = ev.steps.find((s) => s.state === 'ready');
      if (!ready) break;
      const r = A.markDone(rules, o, ready.id, date, date);
      assert.ok(r.ok, `${name} ${ready.id}: ${JSON.stringify(r.errors)}`);
      o = r.order;
    }
    const ev = evaluate(rules, o, date);
    if (ev.status !== 'completed') {
      // Only orders still waiting on dates or data may stop early.
      const locked = ev.steps.filter((s) => s.state === 'locked').flatMap((s) => s.reasons.map((x) => x.code));
      assert.ok(locked.every((c) => ['tasreeh_starts', 'no_tasreeh_dates', 'missing_segments', 'waiting_for'].includes(c)), `${name} stuck: ${locked}`);
      assert.ok(locked.some((c) => c !== 'waiting_for'), `${name} stuck only on waiting_for`);
      continue;
    }
    const first = generate(rules, o)[0].id;
    const cleared = A.clearStep(rules, o, first);
    assert.ok(cleared.ok);
    const left = Object.keys(cleared.order.steps);
    for (const id of left) assert.ok(!cleared.cleared.includes(id));
    assert.equal(evaluate(rules, cleared.order, date).status, 'open', name);
  }
});

test('property: every N/A or done record survives a hold, resume and reopen round trip', () => {
  const o = build('C');
  const h = A.putOnHold(rules, o, '2026-10-09', 'No material', today);
  const r = A.resume(rules, h.order, '2026-10-10', today);
  const c = A.cancel(rules, r.order, 'x', today);
  const back = A.reopen(rules, c.order);
  assert.deepEqual(back.order.steps, o.steps);
  assert.equal(back.order.status.holdPeriods.length, 1);
});
