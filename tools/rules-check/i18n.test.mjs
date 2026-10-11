// Checks the English and Arabic text files: same keys, same placeholders,
// nothing empty, and a message for every code the engine and screens can produce.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ACTION_GROUPS, QUICK_FILTERS, SEARCH_KINDS, pipeline } from './insights.mjs';
import { PLURAL_FORMS, PLACEHOLDER, format, pluralForm } from './i18n.mjs';

const root = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, root), 'utf8');
const en = JSON.parse(read('app/assets/i18n/en.json'));
const ar = JSON.parse(read('app/assets/i18n/ar.json'));
const rules = JSON.parse(read('app/assets/rules/rules.json'));
const engineSrc = read('tools/rules-check/engine.mjs');
const actionsSrc = read('tools/rules-check/actions.mjs');
const insightsSrc = read('tools/rules-check/insights.mjs');
const sql = read('supabase/migrations/20261011000001_initial.sql');

const ARABIC = /[؀-ۿ]/;
// Placeholder names; the unit after # may differ between languages.
const placeholders = (s) => [...new Set([...s.matchAll(PLACEHOLDER)].map((m) => m[1]))].sort();
const unitsUsed = (file) => new Set(Object.entries(file).filter(([k]) => !k.startsWith('unit.')).flatMap(([, v]) => [...v.matchAll(PLACEHOLDER)].map((m) => m[2]).filter(Boolean)));
const messages = (file) => Object.keys(file).filter((k) => !k.startsWith('unit.'));
const fx = JSON.parse(read('app/test/fixtures/i18n.json'));
const has = (key) => assert.ok(key in en && key in ar, `missing text: ${key}`);

test('both files have exactly the same messages', () => {
  const onlyEn = messages(en).filter((k) => !(k in ar));
  const onlyAr = messages(ar).filter((k) => !(k in en));
  assert.deepEqual(onlyEn, [], 'keys only in en.json');
  assert.deepEqual(onlyAr, [], 'keys only in ar.json');
});

test('placeholders match between English and Arabic', () => {
  for (const k of messages(en)) assert.deepEqual(placeholders(ar[k]), placeholders(en[k]), k);
});

test('every counted word has all its plural forms, and no unused ones', () => {
  for (const [lang, file] of [['en', en], ['ar', ar]]) {
    const used = unitsUsed(file);
    assert.ok(used.size >= 5, `${lang}: only ${used.size} units used`);
    for (const u of used) for (const f of PLURAL_FORMS[lang]) assert.ok(file[`unit.${u}.${f}`], `${lang} unit.${u}.${f} missing`);
    for (const k of Object.keys(file).filter((k) => k.startsWith('unit.'))) {
      const [, u, f] = k.split('.');
      assert.ok(used.has(u), `${lang} ${k} is never used`);
      assert.ok(PLURAL_FORMS[lang].includes(f), `${lang} ${k}: ${f} is not a plural form of ${lang}`);
    }
  }
});

test('plural rules', () => {
  const ar = [[0, 'other'], [1, 'one'], [2, 'two'], [3, 'few'], [10, 'few'], [11, 'many'], [99, 'many'], [100, 'other'], [102, 'other'], [103, 'few'], [111, 'many']];
  for (const [n, f] of ar) assert.equal(pluralForm('ar', n), f, `ar ${n}`);
  assert.equal(pluralForm('en', 1), 'one');
  for (const n of [0, 2, 11, 101]) assert.equal(pluralForm('en', n), 'other');
});

test('formatted text matches the shared fixture', () => {
  for (const c of fx.cases) {
    const file = c.lang === 'ar' ? ar : en;
    assert.equal(format(c.lang, file, en, c.key, c.params), c.expected, `${c.lang} ${c.key} ${JSON.stringify(c.params)}`);
  }
});

test('no empty text; Arabic text is Arabic; braces are balanced', () => {
  const latinOnly = new Set(['report.format.pdf', 'report.range']);
  for (const [lang, file] of [['en', en], ['ar', ar]]) {
    for (const [k, v] of Object.entries(file)) {
      assert.equal(typeof v, 'string', `${lang} ${k}`);
      assert.ok(v.trim().length > 0, `${lang} ${k} is empty`);
      assert.equal((v.match(/\{/g) || []).length, (v.match(/\}/g) || []).length, `${lang} ${k} braces`);
      assert.ok(!/\{\s*\}/.test(v), `${lang} ${k} has an empty placeholder`);
    }
  }
  for (const [k, v] of Object.entries(ar)) {
    const words = v.replace(PLACEHOLDER, '').trim(); // "{count#day}" alone is fine: the unit word is Arabic
    if (!latinOnly.has(k) && words) assert.ok(ARABIC.test(words), `ar ${k} has no Arabic: ${v}`);
  }
  for (const [k, v] of Object.entries(en)) assert.ok(!ARABIC.test(v), `en ${k} contains Arabic`);
});

test('Arabic uses the same digits as the numbers the app fills in', () => {
  for (const [k, v] of Object.entries(ar)) assert.ok(!/[٠-٩۰-۹]/.test(v), `ar ${k} uses Arabic-Indic digits`);
});

// Every `code: '...'` the engine emits, grouped by where the app shows it.
function engineCodes(kind) {
  const out = new Map();
  const patterns = {
    alert: /alerts\.push\(\{\s*code:\s*'(\w+)'([^}]*)\}/g,
    lock: /\{\s*code:\s*'(\w+)'([^}]*)\}/g,
    error: /(?:errors\.push\(|return \[)\{\s*code:\s*'(\w+)'([^}]*)\}/g,
  };
  let src = engineSrc;
  if (kind === 'lock') src = engineSrc.slice(engineSrc.indexOf('const reasons = []'), engineSrc.indexOf("state: 'locked'"));
  for (const m of src.matchAll(patterns[kind])) {
    const fields = [...m[2].matchAll(/(\w+)\s*(?::|,|$)/g)].map((x) => x[1]).filter((f) => f !== 'severity');
    out.set(m[1], new Set([...(out.get(m[1]) || []), ...fields]));
  }
  return out;
}

