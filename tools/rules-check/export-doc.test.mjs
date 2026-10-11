// The two Excel files: every sheet is well formed, the figures agree with the report,
// and the data copy turns back into exactly the same orders.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { reportWorkbook, dataWorkbook, ordersFromDataWorkbook, canonicalOrder } from './export-doc.mjs';
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
const big = buildDemo(rules, DEMO_TODAY, 7, { volume: 1200, spanDays: 90 });

const opts = (lang) => ({ lang, text: lang === 'ar' ? ar : en, english: en, hijri, preparedBy: 'Engr Najim', generatedAt: `${DEMO_TODAY} 08:00` });
const TYPES = new Set(['text', 'int', 'decimal', 'date', 'bool']);

function checkWorkbook(wb) {
  const names = wb.sheets.map((s) => s.name);
  assert.equal(new Set(names).size, names.length, 'sheet names are unique');
  for (const s of wb.sheets) {
    assert.ok(s.name.length > 0 && s.name.length <= 31 && !/[[\]:*?/\\]/.test(s.name), `bad sheet name "${s.name}"`);
    const keys = s.columns.map((c) => c.key);
    for (const c of s.columns) assert.ok(TYPES.has(c.type), `${s.name}.${c.key} type ${c.type}`);
    if (s.kind !== 'table') continue;
    for (const row of s.rows) {
      for (const k of Object.keys(row)) assert.ok(keys.includes(k) || k === 'style', `${s.name}: unexpected field ${k}`);
      for (const c of s.columns) {
        const v = row[c.key];
        if (v === null || v === undefined || v === '') continue;
        if (c.type === 'int') assert.ok(Number.isInteger(v), `${s.name}.${c.key} = ${v}`);
        if (c.type === 'decimal') assert.equal(typeof v, 'number', `${s.name}.${c.key}`);
        if (c.type === 'date') assert.match(v, /^\d{4}-\d{2}-\d{2}$/, `${s.name}.${c.key}`);
        if (c.type === 'bool') assert.equal(typeof v, 'boolean', `${s.name}.${c.key}`);
      }
    }
    for (const f of Object.values(s.rowFormulas || {})) for (const k of f.ratio) assert.ok(keys.includes(k));
    if (s.totals) for (const k of s.totals.sum) assert.ok(keys.includes(k));
  }
}

