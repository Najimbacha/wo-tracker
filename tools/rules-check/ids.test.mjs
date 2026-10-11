import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, randomBytes } from 'node:crypto';
import { uuidV5, stepRowId, STEP_ID_NAMESPACE, sha1Plain, uuidV5Plain } from './ids.mjs';

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

test('the plain SHA-1 the Dart app copies matches node:crypto', () => {
  const lengths = [0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 128, 1000];
  for (let n = 0; n < 300; n++) lengths.push(n);
  for (const len of lengths) {
    const bytes = randomBytes(len);
    assert.equal(Buffer.from(sha1Plain(bytes)).toString('hex'), createHash('sha1').update(bytes).digest('hex'), `length ${len}`);
  }
  assert.equal(Buffer.from(sha1Plain(new TextEncoder().encode('abc'))).toString('hex'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
});

test('the plain version 5 ids match, including the fixture values', () => {
  assert.equal(uuidV5Plain(fx.rfcCheck.namespace, fx.rfcCheck.name), fx.rfcCheck.id);
  for (const c of fx.cases) {
    assert.equal(uuidV5Plain(fx.namespace, `${c.workOrderId}|${c.stepKey}|${c.segmentId || ''}|${c.meterId || ''}`), c.id);
  }
  for (let n = 0; n < 200; n++) {
    const name = `${randomBytes(16).toString('hex')}|step_${n}|ع${n}|`;
    assert.equal(uuidV5Plain(STEP_ID_NAMESPACE, name), uuidV5(STEP_ID_NAMESPACE, name));
  }
});

test('the plain SHA-1 matches the Python vectors the Dart test uses', () => {
  for (const v of fx.sha1) assert.equal(Buffer.from(sha1Plain(new TextEncoder().encode(v.text))).toString('hex'), v.sha1, `length ${v.text.length}`);
});
