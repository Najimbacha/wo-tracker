// Builds sample reports from generated orders and prints them to PDF with Chromium.
// Run: node tools/report-preview/make-preview.mjs   (PDFs go to tools/report-preview/out/)
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { buildDemo, DEMO_TODAY } from '../sample/demo.mjs';
import { reportDocument } from '../rules-check/report-doc.mjs';
import { HijriCalendar } from '../rules-check/hijri.mjs';
import { renderHtml, footerTemplate } from './render.mjs';

const { chromium } = createRequire(import.meta.url)('playwright'); // global install, found through NODE_PATH
const root = new URL('../../', import.meta.url);
const json = (p) => JSON.parse(readFileSync(new URL(p, root), 'utf8'));
const rules = json('app/assets/rules/rules.json');
const en = json('app/assets/i18n/en.json');
const ar = json('app/assets/i18n/ar.json');
const hijri = new HijriCalendar(json('app/assets/calendar/umalqura.json'));
const out = new URL('./out/', import.meta.url);
mkdirSync(out, { recursive: true });

// About 14 orders a day for 90 days, like a real workload.
const orders = buildDemo(rules, DEMO_TODAY, 7, { volume: 1200, spanDays: 90 });
const jobs = [
  { file: 'daily-report-en', kind: 'daily', date: DEMO_TODAY, lang: 'en' },
  { file: 'daily-report-ar', kind: 'daily', date: DEMO_TODAY, lang: 'ar' },
  { file: 'monthly-report-september-en', kind: 'monthly', date: '2026-09-15', lang: 'en' },
];

const browser = await chromium.launch();
const page = await browser.newPage();
for (const j of jobs) {
  const doc = reportDocument(rules, orders, j.kind, j.date, DEMO_TODAY, {
    lang: j.lang, text: j.lang === 'ar' ? ar : en, english: en, hijri, preparedBy: j.lang === 'ar' ? 'م. نجم' : 'Engr Najim', generatedAt: `${DEMO_TODAY} 20:55`,
  });
  const html = renderHtml(doc);
  writeFileSync(new URL(`${j.file}.html`, out), html);
  await page.setContent(html, { waitUntil: 'load' });
  await page.pdf({
    path: new URL(`${j.file}.pdf`, out).pathname, format: 'A4', printBackground: true,
    displayHeaderFooter: true, headerTemplate: '<span></span>', footerTemplate: footerTemplate(doc),
    margin: { top: '14mm', bottom: '18mm', left: '15mm', right: '15mm' },
  });
  console.log(`${j.file}.pdf`);
}
await browser.close();
