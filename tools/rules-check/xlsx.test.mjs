// The package-free Excel writer: the zip must be valid, and openpyxl (and LibreOffice,
// when installed) must read back exactly what the workbook model holds.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { crc32, zipStored, workbookXlsx, colLetter, excelDate, sheetName } from './xlsx.mjs';

const fx = JSON.parse(readFileSync(new URL('../../app/test/fixtures/export_doc.json', import.meta.url), 'utf8'));
const dir = mkdtempSync(join(tmpdir(), 'xlsx-'));
const has = (cmd) => { try { execFileSync('which', [cmd]); return true; } catch { return false; } };

test('crc32 and helpers', () => {
  assert.equal(crc32(new TextEncoder().encode('The quick brown fox jumps over the lazy dog')), 0x414fa339);
  assert.equal(colLetter(1), 'A'); assert.equal(colLetter(26), 'Z'); assert.equal(colLetter(27), 'AA'); assert.equal(colLetter(703), 'AAA');
  assert.equal(excelDate('1900-03-01'), 61); assert.equal(excelDate('2026-10-11'), 46306);
  const used = new Set();
  assert.equal(sheetName('Needs: attention?', used), 'Needs  attention');
  assert.equal(sheetName('A'.repeat(40), used), 'A'.repeat(31));
  assert.equal(sheetName('A'.repeat(40), used), 'A'.repeat(27) + ' (2)');
});

test('stored zip opens with unzip', { skip: !has('unzip') }, () => {
  const z = zipStored([{ name: 'a.txt', data: new TextEncoder().encode('hello') }, { name: 'ج/ب.txt', data: new TextEncoder().encode('مرحبا') }]);
  const p = join(dir, 't.zip');
  writeFileSync(p, z);
  const out = execFileSync('unzip', ['-t', p]).toString();
  assert.match(out, /No errors detected/);
});

const PY = `
import json, sys, datetime
from openpyxl import load_workbook
wb = load_workbook(sys.argv[1])
out = {}
for ws in wb.worksheets:
    rows = [[(c.value.isoformat()[:10] if isinstance(c.value, datetime.datetime) else c.value) for c in r] for r in ws.iter_rows()]
    out[ws.title] = {'rows': rows, 'freeze': ws.freeze_panes, 'filter': ws.auto_filter.ref, 'rtl': bool(ws.sheet_view.rightToLeft),
                     'formats': [c.number_format for c in (list(ws.iter_rows(min_row=2, max_row=2))[0] if ws.max_row >= 2 else [])],
                     'orientation': ws.page_setup.orientation, 'fitW': ws.page_setup.fitToWidth}
print(json.dumps(out, ensure_ascii=False, default=str))
`;

function readBack(path) {
  return JSON.parse(execFileSync('python3', ['-c', PY, path], { maxBuffer: 1 << 26 }).toString());
}

for (const c of fx.report) {
  test(`report workbook reads back: ${c.kind} ${c.lang}`, { skip: !has('python3') }, () => {
    const wb = c.workbook;
    const p = join(dir, wb.fileName.replace('.xlsx', `-${c.lang}.xlsx`));
    writeFileSync(p, workbookXlsx(wb));
    const back = readBack(p);
    assert.deepEqual(Object.keys(back), wb.sheets.map((s) => s.name));
    for (const sh of wb.sheets) {
      const b = back[sh.name];
      assert.equal(b.rtl, wb.dir === 'rtl', `${sh.name} direction`);
      if (sh.kind === 'summary') {
        sh.rows.forEach((row, i) => {
          if (row.kind === 'blank') return;
          assert.equal(b.rows[i][0], row.label, `${sh.name} row ${i}`);
          if (row.kind === 'item' && row.value !== undefined && row.value !== null) assert.equal(b.rows[i][1], row.value);
          if (row.kind === 'item' && row.note) assert.equal(b.rows[i][2], row.note);
        });
        continue;
      }
      assert.deepEqual(b.rows[0], sh.columns.map((col) => col.label), `${sh.name} header`);
      assert.equal(b.freeze, 'A2');
      if (sh.rows.length) assert.equal(b.filter, `A1:${colLetter(sh.columns.length)}${sh.rows.length + 1}`);
      sh.rows.forEach((row, i) => sh.columns.forEach((col, j) => {
        const got = b.rows[i + 1][j];
        if (sh.rowFormulas && sh.rowFormulas[col.key]) { assert.match(String(got), /^=IF\(/); return; }
        const want = row[col.key];
        if (want === null || want === undefined || want === '') assert.equal(got, null, `${sh.name}[${i}].${col.key}`);
        else assert.equal(got, want, `${sh.name}[${i}].${col.key}`);
      }));
      if (sh.totals) assert.match(String(b.rows[sh.rows.length + 1][1]), /^=SUM\(B2:B\d+\)$/);
      const dateCol = sh.columns.findIndex((col) => col.type === 'date');
      if (dateCol >= 0 && sh.rows.length) assert.equal(b.formats[dateCol], 'dd/mm/yyyy');
    }
  });
}

test('data workbook reads back, with its About sheet', { skip: !has('python3') }, () => {
  const wb = fx.data.workbook;
  const p = join(dir, wb.fileName);
  writeFileSync(p, workbookXlsx(wb));
  const back = readBack(p);
  assert.deepEqual(Object.keys(back), [...wb.sheets.map((s) => s.name), 'About']);
  const orders = wb.sheets.find((s) => s.key === 'orders');
  assert.equal(back.Orders.rows.length, orders.rows.length + 1);
  const i = orders.columns.findIndex((c) => c.key === 'woNumber');
  assert.deepEqual(back.Orders.rows.slice(1).map((r) => r[i]), orders.rows.map((r) => r.woNumber));
  assert.equal(back.About.rows[3][1], wb.about.format);
});

test('LibreOffice opens the file and calculates the formulas', { skip: !has('soffice') }, () => {
  const c = fx.report.find((r) => r.workbook.sheets.some((s) => s.totals));
  const p = join(dir, 'calc.xlsx');
  writeFileSync(p, workbookXlsx(c.workbook));
  execFileSync('soffice', ['--headless', '--convert-to', 'csv:Text - txt - csv (StarCalc):44,34,76,1,,0,false,true,false,false,false,3', '--outdir', dir, p], { timeout: 120000, stdio: 'ignore' });
  const sheetIndex = c.workbook.sheets.findIndex((s) => s.totals) + 1;
  const csvPath = join(dir, `calc-${c.workbook.sheets[sheetIndex - 1].name}.csv`);
  assert.ok(existsSync(csvPath), 'LibreOffice wrote the sheet');
  const lines = readFileSync(csvPath, 'utf8').trim().split('\n');
  const sh = c.workbook.sheets[sheetIndex - 1];
  const total = lines[sh.rows.length + 1].split(',');
  const openIdx = sh.columns.findIndex((col) => col.key === 'open');
  assert.equal(Number(total[openIdx]), sh.rows.reduce((n, r) => n + (r.open || 0), 0), 'SUM calculated');
});
