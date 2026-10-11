// The report document: figures agree with the report numbers, every label is real text
// in the right language, and the saved cases (used by the Dart test) are up to date.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { reportDocument } from './report-doc.mjs';
import { report, weekRange, monthRange } from './insights.mjs';
import { HijriCalendar } from './hijri.mjs';
import { buildDemo, DEMO_TODAY } from '../sample/demo.mjs';

const root = new URL('../../', import.meta.url);
const json = (p) => JSON.parse(readFileSync(new URL(p, root), 'utf8'));
const rules = json('app/assets/rules/rules.json');
const en = json('app/assets/i18n/en.json');
const ar = json('app/assets/i18n/ar.json');
const hijri = new HijriCalendar(json('app/assets/calendar/umalqura.json'));
const demo = json('app/assets/demo/demo_orders.json');
const fx = json('app/test/fixtures/report_doc.json');

export function buildCase(orders, c) {
  return reportDocument(rules, orders, c.kind, c.date, c.today, {
    lang: c.lang, text: c.lang === 'ar' ? ar : en, english: en, hijri, preparedBy: c.preparedBy, generatedAt: c.generatedAt,
  });
}

test('saved report cases are up to date (run tools/report-preview/gen-fixture.mjs after a deliberate change)', () => {
  for (const c of fx.cases) assert.deepEqual(JSON.parse(JSON.stringify(buildCase(demo.orders, c))), c.doc, `${c.kind} ${c.lang}`);
});

const big = buildDemo(rules, DEMO_TODAY, 7, { volume: 1200, spanDays: 90 });
const kinds = [['daily', DEMO_TODAY], ['weekly', DEMO_TODAY], ['monthly', '2026-09-15']];

