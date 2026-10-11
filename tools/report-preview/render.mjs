// Lays out a report document (from report-doc.mjs) as printable A4 HTML in the
// approved design. Used to preview and approve the report; the app's PDF writer
// follows the same layout. Nothing is computed here, only placed.

const C = { ink: '#15181C', muted: '#4F5861', faint: '#6B747C', line: '#D5D9D4', soft: '#E2E5E1', track: '#F4F5F3', accent: '#2152C4', accentDark: '#173C94', grey: '#B8BEB7', greyDark: '#8F968E', alertBg: '#FBECEA', alert: '#8C1D17' };
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const num = (n) => (n === null || n === undefined ? '–' : String(n));
const more = (doc, total, shown) => (total > shown ? `<p class="more">${esc(doc.moreText.replace('{count}', String(total - shown)))}</p>` : '');

export function renderHtml(doc) {
  const rtl = doc.dir === 'rtl';
  const font = rtl ? "'DejaVu Sans', 'Inter', sans-serif" : "'Inter', 'DejaVu Sans', sans-serif";
  const h = doc.header;

  const kpis = doc.kpis.map((k) => `
    <div class="kpi ${k.tone === 'alert' ? 'alert' : ''}">
      <div class="k">${esc(k.label)}</div><div class="kn">${num(k.value)}</div><div class="kd">${esc(k.note)}</div>
    </div>`).join('');

  const tr = doc.trend;
  const last = tr.days.length - 1;
  const bars = tr.days.map((d, i) => `
    <div class="bar-pair" title="${esc(d.label)}">
      <div style="height:${(d.received / tr.max) * 100}%;background:${i === last ? C.greyDark : C.grey}"></div>
      <div style="height:${(d.completed / tr.max) * 100}%;background:${i === last ? C.accentDark : C.accent}"></div>
    </div>`).join('');
  const lastDay = tr.days[last];
  const axisMid = tr.days[Math.floor(last / 2)];

  const stageMax = Math.max(1, ...doc.stages.rows.map((r) => r.value));
  const stages = doc.stages.rows.map((r) => `
    <div class="stage"><span class="sl">${esc(r.label)}</span><div class="track"><div style="width:${(r.value / stageMax) * 100}%"></div></div><span class="n">${r.value}</span></div>`).join('');

  const steps = doc.steps.rows.length
    ? `<div class="grid3">${doc.steps.rows.map((r) => `<div class="cell"><span>${esc(r.label)}</span><span class="n">${r.value}</span></div>`).join('')}</div>`
    : `<p class="empty">${esc(doc.empty)}</p>`;

  const table = (section, rowHtml) => `
    <table><thead><tr>${section.columns.map((c) => `<th class="${c.numeric ? 'r' : ''}">${esc(c.label)}</th>`).join('')}</tr></thead>
    <tbody>${rowHtml}</tbody></table>`;

  const delayRows = doc.delays.rows.slice(0, doc.limits.delays);
  const delays = delayRows.length
    ? table(doc.delays, delayRows.map((d) => `
      <tr><td class="n">${esc(d.wo)}</td><td class="n">${esc(d.type)}</td><td>${esc(d.district)}</td><td>${esc(d.contractor)}</td>
      <td class="${d.severity === 'critical' ? 'crit' : ''}">${esc(d.issue)}</td><td class="n r strong">${num(d.days)}</td></tr>`).join('')) + more(doc, doc.delays.rows.length, delayRows.length)
    : `<p class="empty">${esc(doc.empty)}</p>`;

  const ct = doc.contractors;
  const contractors = table(ct, [...ct.rows.map((c) => `
      <tr><td>${esc(c.contractor)}</td><td class="n r">${c.open}</td><td class="n r">${c.completed}</td>
      <td class="n r ${c.lateStarts ? 'crit' : ''}">${c.lateStarts}</td><td class="n r">${num(c.avgDays)}</td></tr>`),
    `<tr class="total"><td>${esc(ct.total.contractor)}</td><td class="n r">${ct.total.open}</td><td class="n r">${ct.total.completed}</td><td class="n r">${ct.total.lateStarts}</td><td class="n r">${num(ct.total.avgDays)}</td></tr>`].join(''));

  const doneRows = doc.completed.rows.slice(0, doc.limits.completed);
  const completed = doneRows.length
    ? `<div class="grid3">${doneRows.map((c) => `<div class="cell small"><span><span class="n">${esc(c.wo)}</span> · ${esc(c.type)}</span><span class="muted">${esc(c.daysText)}</span></div>`).join('')}</div>${more(doc, doc.completed.rows.length, doneRows.length)}`
    : `<p class="empty">${esc(doc.empty)}</p>`;

  const quantities = doc.quantities.items.map((q) => `<div class="q"><b class="n">${q.value}</b><span>${esc(q.label)}</span></div>`).join('');

  return `<!doctype html>
<html lang="${doc.lang}" dir="${doc.dir}">
<head>
<meta charset="utf-8">
<title>${esc(h.eyebrow)} · ${esc(h.title)}</title>
<style>
@page { size: A4; margin: 14mm 15mm 16mm; }
* { box-sizing: border-box; }
body { margin: 0; font-family: ${font}; color: ${C.ink}; font-size: 12px; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.n { font-variant-numeric: tabular-nums; font-feature-settings: "tnum"; direction: ltr; unicode-bidi: isolate; }
header.top { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; padding-bottom: 14px; border-bottom: 2px solid ${C.ink}; }
.eyebrow { display: flex; align-items: center; gap: 8px; font-size: 11px; font-weight: 600; color: ${C.accent}; letter-spacing: ${rtl ? '0' : '.06em'}; text-transform: ${rtl ? 'none' : 'uppercase'}; }
h1 { margin: 8px 0 2px; font-size: 24px; font-weight: 600; }
.hijri { font-size: 13px; color: ${C.muted}; }
.meta { text-align: end; font-size: 11px; color: ${C.muted}; line-height: 1.7; }
section { margin-top: 22px; break-inside: avoid; }
section.flow { break-inside: auto; }
h2 { margin: 0 0 12px; font-size: 14px; font-weight: 600; display: flex; justify-content: space-between; align-items: baseline; gap: 12px; }
h2 small { font-size: 11px; font-weight: 400; color: ${C.faint}; }
.kpis { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); border: 1px solid ${C.line}; border-radius: 8px; overflow: hidden; }
.kpi { padding: 13px 15px; border-inline-end: 1px solid ${C.line}; }
.kpi:last-child { border-inline-end: 0; }
.kpi.alert { background: ${C.alertBg}; color: ${C.alert}; }
.k { font-size: 11.5px; color: inherit; opacity: .85; }
.kn { font-size: 28px; font-weight: 600; line-height: 1.15; font-variant-numeric: tabular-nums; }
.kd { font-size: 11px; opacity: .85; }
.legend { display: flex; gap: 14px; font-size: 11px; font-weight: 400; color: ${C.muted}; }
.legend i { display: inline-block; width: 10px; height: 10px; margin-inline-end: 5px; vertical-align: -1px; }
.chart { position: relative; height: 150px; border-bottom: 1px solid ${C.greyDark}; display: flex; align-items: flex-end; gap: ${tr.days.length > 20 ? 3 : 9}px; padding: 0 4px; background: linear-gradient(${C.soft}, ${C.soft}) 0 0 / 100% 1px no-repeat, linear-gradient(${C.soft}, ${C.soft}) 0 50% / 100% 1px no-repeat; }
.chart-wrap { display: flex; gap: 8px; }
.chart-wrap .chart { flex: 1; }
.yaxis { display: flex; flex-direction: column; justify-content: space-between; height: 150px; font-size: 10px; color: ${C.faint}; text-align: end; width: 20px; margin-top: -6px; margin-bottom: -6px; }
.more { margin: 8px 0 0; font-size: 11px; color: ${C.muted}; }
.bar-pair { flex: 1; display: flex; align-items: flex-end; gap: 2px; height: 100%; }
.bar-pair div { flex: 1; min-height: 0; }
.axis { margin-inline-start: 28px; display: flex; justify-content: space-between; font-size: 10px; color: ${C.faint}; margin-top: 6px; }
.axis b { color: ${C.ink}; font-weight: 600; }
.note { font-size: 11.5px; color: ${C.muted}; margin-top: 8px; }
.stage { display: flex; align-items: center; gap: 12px; margin-bottom: 8px; }
.sl { width: 150px; }
.track { flex: 1; height: 15px; background: ${C.track}; }
.track div { height: 100%; background: ${C.accent}; }
.stage .n { width: 30px; text-align: end; font-weight: 600; }
.grid3 { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); column-gap: 26px; }
.cell { display: flex; justify-content: space-between; gap: 8px; padding: 6px 0; border-bottom: 1px solid ${C.soft}; }
.cell .n { font-weight: 600; }
.cell.small { font-size: 11px; }
.cell.small .n { font-weight: 400; }
.muted { color: ${C.muted}; }
table { width: 100%; border-collapse: collapse; font-size: 11px; }
thead { display: table-header-group; }
th { text-align: start; font-weight: 600; color: ${C.muted}; font-size: 10.5px; padding: 6px 8px 6px 0; border-bottom: 1px solid ${C.ink}; }
td { padding: 6px 8px 6px 0; border-bottom: 1px solid ${C.soft}; vertical-align: top; }
tr { break-inside: avoid; }
.r { text-align: end; }
.strong { font-weight: 600; }
.crit { color: ${C.alert}; font-weight: 600; }
tr.total td { font-weight: 600; border-bottom: 0; border-top: 1px solid ${C.ink}; }
.qs { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 8px; }
.q { border: 1px solid ${C.line}; border-radius: 6px; padding: 10px; display: flex; flex-direction: column; gap: 2px; }
.q b { font-size: 18px; font-weight: 600; }
.q span { font-size: 10.5px; color: ${C.muted}; }
.empty { color: ${C.faint}; margin: 0; }
.page-break { break-before: page; }
</style>
</head>
<body>
<header class="top">
  <div>
    <div class="eyebrow"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="${C.accent}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13 2 4 14h7l-1 8 9-12h-7z"/></svg>${esc(h.eyebrow)}</div>
    <h1>${esc(h.title)}</h1>
    ${h.hijri ? `<div class="hijri">${esc(h.hijri)}</div>` : ''}
  </div>
  <div class="meta">${esc(h.preparedBy)}<br>${esc(h.generated)}</div>
</header>

<section><div class="kpis">${kpis}</div></section>

<section>
  <h2>${esc(tr.title)}<span class="legend"><span><i style="background:${C.grey}"></i>${esc(tr.legend.received)}</span><span><i style="background:${C.accent}"></i>${esc(tr.legend.completed)}</span></span></h2>
  <div class="chart-wrap"><div class="yaxis n"><span>${tr.max}</span><span>${Math.round(tr.max / 2)}</span><span>0</span></div><div class="chart">${bars}</div></div>
  <div class="axis"><span>${esc(tr.days[0].label)}</span><span>${esc(axisMid.label)}</span><b>${esc(lastDay.label)}: <span class="n">${lastDay.received} / ${lastDay.completed}</span></b></div>
  <div class="note">${esc(tr.summary)}</div>
</section>

<section><h2>${esc(doc.stages.title)}</h2>${stages}</section>
<section><h2>${esc(doc.steps.title)}</h2>${steps}</section>

<section class="flow page-break"><h2>${esc(doc.delays.title)}<small>${esc(doc.delays.subtitle)}</small></h2>${delays}</section>
<section><h2>${esc(ct.title)}<small>${esc(ct.subtitle)}</small></h2>${contractors}</section>
<section><h2>${esc(doc.quantities.title)}<small>${esc(doc.quantities.subtitle)}</small></h2><div class="qs">${quantities}</div></section>
<section class="flow"><h2>${esc(doc.completed.title)}<small>${esc(doc.completed.subtitle)}</small></h2>${completed}</section>
</body>
</html>`;
}

/** Footer for every printed page: report name on one side, "Page x of y" on the other. */
export function footerTemplate(doc) {
  const page = esc(doc.pageText).replace('{page}', '<span class="pageNumber"></span>').replace('{pages}', '<span class="totalPages"></span>');
  const font = doc.dir === 'rtl' ? "'DejaVu Sans', sans-serif" : "'Inter', sans-serif";
  return `<div dir="${doc.dir}" style="width:100%;margin:0 15mm;display:flex;justify-content:space-between;font-family:${font};font-size:8px;color:${C.faint};border-top:1px solid ${C.line};padding-top:6px"><span>${esc(doc.footer)}</span><span>${page}</span></div>`;
}
