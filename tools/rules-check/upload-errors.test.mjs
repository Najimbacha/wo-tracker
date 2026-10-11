import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classifyUploadError, RETRY_DELAYS, UPLOAD_CODES } from './upload-errors.mjs';

const fx = JSON.parse(readFileSync(new URL('../../app/test/fixtures/upload_errors.json', import.meta.url), 'utf8'));

test('retry delays match the fixture', () => assert.deepEqual(RETRY_DELAYS, fx.retryDelays));

for (const c of fx.cases) {
  test(`refused upload: ${c.name}`, () => {
    const r = classifyUploadError(c.error, c.attempt, c.row ?? null);
    assert.deepEqual(r, c.expect);
    assert.ok(c.expect.code in UPLOAD_CODES, `${c.expect.code} is a known code`);
  });
}

test('every code is used by at least one case', () => {
  const used = new Set(fx.cases.map((c) => c.expect.code));
  for (const code of Object.keys(UPLOAD_CODES)) assert.ok(used.has(code), code);
});
