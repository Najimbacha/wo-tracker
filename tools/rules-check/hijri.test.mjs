import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { HijriCalendar, formatHijri } from './hijri.mjs';

const root = new URL('../../', import.meta.url);
const json = (p) => JSON.parse(readFileSync(new URL(p, root), 'utf8'));
const table = json('app/assets/calendar/umalqura.json');
const fx = json('app/test/fixtures/hijri.json');
const en = json('app/assets/i18n/en.json');
const ar = json('app/assets/i18n/ar.json');
const cal = new HijriCalendar(table);

const intl = new Intl.DateTimeFormat('en-u-ca-islamic-umalqura', { timeZone: 'UTC', day: 'numeric', month: 'numeric', year: 'numeric' });
function viaIntl(ms) {
  const o = {};
  for (const p of intl.formatToParts(new Date(ms))) if (p.type !== 'literal') o[p.type] = +p.value;
  return { year: o.year, month: o.month, day: o.day };
}

test('every day in the table matches the ICU Umm al-Qura calendar', () => {
  const DAY = 86400000;
  const start = Date.parse(cal.firstDate), end = Date.parse(cal.lastDate);
  let n = 0;
  for (let ms = start; ms <= end; ms += DAY, n++) {
    const ymd = new Date(ms).toISOString().slice(0, 10);
    const h = cal.toHijri(ymd);
    assert.deepEqual(h, viaIntl(ms), ymd);
    assert.equal(cal.fromHijri(h.year, h.month, h.day), ymd, `round trip ${ymd}`);
  }
  assert.ok(n > 14000, `only ${n} days checked`);
});

test('reference dates (official Saudi dates)', () => {
  for (const c of fx.dates) {
    assert.deepEqual(cal.toHijri(c.gregorian), c.hijri, `${c.gregorian} (${c.note})`);
    assert.equal(cal.fromHijri(c.hijri.year, c.hijri.month, c.hijri.day), c.gregorian, c.note);
    assert.equal(formatHijri(cal.toHijri(c.gregorian), monthNames(en)), c.en, c.note);
    assert.equal(formatHijri(cal.toHijri(c.gregorian), monthNames(ar), ar['date.hijriFull']), c.ar, c.note);
  }
});

test('impossible and out-of-range dates', () => {
  for (const c of fx.invalidHijri) assert.equal(cal.fromHijri(...c.input), null, c.note);
  for (const c of fx.outOfRange) assert.equal(cal.toHijri(c), null, c);
  for (const bad of ['2026-02-30', '2026-13-01', '26-10-11', '']) assert.throws(() => cal.toHijri(bad), bad);
});

test('month lengths are 29 or 30 and years are 354 or 355 days', () => {
  for (let y = table.firstYear; y <= table.lastYear; y++) {
    let total = 0;
    for (let m = 1; m <= 12; m++) {
      const len = cal.monthLength(y, m);
      assert.ok(len === 29 || len === 30, `${y}/${m}: ${len}`);
      total += len;
    }
    assert.ok(total === 354 || total === 355, `${y}: ${total}`);
  }
  for (const c of fx.monthLengths) assert.equal(cal.monthLength(c.year, c.month), c.days, `${c.year}/${c.month}`);
});

test('table covers the years the app needs', () => {
  assert.ok(cal.firstDate <= '2019-01-01');
  assert.ok(cal.lastDate >= '2050-12-31');
});

function monthNames(file) {
  return Array.from({ length: 12 }, (_, i) => file[`date.hijri.${i + 1}`]);
}