for (const [kind, date] of kinds) {
  test(`${kind}: figures match the report numbers`, () => {
    const d = buildCase(big, { kind, date, today: DEMO_TODAY, lang: 'en', preparedBy: 'Engr Najim', generatedAt: `${DEMO_TODAY} 08:00` });
    const range = kind === 'daily' ? { from: date, to: date } : kind === 'weekly' ? weekRange(date) : monthRange(date);
    const asOf = range.to < DEMO_TODAY ? range.to : DEMO_TODAY;
    const r = report(rules, big, range.from, range.to, asOf);
    assert.deepEqual(d.kpis.map((k) => k.value), [r.received, r.stepsCompleted, r.completed, r.attention]);
    assert.equal(d.stages.rows.reduce((s, x) => s + x.value, 0), r.open - (r.byStage.null || 0));
    assert.equal(d.steps.rows.reduce((s, x) => s + x.value, 0), r.stepsCompleted);
    assert.equal(d.delays.rows.length, r.attention);
    assert.equal(d.completed.rows.length, r.completed);
    assert.equal(d.contractors.total.open, r.open);
    assert.equal(d.contractors.rows.reduce((s, x) => s + x.open, 0), r.open);
    assert.equal(d.contractors.rows.reduce((s, x) => s + x.completed, 0), r.completed);
    assert.ok(d.contractors.rows.length <= 7);
    for (const row of d.delays.rows.filter((x) => x.issue.startsWith('Tasreeh expired'))) assert.ok(Number.isInteger(row.days), `${row.wo} has no days`);
    for (const row of d.delays.rows.filter((x) => x.issue.startsWith('Meter not on'))) assert.ok(!row.issue.includes('next: Meter on'), row.issue);
    if (kind === 'daily') assert.equal(d.trend.days.length, 14);
    else assert.equal(d.trend.days.length, (Date.parse(asOf) - Date.parse(range.from)) / 864e5 + 1, 'trend stops at today');
  });

  test(`${kind}: English and Arabic show the same numbers, all text is real text`, () => {
    const opts = { kind, date, today: DEMO_TODAY, preparedBy: 'Engr Najim', generatedAt: `${DEMO_TODAY} 08:00` };
    const e = buildCase(big, { ...opts, lang: 'en' });
    const a = buildCase(big, { ...opts, lang: 'ar' });
    assert.equal(a.dir, 'rtl');
    const numbers = (doc) => JSON.stringify(doc, (k, v) => (typeof v === 'string' ? undefined : v));
    assert.equal(numbers(a), numbers(e));
    const strings = (doc) => { const out = []; JSON.stringify(doc, (k, v) => { if (typeof v === 'string') out.push([k, v]); return v; }); return out; };
    for (const [doc, lang] of [[e, 'en'], [a, 'ar']]) {
      for (const [k, v] of strings(doc)) {
        if (k === 'pageText' || k === 'moreText') continue;
        assert.ok(!/\{\w+(#\w+)?\}/.test(v), `${lang} ${k}: unfilled placeholder in "${v}"`);
        assert.ok(!(v in en), `${lang} ${k}: shows a raw key "${v}"`);
      }
    }
    for (const k of ['eyebrow', 'title', 'preparedBy']) assert.ok(/[؀-ۿ]/.test(a.header[k]) || k === 'preparedBy', `ar header.${k}`);
  });
}

test('a year of orders reports in good time', () => {
  const year = buildDemo(rules, DEMO_TODAY, 11, { volume: 4000, spanDays: 365 });
  const t0 = Date.now();
  buildCase(year, { kind: 'monthly', date: '2026-09-15', today: DEMO_TODAY, lang: 'en', preparedBy: 'x' });
  const ms = Date.now() - t0;
  assert.ok(ms < 8000, `monthly report on ${year.length} orders took ${ms} ms`);
});

test('a report for a past period shows the situation on its last day', async () => {
  const { snapshot } = await import('./insights.mjs');
  const asOf = '2026-09-30';
  const r = report(rules, big, '2026-09-01', asOf, asOf);
  const docsBy = (o) => o.steps.documents_submitted && o.steps.documents_submitted.done && o.steps.documents_submitted.done <= asOf;
  // Cancelled or merged only counts from its own date; before that the order was still active.
  const goneBy = (o) => ['cancelled', 'merged'].includes(o.status.state) && o.status.date <= asOf;
  const expectedOpen = big.filter((o) => !o.deleted && o.receivedDate <= asOf && !goneBy(o) && !docsBy(o)).length;
  assert.equal(r.open, expectedOpen);
  const goneLater = big.filter((o) => !o.deleted && o.receivedDate <= asOf && ['cancelled', 'merged'].includes(o.status.state) && o.status.date > asOf && !docsBy(o));
  assert.ok(goneLater.length > 0, 'the test data has orders cancelled or merged after the period');
  const later = big.filter((o) => o.receivedDate > asOf).length;
  assert.ok(later > 100, 'the test data has orders received after the period');
  // Today's report is unchanged by the rule: nothing is dated after today.
  for (const o of demo.orders) assert.deepEqual(snapshot(o, demo.today), o, o.id);
});

test('snapshot: hand-made case', async () => {
  const { snapshot } = await import('./insights.mjs');
  const o = {
    id: 'S', type: '402', category: 'extension', woNumber: '441799001', receivedDate: '2026-09-20',
    permits: [{ number: 'P1', appliedDate: '2026-09-22', startDate: '2026-09-24', endDate: '2026-10-24' }, { number: 'P2', appliedDate: '2026-10-20', startDate: '2026-10-25', endDate: '2026-11-25' }],
    steps: { kashfeya: { done: '2026-09-21' }, tasreeh_applied: { done: '2026-09-22' }, excavation: { done: '2026-10-02' }, warning_tape: { na: true, reason: 'duct' } },
    status: { state: 'open', holdPeriods: [{ from: '2026-09-26', to: '2026-10-01', reason: 'No material' }] },
    lastChangeDate: '2026-10-02',
  };
  assert.equal(snapshot(o, '2026-09-19'), null);
  const s = snapshot(o, '2026-09-28');
  assert.deepEqual(Object.keys(s.steps), ['kashfeya', 'tasreeh_applied', 'warning_tape']);
  assert.deepEqual(s.permits.map((p) => p.number), ['P1']);
  assert.equal(s.status.state, 'on_hold');
  assert.deepEqual(s.status.holdPeriods, [{ from: '2026-09-26', to: null, reason: 'No material' }]);
  assert.equal(s.lastChangeDate, '2026-09-22');
  const s2 = snapshot(o, '2026-10-05');
  assert.equal(s2.status.state, 'open');
  assert.equal(s2.lastChangeDate, '2026-10-02');
  assert.deepEqual(s2.permits.map((p) => p.number), ['P1']);
});

// Hand-computed report behaviour (added after the post-mortem).
const meterOnly = (id, receivedDate) => ({ id, type: '801', category: 'extension', woNumber: `4417${id}`, receivedDate, meters: [{ id: 'm1' }], steps: {}, status: { state: 'open', holdPeriods: [] } });
const enOpts = { lang: 'en', text: en, english: en, hijri: null, preparedBy: 'x' };

test('snapshot: cancelled and merged count only from their own date', async () => {
  const { snapshot } = await import('./insights.mjs');
  const base = { id: 'C', type: '802', category: 'extension', woNumber: '441799002', receivedDate: '2026-09-10', steps: { kashfeya: { done: '2026-09-11' } }, lastChangeDate: '2026-09-11' };
  const cancelled = { ...base, status: { state: 'cancelled', reason: 'Customer withdrew', date: '2026-09-20', holdPeriods: [] } };
  assert.equal(snapshot(cancelled, '2026-09-19').status.state, 'open');
  assert.equal(snapshot(cancelled, '2026-09-19').status.reason, undefined);
  assert.equal(snapshot(cancelled, '2026-09-20').status.state, 'cancelled');
  // Put on hold on the 15th, cancelled on the 20th: the hold was still running on the 18th.
  const held = { ...base, status: { state: 'cancelled', reason: 'Customer withdrew', date: '2026-09-20', holdPeriods: [{ from: '2026-09-15', to: '2026-09-20', reason: 'Objection' }] } };
  assert.equal(snapshot(held, '2026-09-18').status.state, 'on_hold');
  const merged = { ...base, status: { state: 'merged', reason: 'New WO', mergedInto: 'X', date: '2026-09-25', holdPeriods: [] } };
  assert.equal(snapshot(merged, '2026-09-24').status.state, 'open');
  assert.equal(snapshot(merged, '2026-09-24').status.mergedInto, undefined);
  assert.equal(snapshot(merged, '2026-09-25').status.mergedInto, 'X');
  // Saved before the date was stored: cancelled throughout, as before.
  const old = { ...base, status: { state: 'cancelled', reason: 'Old', holdPeriods: [] } };
  assert.equal(snapshot(old, '2026-09-12').status.state, 'cancelled');
});

test('running week: only the days so far, compared with the same days last week', () => {
  // Sunday 11 Oct: the week is Sat 10 – Fri 16. Two received this Sat/Sun; last week Sat/Sun had two, Monday one more.
  const os = [meterOnly('00010', '2026-10-10'), meterOnly('00011', '2026-10-11'), meterOnly('00003', '2026-10-03'), meterOnly('00004', '2026-10-04'), meterOnly('00005', '2026-10-05')];
  const d = reportDocument(rules, os, 'weekly', '2026-10-11', '2026-10-11', enOpts);
  assert.deepEqual(d.trend.days.map((x) => x.date), ['2026-10-10', '2026-10-11']);
  assert.equal(d.kpis[0].value, 2);
  assert.equal(d.kpis[0].label, 'Received this week');
  assert.equal(d.kpis[0].note, '±0 vs same days last week');
  assert.equal(d.trend.summary, 'Average per day: 1.0 received, 0.0 completed.');
  assert.equal(d.contractors.subtitle, 'Open orders now');
});

test('a finished week is compared with the whole previous week', () => {
  const os = [meterOnly('00010', '2026-10-10'), meterOnly('00003', '2026-10-03'), meterOnly('00004', '2026-10-04'), meterOnly('00005', '2026-10-05')];
  const d = reportDocument(rules, os, 'weekly', '2026-10-05', '2026-10-11', enOpts);
  assert.equal(d.kpis[0].value, 3);
  assert.equal(d.kpis[0].label, 'Received that week');
  assert.equal(d.kpis[0].note, '+3 vs previous week');
  assert.equal(d.trend.days.length, 7);
  assert.equal(d.contractors.subtitle, 'Open at the end of the period');
});

test('a past day says "that day", not "today"', () => {
  const d = reportDocument(rules, [meterOnly('00003', '2026-10-03'), meterOnly('00004', '2026-10-04')], 'daily', '2026-10-04', '2026-10-11', enOpts);
  assert.equal(d.kpis[0].label, 'Received that day');
  assert.equal(d.kpis[0].note, '±0 vs previous day');
  assert.equal(d.contractors.subtitle, 'Open at the end of the period');
});

test('tasreeh ending rows say how many days are left', () => {
  const o = (id, end) => ({ id, type: '802', category: 'extension', woNumber: `4417${id}`, receivedDate: '2026-09-20', contractor: 'C',
    segments: [{ id: 's1', base: 'soil', width: 40, lengthM: 5 }], cableRuns: [{ sizeMm2: 70, voltage: 'LV', lengthM: 9 }],
    permits: [{ number: `P${id}`, appliedDate: '2026-09-21', startDate: '2026-09-22', endDate: end }],
    steps: { kashfeya: { done: '2026-09-20' }, tasreeh_applied: { done: '2026-09-21' }, excavation: { done: '2026-10-10' } }, status: { state: 'open', holdPeriods: [] } });
  const d = reportDocument(rules, [o('00001', '2026-10-14'), o('00002', '2026-10-11')], 'daily', '2026-10-11', '2026-10-11', enOpts);
  const issues = d.delays.rows.map((r) => r.issue).sort();
  assert.deepEqual(issues, ['Tasreeh ends in 3 days · next: Cable installed', 'Tasreeh ends today · next: Cable installed']);
});

test('a report for a period that has not started is refused', () => {
  assert.throws(() => reportDocument(rules, [], 'weekly', '2026-10-20', '2026-10-11', enOpts));
});
