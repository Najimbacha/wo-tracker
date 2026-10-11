// Reference text formatter. app/lib/i18n/strings.dart does the same thing;
// both are tested on app/test/fixtures/i18n.json.
//
//   {name}       → the value
//   {name#unit}  → the number with the right word: "1 day", "9 days",
//                  "يومين", "9 أيام", "11 يوماً" (texts under unit.<unit>.<form>;
//                  Arabic 1 and 2 are the word alone)

export const PLURAL_FORMS = { en: ['one', 'other'], ar: ['one', 'two', 'few', 'many', 'other'] };

/** CLDR plural form for a whole number. */
export function pluralForm(lang, n) {
  n = Math.abs(n);
  if (lang === 'ar') {
    if (n === 1) return 'one';
    if (n === 2) return 'two';
    const r = n % 100;
    if (r >= 3 && r <= 10) return 'few';
    if (r >= 11 && r <= 99) return 'many';
    return 'other'; // 0, 100, 101, 102, ...
  }
  return n === 1 ? 'one' : 'other';
}

export const PLACEHOLDER = /\{(\w+)(?:#(\w+))?\}/g;

export function format(lang, text, fallback, key, params = {}) {
  const raw = text[key] ?? fallback[key] ?? key;
  return raw.replace(PLACEHOLDER, (whole, name, unit) => {
    const v = params[name];
    if (v === undefined || v === null) return whole;
    if (!unit) return Array.isArray(v) ? listJoin(lang, v.map(String)) : String(v);
    const form = pluralForm(lang, Number(v));
    const own = text[`unit.${unit}.${form}`];
    const word = own ?? text[`unit.${unit}.other`] ?? fallback[`unit.${unit}.${pluralForm('en', Number(v))}`] ?? unit;
    // Arabic singular and dual carry the number in the word: "منذ يومين", "منذ يوم".
    if (lang === 'ar' && own !== undefined && (form === 'one' || form === 'two')) return word;
    return `${v} ${word}`;
  });
}

/** "A, B and C" / "A، B وC" (same as Strings.list in Dart). */
export function listJoin(lang, items) {
  if (!items.length) return '';
  if (items.length === 1) return items[0];
  const rtl = lang === 'ar';
  return `${items.slice(0, -1).join(rtl ? '، ' : ', ')}${rtl ? ' و' : ' and '}${items[items.length - 1]}`;
}

/**
 * Text helpers for one language, like Strings in Dart:
 *   t(key, params), date('2026-10-11'), weekday(date), hijri(date, cal), step(key), type(code)
 */
export function textFor(lang, text, english, rules) {
  const t = (key, params) => format(lang, text, english, key, params);
  const date = (ymd) => {
    const [y, m, d] = ymd.split('-').map(Number);
    return `${d} ${t(`date.month.${m}`)} ${y}`;
  };
  const weekday = (ymd) => t(`date.weekday.${new Date(`${ymd}T00:00:00Z`).getUTCDay()}`);
  const hijri = (ymd, cal) => {
    const h = cal && cal.toHijri(ymd);
    return h ? t('date.hijriFull', { day: h.day, month: t(`date.hijri.${h.month}`), year: h.year }) : '';
  };
  const label = (def, fallback) => (def && (def[lang] || def.en)) || fallback;
  return {
    lang, t, date, weekday, hijri,
    list: (items) => listJoin(lang, items),
    step: (key) => label(rules.steps[key], key),
    type: (code) => label(rules.types[code], code),
  };
}