for (const [kind, prefix] of [['alert', 'alert'], ['lock', 'lock'], ['error', 'error']]) {
  test(`every engine ${kind} code has a message that only uses fields the engine provides`, () => {
    const codes = engineCodes(kind);
    assert.ok(codes.size >= (kind === 'lock' ? 4 : 8), `found only ${codes.size} ${kind} codes; check the pattern`);
    for (const [code, fields] of codes) {
      const key = `${prefix}.${code}`;
      has(key);
      for (const p of placeholders(en[key])) assert.ok(fields.has(p), `${key} uses {${p}} but the engine sends: ${[...fields].join(', ')}`);
    }
  });
}

// Every object literal starting with `code:` in actions.mjs is an error shown to the user.
function actionCodes() {
  const out = new Map();
  for (const m of actionsSrc.matchAll(/\{\s*code:\s*(?:[\w.]+\s*\?\s*)?'(\w+)'(?:\s*:\s*'(\w+)')?([^}]*)\}/g)) {
    const fields = [...m[3].matchAll(/(\w+)\s*(?::|,|$)/g)].map((x) => x[1]);
    for (const code of [m[1], m[2]].filter(Boolean)) out.set(code, new Set([...(out.get(code) || []), ...fields]));
  }
  return out;
}

test('every action error has a message that only uses fields the action provides', () => {
  const codes = actionCodes();
  assert.ok(codes.size >= 15, `found only ${codes.size} action codes`);
  for (const [code, fields] of codes) {
    const key = `error.${code}`;
    has(key);
    for (const p of placeholders(en[key])) assert.ok(fields.has(p), `${key} uses {${p}} but the action sends: ${[...fields].join(', ')}`);
  }
});

test('every alert has a short name for chips and reports', () => {
  for (const code of engineCodes('alert').keys()) has(`alertShort.${code}`);
});

test('alert codes in the app match the ones in the design', () => {
  const expected = ['late_start', 'open_trench', 'restoration_overdue', 'no_active_tasreeh', 'next_tasreeh_needed', 'meter_not_on', 'tawari_tasreeh_missing', 'stalled'];
  assert.deepEqual([...engineCodes('alert').keys()].sort(), [...expected].sort());
});

test('statuses, stages and categories', () => {
  for (const s of ['open', 'on_hold', 'completed', 'cancelled', 'merged']) has(`status.${s}`);
  for (const st of rules.stages) {
    assert.equal(en[`stage.${st.key}`], st.en, `stage.${st.key} en differs from rules.json`);
    assert.equal(ar[`stage.${st.key}`], st.ar, `stage.${st.key} ar differs from rules.json`);
  }
  for (const [c, def] of Object.entries(rules.categories)) {
    assert.equal(en[`category.${c}`], def.en);
    assert.equal(ar[`category.${c}`], def.ar);
  }
});

test('every step and type in rules.json has English and Arabic names', () => {
  for (const [k, s] of Object.entries(rules.steps)) {
    assert.ok(s.en && s.en.trim(), `step ${k} en`);
    assert.ok(s.ar && ARABIC.test(s.ar), `step ${k} ar`);
  }
  for (const [k, t] of Object.entries(rules.types)) {
    assert.ok(t.en && t.en.trim(), `type ${k} en`);
    assert.ok(t.ar && ARABIC.test(t.ar), `type ${k} ar`);
  }
});

test('follow-up groups, quick filters, search kinds, pipeline buckets', () => {
  for (const [g] of ACTION_GROUPS) has(`followUp.group.${g}`);
  for (const q of QUICK_FILTERS) has(`filter.quick.${q}`);
  for (const s of SEARCH_KINDS) has(`search.kind.${s}`);
  for (const b of Object.keys(pipeline(rules, [], '2026-10-11').buckets)) has(`pipeline.bucket.${b}`);
  assert.ok(insightsSrc.includes(`'${SEARCH_KINDS[0]}'`));
});

test('tasreeh states and surface filters', () => {
  const start = insightsSrc.indexOf('function tasreehState');
  const fn = insightsSrc.slice(start, insightsSrc.indexOf('\n}', start));
  const states = [...fn.matchAll(/return (?:[^;]*\? )?'(\w+)'(?: : '(\w+)')?/g)].flatMap((m) => m.slice(1).filter(Boolean));
  assert.ok(states.length >= 5, 'could not read tasreeh states');
  for (const s of new Set(states)) has(`tasreeh.state.${s}`);
  for (const s of ['soil', 'asphalt_40', 'asphalt_80', 'tiled', 'no_digging']) {
    has(`filter.surface.${s}`);
    assert.ok(insightsSrc.includes(`'${s}'`) || s.startsWith('asphalt_'), `surface ${s} not produced by insights`);
  }
});

test('meter types match the database', () => {
  const m = sql.match(/meter_type in \(([^)]*)\)/);
  assert.ok(m, 'meter_type check not found');
  for (const t of [...m[1].matchAll(/'(\w+)'/g)].map((x) => x[1])) has(`order.meterType.${t}`);
});

test('calendar names', () => {
  for (let i = 1; i <= 12; i++) { has(`date.month.${i}`); has(`date.hijri.${i}`); }
  for (let i = 0; i <= 6; i++) has(`date.weekday.${i}`);
});
