// Builds sample Excel files from generated orders. Run: node tools/report-preview/make-excel.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { buildDemo, DEMO_TODAY } from '../sample/demo.mjs';
import { reportWorkbook, dataWorkbook } from '../rules-check/export-doc.mjs';
import { HijriCalendar } from '../rules-check/hijri.mjs';

const root = new URL('../../', import.meta.url);
const json = (p) => JSON.parse(readFileSync(new URL(p, root), 'utf8'));
const rules = json('app/assets/rules/rules.json');
const en = json('app/assets/i18n/en.json');
const ar = json('app/assets/i18n/ar.json');
const hijri = new HijriCalendar(json('app/assets/calendar/umalqura.json'));
const out = new URL('./out/', import.meta.url);
mkdirSync(out, { recursive: true });

const orders = buildDemo(rules, DEMO_TODAY, 7, { volume: 1200, spanDays: 90 });
const opts = (lang) => ({ lang, text: lang === 'ar' ? ar : en, english: en, hijri, preparedBy: lang === 'ar' ? 'م. نجم' : 'Engr Najim', generatedAt: `${DEMO_TODAY} 20:55` });
const books = [
  reportWorkbook(rules, orders, 'daily', DEMO_TODAY, DEMO_TODAY, opts('en')),
  reportWorkbook(rules, orders, 'daily', DEMO_TODAY, DEMO_TODAY, opts('ar')),
  reportWorkbook(rules, orders, 'monthly', '2026-09-15', DEMO_TODAY, opts('en')),
  dataWorkbook(rules, orders, DEMO_TODAY, `${DEMO_TODAY} 20:55`),
];
for (const wb of books) {
  const modelPath = new URL(`${wb.fileName}.json`, out).pathname;
  writeFileSync(modelPath, JSON.stringify(wb));
  execFileSync('python3', [new URL('./write_xlsx.py', import.meta.url).pathname, modelPath, new URL(wb.fileName, out).pathname]);
  console.log(wb.fileName);
}