for (const [kind, date] of [['daily', DEMO_TODAY], ['weekly', DEMO_TODAY], ['monthly', '2026-09-15']]) {
  for (const lang of ['en', 'ar']) {
    test(`${kind} report workbook (${lang}) is well formed and complete`, () => {
      const wb = reportWorkbook(rules, big, kind, date, DEMO_TODAY, opts(lang));
      checkWorkbook(wb);
      assert.equal(wb.dir, lang === 'ar' ? 'rtl' : 'ltr');
      const range = kind === 'daily' ? { from: date, to: date } : kind === 'weekly' ? weekRange(date) : monthRange(date);
      const asOf = range.to < DEMO_TODAY ? range.to : DEMO_TODAY;
      const r = report(rules, big, range.from, range.to, asOf);
      const [, attention, contractors, completed, open] = wb.sheets;
      assert.equal(attention.rows.length, r.attention, 'every order needing attention, not only the top 25');
      assert.equal(completed.rows.length, r.completed);
      assert.equal(open.rows.length, r.open);
      assert.equal(contractors.rows.length, r.contractors.length);
      assert.equal(contractors.rows.reduce((a, c) => a + c.open, 0), r.open, 'contractor totals add up');
      for (const c of contractors.rows) assert.equal(c.avgDays, c.finished ? Math.round(c.totalDays / c.finished) : null, 'the average formula gives the same value');
      for (const row of completed.rows) assert.ok(row.completedOn >= range.from && row.completedOn <= range.to);
      // Columns that must never be empty.
      const required = { [open.name]: ['wo', 'type', 'received', 'status', 'closed', 'total'], [attention.name]: ['wo', 'issue', 'severity'], [completed.name]: ['wo', 'received', 'completedOn', 'days'] };
      for (const s of wb.sheets) for (const k of required[s.name] || []) for (const row of s.rows) assert.ok(row[k] !== null && row[k] !== undefined && row[k] !== '', `${s.name}: empty ${k} for ${row.wo}`);
      for (const row of open.rows) assert.ok(row.closed < row.total, `${row.wo}: open order with all steps done`);
      assert.ok(wb.fileName.endsWith('.xlsx') && !/[\\/:*?"<>|]/.test(wb.fileName));
    });
  }
}

test('the data copy turns back into exactly the same orders (demo and 1,200 orders)', () => {
  for (const orders of [demo.orders, big]) {
    const wb = dataWorkbook(rules, orders, DEMO_TODAY);
    checkWorkbook(wb);
    // Through JSON, as a file would be: no shared objects, only plain values.
    const back = ordersFromDataWorkbook(JSON.parse(JSON.stringify(wb)));
    assert.equal(back.length, orders.length);
    for (let i = 0; i < orders.length; i++) assert.deepEqual(canonicalOrder(back[i]), canonicalOrder(orders[i]), orders[i].id);
  }
});

test('meter type, breaker amps and step notes survive the round trip', () => {
  const o = { id: 'N1', type: '801', category: 'extension', woNumber: '441700901', receivedDate: '2026-10-01',
    meters: [{ id: 'm1', number: '55501234', meterType: 'ct', breakerAmps: 200 }],
    steps: { 'meter_installed@m1': { done: '2026-10-02', note: 'In the annex' }, 'meter_on@m1': { note: 'Waiting for the customer' } },
    status: { state: 'open', holdPeriods: [] } };
  const back = ordersFromDataWorkbook(JSON.parse(JSON.stringify(dataWorkbook(rules, [o], DEMO_TODAY))));
  assert.deepEqual(canonicalOrder(back[0]), canonicalOrder(o));
  assert.equal(back[0].meters[0].meterType, 'ct');
  assert.equal(back[0].steps['meter_on@m1'].note, 'Waiting for the customer');
});

test('an order completed with documents marked not applicable appears in the Completed sheet with its date', () => {
  const o = { id: 'N2', type: '801', category: 'extension', woNumber: '441700902', receivedDate: '2026-10-01', meters: [{ id: 'm1' }],
    steps: { 'meter_installed@m1': { done: '2026-10-02' }, 'meter_on@m1': { done: '2026-10-03' }, 'form_190@m1': { done: '2026-10-04' }, 'form_200@m1': { done: '2026-10-05' },
      certificate: { done: '2026-10-06' }, documents_submitted: { na: true, reason: 'SEC closed it' } }, status: { state: 'open', holdPeriods: [] } };
  const wb = reportWorkbook(rules, [o], 'weekly', '2026-10-06', DEMO_TODAY, opts('en'));
  const done = wb.sheets[3].rows;
  assert.deepEqual(done.map((r) => [r.wo, r.completedOn, r.days]), [['441700902', '2026-10-06', 5]]);
});

test('the data copy includes deleted orders, every step record, tasreeh and hold', () => {
  const wb = dataWorkbook(rules, demo.orders, DEMO_TODAY);
  const sheet = (k) => wb.sheets.find((s) => s.key === k).rows;
  assert.equal(sheet('orders').filter((r) => r.deleted).length, demo.orders.filter((o) => o.deleted).length);
  assert.equal(sheet('steps').length, demo.orders.reduce((a, o) => a + Object.keys(o.steps).length, 0));
  assert.equal(sheet('permits').length, demo.orders.reduce((a, o) => a + o.permits.length, 0));
  assert.equal(sheet('holds').length, demo.orders.reduce((a, o) => a + o.status.holdPeriods.length, 0));
  assert.ok(sheet('steps').some((r) => r.na && r.reason));
});

test('a deliberately damaged copy is caught by the round-trip check', () => {
  const wb = JSON.parse(JSON.stringify(dataWorkbook(rules, demo.orders, DEMO_TODAY)));
  wb.sheets.find((s) => s.key === 'permits').rows.pop();
  const back = ordersFromDataWorkbook(wb);
  const differs = back.some((o, i) => JSON.stringify(canonicalOrder(o)) !== JSON.stringify(canonicalOrder(demo.orders[i])));
  assert.ok(differs);
});

test('saved export cases are up to date (run tools/report-preview/gen-fixture.mjs after a deliberate change)', () => {
  const fx = json('app/test/fixtures/export_doc.json');
  for (const c of fx.report) {
    const wb = reportWorkbook(rules, demo.orders, c.kind, c.date, c.today, { ...opts(c.lang), preparedBy: c.preparedBy, generatedAt: c.generatedAt });
    assert.deepEqual(JSON.parse(JSON.stringify(wb)), c.workbook, `${c.kind} ${c.lang}`);
  }
  assert.deepEqual(JSON.parse(JSON.stringify(dataWorkbook(rules, demo.orders, fx.data.today, fx.data.generatedAt))), fx.data.workbook);
});

// Every column of every order table in the database is either in the Excel data copy or
// listed here with the reason it is left out. A new column added to the database fails
// this test until one of the two is done.
test('the data copy covers every column of the order tables in the database', () => {
  const sql = readFileSync(new URL('supabase/migrations/20261011000001_initial.sql', root), 'utf8');
  const columnsOf = (table) => {
    const m = sql.match(new RegExp(`create table public\\.${table} \\(([\\s\\S]*?)\\n\\);`));
    assert.ok(m, `table ${table} not found`);
    return m[1].split('\n').map((l) => l.trim()).filter((l) => /^[a-z_]+\s/.test(l) && !l.startsWith('constraint')).map((l) => l.split(/\s+/)[0]);
  };
  const leftOut = {
    _all: { id: 'row id (the copy uses its own order, segment and meter ids)', owner_id: 'account, set by the server', created_at: 'server time', updated_at: 'server time', deleted_at: 'deleted parts are history, kept in the nightly backup' },
    work_orders: { rules_version: 'always 1 so far', status_cache: 'recalculated', stage_cache: 'recalculated', progress_closed: 'recalculated', progress_total: 'recalculated', deleted_at: null },
    meters: { seq: 'the order of the meter rows' },
    steps: { work_order_id: 'the row is under its order', step_key: 'part of Step id', segment_id: 'part of Step id', meter_id: 'part of Step id' },
  };
  const DB_TO_COPY = {
    work_orders: { wo_number: 'woNumber', category: 'category', type_code: 'type', received_date: 'receivedDate', district_id: 'district', street: 'street', network_ref: 'networkRef', contractor_id: 'contractor', needs_excavation: 'needsExcavation', state: 'state', state_reason: 'stateReason', merged_into: 'mergedInto', notes: 'notes', last_change_date: 'lastChangeDate', deleted_at: 'deleted' },
    permits: { work_order_id: 'orderId', permit_number: 'number', applied_date: 'appliedDate', start_date: 'startDate', end_date: 'endDate' },
    segments: { work_order_id: 'orderId', base: 'base', width_cm: 'width', length_m: 'lengthM', tiled: 'tiled' },
    meters: { work_order_id: 'orderId', meter_number: 'number', meter_type: 'meterType', breaker_amps: 'breakerAmps', old_meter_number: 'oldNumber' },
    cable_runs: { work_order_id: 'orderId', size_mm2: 'sizeMm2', voltage: 'voltage', length_m: 'lengthM' },
    steps: { done_date: 'done', not_applicable: 'na', na_reason: 'reason', note: 'note' },
    hold_periods: { work_order_id: 'orderId', from_date: 'from', to_date: 'to', reason: 'reason', review_date: 'review' },
  };
  const sheetFor = { work_orders: 'orders', permits: 'permits', segments: 'segments', meters: 'meters', cable_runs: 'cableRuns', steps: 'steps', hold_periods: 'holds' };
  const wb = dataWorkbook(rules, [], DEMO_TODAY);
  for (const [table, map] of Object.entries(DB_TO_COPY)) {
    const copyCols = wb.sheets.find((s) => s.key === sheetFor[table]).columns.map((c) => c.key);
    for (const col of columnsOf(table)) {
      if (map[col]) { assert.ok(copyCols.includes(map[col]), `${table}.${col} maps to ${map[col]}, which the copy does not have`); continue; }
      const reason = (leftOut[table] || {})[col] ?? leftOut._all[col];
      assert.ok(reason, `${table}.${col} is neither in the data copy nor listed as left out`);
    }
  }
});
