// Turns the report figures into the finished report: every section, label, row and
// number, in English or Arabic. The PDF and Excel writers only lay this out; they
// never compute anything. app/lib/report/report_doc.dart mirrors this file.
import { toDay, fromDay, evaluate, activeDays } from './engine.mjs';
import { report, weekRange, monthRange, UNASSIGNED } from './insights.mjs';
import { textFor } from './i18n.mjs';

const TREND_DAYS = 14;
const TOP_CONTRACTORS = 6;
// The PDF is a summary; longer lists are cut here with "+N more in the Excel file".
export const PDF_LIMITS = { delays: 25, completed: 30 };
// An issue that already says what to do next doesn't repeat it.
const IMPLIED_NEXT = { meter_not_on: ['meter_on'], tawari_tasreeh_missing: ['tasreeh_applied'] };

/**
 * kind: 'daily' | 'weekly' | 'monthly'
 * date: any day in the period ('YYYY-MM-DD'); today: the data date
 * opts: { lang, text, english, hijri (HijriCalendar or null), preparedBy, generatedAt ('YYYY-MM-DD HH:mm') }
 */
export function reportDocument(rules, orders, kind, date, today, opts) {
  const x = textFor(opts.lang, opts.text, opts.english, rules);
  const { t } = x;
  const range = kind === 'daily' ? { from: date, to: date } : kind === 'weekly' ? weekRange(date) : monthRange(date);
  if (toDay(range.from) > toDay(today)) throw new Error(`The report period starts after ${today}`);
  const asOf = toDay(range.to) < toDay(today) ? range.to : today;
  // `current`: the period includes today. `partial`: it is still running, so only the days
  // up to today exist yet, and it is compared with the same days of the previous period.
  const current = toDay(today) <= toDay(range.to);
  const partial = toDay(asOf) < toDay(range.to);
  const r = report(rules, orders, range.from, range.to, asOf);
  const prevFull = kind === 'daily'
    ? { from: fromDay(toDay(date) - 1), to: fromDay(toDay(date) - 1) }
    : kind === 'weekly' ? weekRange(fromDay(toDay(range.from) - 1)) : monthRange(fromDay(toDay(range.from) - 1));
  const elapsed = toDay(asOf) - toDay(range.from);
  const prevTo = fromDay(Math.min(toDay(prevFull.from) + elapsed, toDay(prevFull.to)));
  const prev = report(rules, orders, prevFull.from, prevTo, prevTo);
  const signed = (n) => (n > 0 ? `+${n}` : n < 0 ? `−${Math.abs(n)}` : '±0');
  const vsKey = kind === 'daily' ? 'report.vsPrevDay'
    : kind === 'weekly' ? (partial ? 'report.vsPrevWeekSoFar' : 'report.vsPrevWeek')
      : (partial ? 'report.vsPrevMonthSoFar' : 'report.vsPrevMonth');
  const periodWord = t(current ? `report.period.${kind}` : `report.period.${kind}Past`);
  const reportName = t(`report.${kind}Title`);

  // Header
  let title, hijri;
  if (kind === 'daily') {
    title = t('report.weekdayDate', { weekday: x.weekday(date), date: x.date(date) });
    hijri = x.hijri(date, opts.hijri);
  } else if (kind === 'weekly') {
    title = t('report.range', { from: x.date(range.from), to: x.date(range.to) });
    const hf = x.hijri(range.from, opts.hijri), ht = x.hijri(range.to, opts.hijri);
    hijri = hf && ht ? t('report.range', { from: hf, to: ht }) : '';
  } else {
    const [y, m] = range.from.split('-').map(Number);
    title = `${t(`date.month.${m}`)} ${y}`;
    const hf = x.hijri(range.from, opts.hijri), ht = x.hijri(range.to, opts.hijri);
    hijri = hf && ht ? t('report.range', { from: hf, to: ht }) : '';
  }

  // Key figures
  const attnParts = Object.entries(r.attentionByCode)
    .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))
    .map(([code, n]) => `${t(`alertShort.${code}`)} ${n}`);
  const kpis = [
    { key: 'received', label: t('report.kpiReceived', { period: periodWord }), value: r.received, note: t(vsKey, { delta: signed(r.received - prev.received) }), tone: 'normal' },
    { key: 'steps', label: t('report.stepsCompleted'), value: r.stepsCompleted, note: t('report.onOrders', { count: r.ordersTouched }), tone: 'normal' },
    { key: 'completed', label: t('report.ordersCompleted'), value: r.completed, note: t(vsKey, { delta: signed(r.completed - prev.completed) }), tone: 'normal' },
    { key: 'attention', label: t('report.needAttention'), value: r.attention, note: attnParts.slice(0, 3).join(' · '), tone: r.attention ? 'alert' : 'normal' },
  ];

  // Trend: last 14 days for a daily report, every day of the period up to today otherwise.
  const trendFrom = kind === 'daily' ? fromDay(toDay(date) - (TREND_DAYS - 1)) : range.from;
  const trendSeries = report(rules, orders, trendFrom, asOf, asOf).series;
  const avg = (k) => (trendSeries.length ? trendSeries.reduce((s, p) => s + p[k], 0) / trendSeries.length : 0).toFixed(1);
  const trend = {
    title: kind === 'daily' ? t('report.receivedVsCompleted') : t('report.byDay'),
    days: trendSeries.map((p) => ({ date: p.date, label: shortDate(x, p.date), received: p.received, completed: p.completed })),
    max: Math.max(1, ...trendSeries.flatMap((p) => [p.received, p.completed])),
    legend: { received: t('report.received'), completed: t('report.completedInPeriod') },
    summary: t('report.trendSummary', { received: avg('received'), completed: avg('completed') }),
  };

  const stages = {
    title: t('report.openByStage', { count: r.open }),
    rows: rules.stages.map((s) => ({ key: s.key, label: t(`stage.${s.key}`), value: r.byStage[s.key] || 0 })),
  };

  const stepOrder = Object.keys(rules.steps);
  const steps = {
    title: t('report.stepsInPeriod', { count: r.stepsCompleted }),
    rows: Object.entries(r.stepsByKey)
      .sort((a, b) => stepOrder.indexOf(a[0]) - stepOrder.indexOf(b[0]))
      .map(([key, n]) => ({ key, label: x.step(key), value: n })),
  };

  // Needs attention: the most urgent alert of each order, with the next step to do.
  const byId = new Map(orders.map((o) => [o.id, o]));
  const delays = {
    title: t('report.delays', { count: r.delays.length }),
    subtitle: t('report.mostUrgentFirst'),
    columns: ['wo', 'type', 'district', 'contractor', 'issue', 'days'].map((k) => ({ key: k, label: t(`report.col.${k}`), numeric: k === 'days' })),
    rows: r.delays.map((d) => {
      const order = byId.get(d.id);
      const ev = evaluate(rules, order, asOf);
      const nextKey = ev.next && ev.next.length ? ev.next[0].split('@')[0] : null;
      const showNext = nextKey && !(IMPLIED_NEXT[d.code] || []).includes(nextKey);
      let issue = t(`alertShort.${d.code}`);
      if (d.code === 'next_tasreeh_needed') {
        const a = ev.alerts.find((al) => al.code === 'next_tasreeh_needed');
        if (a) issue = a.daysLeft === 0 ? t('report.tasreehEndsToday') : t('report.tasreehEndsIn', { daysLeft: a.daysLeft });
      }
      let days = d.days;
      if (days === null && d.code === 'no_active_tasreeh') {
        const a = ev.alerts.find((al) => al.code === 'no_active_tasreeh');
        if (a && a.since) days = activeDays(a.since, asOf, (order.status && order.status.holdPeriods) || []);
      }
      return {
        wo: d.woNumber, type: d.type, district: d.district || '', contractor: d.contractor || t('common.unassigned'),
        issue: showNext ? t('report.issueNext', { issue, step: x.step(nextKey) }) : issue,
        days, severity: d.severity,
      };
    }),
  };

  // By contractor: the busiest first, the rest folded into one row, then the total.
  const all = r.contractors;
  const named = all.filter((c) => c.contractor !== UNASSIGNED);
  const top = named.slice(0, TOP_CONTRACTORS);
  const rest = [...named.slice(TOP_CONTRACTORS), ...all.filter((c) => c.contractor === UNASSIGNED)];
  const sumRow = (list, label) => {
    const finished = list.reduce((s, c) => s + c.finished, 0);
    return {
      contractor: label,
      open: list.reduce((s, c) => s + c.open, 0),
      completed: list.reduce((s, c) => s + c.completedInPeriod, 0),
      lateStarts: list.reduce((s, c) => s + c.lateStarts, 0),
      avgDays: finished ? Math.round(list.reduce((s, c) => s + c.finishDaysTotal, 0) / finished) : null,
    };
  };
  const contractors = {
    title: t('report.byContractor'),
    subtitle: t(current ? 'report.openAsOf' : 'report.openAtEnd'),
    columns: [
      { key: 'contractor', label: t('report.col.contractor'), numeric: false },
      { key: 'open', label: t('report.open'), numeric: true },
      { key: 'completed', label: t('report.completedInPeriod'), numeric: true },
      { key: 'lateStarts', label: t('report.lateStarts'), numeric: true },
      { key: 'avgDays', label: t('report.avgDaysToFinish'), numeric: true },
    ],
    rows: [
      ...top.map((c) => ({ contractor: c.contractor, open: c.open, completed: c.completedInPeriod, lateStarts: c.lateStarts, avgDays: c.avgDaysToFinish })),
      ...(rest.length === 1 && rest[0].contractor === UNASSIGNED
        ? [{ ...sumRow(rest, t('common.unassigned')) }]
        : rest.length ? [sumRow(rest, t('report.others', { count: rest.length }))] : []),
    ],
    total: sumRow(all, t('report.total')),
  };

  const completed = {
    title: t('report.completedList', { count: r.completed }),
    subtitle: t('report.documentsSubmitted'),
    rows: r.completedList.map((c) => ({ wo: c.woNumber, type: c.type, days: c.days, daysText: t('common.days', { count: c.days }) })),
  };

  const qKeys = ['cableLV', 'cableMV', 'asphalt40', 'asphalt80', 'soil', 'tiles'];
  const quantities = {
    title: t('report.quantities'),
    subtitle: t('report.metres'),
    items: qKeys.map((k) => ({ key: k, label: t(`report.${k}`), value: Math.round(r.quantities[k]) })),
  };

  return {
    kind,
    lang: opts.lang,
    dir: opts.lang === 'ar' ? 'rtl' : 'ltr',
    period: range,
    header: {
      eyebrow: reportName,
      title,
      hijri,
      preparedBy: t('report.preparedBy', { name: opts.preparedBy }),
      generated: t('report.generated', { time: generatedText(x, opts.generatedAt) }),
    },
    kpis, trend, stages, steps, delays, contractors, completed, quantities,
    empty: t('report.none'),
    moreText: t('report.moreRows', { count: '{count}' }), // writer fills in the number
    limits: PDF_LIMITS,
    footer: t('report.footer', { report: reportName, date: x.date(today) }),
    pageText: t('report.page', { page: '{page}', pages: '{pages}' }), // writer fills in the numbers
  };
}

function shortDate(x, ymd) {
  const [, m, d] = ymd.split('-').map(Number);
  const month = x.t(`date.month.${m}`);
  return `${d} ${x.lang === 'ar' ? month : month.slice(0, 3)}`;
}

function generatedText(x, at) {
  if (!at) return '';
  const [d, time] = at.split(' ');
  return time ? `${x.date(d)}${x.lang === 'ar' ? '، ' : ', '}${time}` : x.date(d);
}
