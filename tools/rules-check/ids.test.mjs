import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { uuidV5, stepRowId, STEP_ID_NAMESPACE } from './ids.mjs';

const fx = JSON.parse(readFileSync(new URL('../../app/test/fixtures/ids.json', import.meta.url), 'utf8'));

test('version 5 ids match the standard (checked against Python)', () => {
  assert.equal(uuidV5(fx.rfcCheck.namespace, fx.rfcCheck.name), fx.rfcCheck.id);
  assert.equal(STEP_ID_NAMESPACE, fx.namespace);
});

test('step row ids match the independently computed values', () => {
  for (const c of fx.cases) assert.equal(stepRowId(c.workOrderId, c.stepKey, c.segmentId, c.meterId), c.id, `${c.stepKey}`);
});

test('two devices get the same id for the same step, different ids for different steps', () => {
  const a = stepRowId('w1', 'meter_on', null, 'm1');
  assert.equal(stepRowId('w1', 'meter_on', null, 'm1'), a);
  assert.notEqual(stepRowId('w1', 'meter_on', null, 'm2'), a);
  assert.notEqual(stepRowId('w2', 'meter_on', null, 'm1'), a);
  assert.match(a, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});
