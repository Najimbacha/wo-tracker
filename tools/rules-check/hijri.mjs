// Umm al-Qura (Saudi official) Hijri dates from the month table in
// app/assets/calendar/umalqura.json. The Dart version in app/lib/domain/hijri.dart
// follows this file line for line.
const DAY = 86400000;
const dayNum = (ymd) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd)) throw new Error(`bad date: ${ymd}`);
  const [y, m, d] = ymd.split('-').map(Number);
  const ms = Date.UTC(y, m - 1, d);
  if (new Date(ms).toISOString().slice(0, 10) !== ymd) throw new Error(`bad date: ${ymd}`);
  return Math.round(ms / DAY);
};
const fromDayNum = (n) => new Date(n * DAY).toISOString().slice(0, 10);

export class HijriCalendar {
  constructor(table) {
    this.firstYear = table.firstYear;
    this.lastYear = table.lastYear;
    this.starts = table.monthStarts.map(dayNum);
    if (this.starts.length !== (this.lastYear - this.firstYear + 1) * 12 + 1) throw new Error('month table has the wrong length');
  }

  get firstDate() { return fromDayNum(this.starts[0]); }
  get lastDate() { return fromDayNum(this.starts[this.starts.length - 1] - 1); }

  /** 'YYYY-MM-DD' → { year, month, day }, or null outside the table. */
  toHijri(ymd) {
    const n = dayNum(ymd);
    const s = this.starts;
    if (n < s[0] || n >= s[s.length - 1]) return null;
    let lo = 0, hi = s.length - 2; // last index whose start is <= n
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (s[mid] <= n) lo = mid; else hi = mid - 1;
    }
    return { year: this.firstYear + Math.floor(lo / 12), month: (lo % 12) + 1, day: n - s[lo] + 1 };
  }

  monthLength(year, month) {
    const i = this.#index(year, month);
    return i === null ? null : this.starts[i + 1] - this.starts[i];
  }

  /** Hijri → 'YYYY-MM-DD', or null for an impossible or out-of-range date. */
  fromHijri(year, month, day) {
    const i = this.#index(year, month);
    if (i === null || !Number.isInteger(day) || day < 1 || day > this.starts[i + 1] - this.starts[i]) return null;
    return fromDayNum(this.starts[i] + day - 1);
  }

  #index(year, month) {
    if (!Number.isInteger(year) || !Number.isInteger(month) || month < 1 || month > 12) return null;
    if (year < this.firstYear || year > this.lastYear) return null;
    return (year - this.firstYear) * 12 + month - 1;
  }
}

/** "30 Rabiʻ II 1448" using month names from the i18n file. */
export function formatHijri(h, monthNames, pattern = '{day} {month} {year}') {
  if (!h) return '';
  return pattern.replace('{day}', String(h.day)).replace('{month}', monthNames[h.month - 1]).replace('{year}', String(h.year));
}
