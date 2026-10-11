// Builds app/assets/calendar/umalqura.json: the Gregorian date on which each
// Umm al-Qura month starts, from the ICU calendar data built into Node.js.
// Run: node tools/calendar/gen-umalqura.mjs
import { writeFileSync } from 'node:fs';

const FIRST_YEAR = 1440; // starts 2018-09-11
const LAST_YEAR = 1480;  // ends 2059

const fmt = new Intl.DateTimeFormat('en-u-ca-islamic-umalqura', { timeZone: 'UTC', day: 'numeric', month: 'numeric', year: 'numeric' });
const parts = (ms) => {
  const o = {};
  for (const p of fmt.formatToParts(new Date(ms))) if (p.type !== 'literal') o[p.type] = p.value;
  return { y: +o.year, m: +o.month, d: +o.day };
};
const iso = (ms) => new Date(ms).toISOString().slice(0, 10);
const DAY = 86400000;

const starts = [];
for (let ms = Date.UTC(2018, 7, 1); starts.length < (LAST_YEAR - FIRST_YEAR + 1) * 12 + 1; ms += DAY) {
  const h = parts(ms);
  if (h.d !== 1 || h.y < FIRST_YEAR) continue;
  const expected = FIRST_YEAR * 12 + starts.length;
  if (h.y * 12 + h.m - 1 !== expected) throw new Error(`month out of order at ${iso(ms)}`);
  starts.push(iso(ms));
}
for (let i = 1; i < starts.length; i++) {
  const len = (Date.parse(starts[i]) - Date.parse(starts[i - 1])) / DAY;
  if (len !== 29 && len !== 30) throw new Error(`month ${i} has ${len} days`);
}

const out = {
  calendar: 'Umm al-Qura',
  source: `ICU islamic-umalqura (Node ${process.versions.node}, ICU ${process.versions.icu})`,
  firstYear: FIRST_YEAR,
  lastYear: LAST_YEAR,
  note: 'monthStarts[i] is day 1 of month (i % 12) + 1 of year firstYear + floor(i / 12). The last entry is 1 Muharram of lastYear + 1 and only marks where the table ends.',
  monthStarts: starts,
};
const target = new URL('../../app/assets/calendar/umalqura.json', import.meta.url);
// One Hijri year per line, so the file is easy to check by eye.
const { monthStarts, ...head } = out;
const rows = [];
for (let i = 0; i < monthStarts.length; i += 12) {
  rows.push(`    ${monthStarts.slice(i, i + 12).map((d) => JSON.stringify(d)).join(', ')}`);
}
const headJson = JSON.stringify(head, null, 2).slice(0, -2);
writeFileSync(target, `${headJson},\n  "monthStarts": [\n${rows.join(',\n')}\n  ]\n}\n`);
console.log(`wrote ${starts.length} month starts, ${starts[0]} to ${starts.at(-1)}`);
