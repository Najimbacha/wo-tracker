// Excel (.xlsx) writer with no packages: the workbook model from export-doc.mjs →
// SpreadsheetML files → a zip. The Dart app (lib/report/xlsx_writer.dart) follows
// this file line by line; tests open the result with openpyxl and LibreOffice.
//
// Same rules as tools/report-preview/write_xlsx.py: Arial, bold header with filter and
// frozen top row, dates as real dates (dd/mm/yyyy), averages and totals as formulas,
// right-to-left sheets for Arabic, one page wide when printed, landscape when wide.

// ---------------------------------------------------------------- zip (stored)

const CRC_TABLE = (() => {
  const t = new Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

const utf8 = (s) => new TextEncoder().encode(s);

/** A zip with every file stored (no compression), which every Excel version reads. */
export function zipStored(files) {
  const out = [];
  let offset = 0;
  const central = [];
  const u16 = (v) => [v & 0xff, (v >>> 8) & 0xff];
  const u32 = (v) => [v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff];
  // 1 Jan 2026 00:00 in DOS time; a fixed time keeps the file identical for the same data.
  const dosTime = 0, dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;
  for (const f of files) {
    const name = utf8(f.name);
    const data = f.data;
    const crc = crc32(data);
    const local = [
      ...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosTime), ...u16(dosDate),
      ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0),
    ];
    out.push(Uint8Array.from(local), name, data);
    central.push([
      ...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosTime), ...u16(dosDate),
      ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0), ...u16(0),
      ...u16(0), ...u16(0), ...u32(0), ...u32(offset), ...name,
    ]);
    offset += local.length + name.length + data.length;
  }
  const centralBytes = central.flat();
  const end = [
    ...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length),
    ...u32(centralBytes.length), ...u32(offset), ...u16(0),
  ];
  out.push(Uint8Array.from(centralBytes), Uint8Array.from(end));
  const total = out.reduce((n, a) => n + a.length, 0);
  const buf = new Uint8Array(total);
  let p = 0;
  for (const a of out) { buf.set(a, p); p += a.length; }
  return buf;
}

// ---------------------------------------------------------------- SpreadsheetML

export const esc = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  // Characters XML 1.0 does not allow.
  .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');

export function colLetter(i) { // 1 → A
  let s = '';
  while (i > 0) { const m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); }
  return s;
}

/** Excel serial day for 'YYYY-MM-DD' (days since 1899-12-30). */
export function excelDate(ymd) {
  const [y, m, d] = ymd.split('-').map(Number);
  return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 86400000);
}

/** Excel sheet names: at most 31 characters, none of []:*?/\ , unique. */
export function sheetName(name, used) {
  let base = String(name).replace(/[[\]:*?/\\]/g, ' ').trim().slice(0, 31) || 'Sheet';
  let n = base, i = 2;
  while (used.has(n.toLowerCase())) { const suffix = ` (${i++})`; n = base.slice(0, 31 - suffix.length) + suffix; }
  used.add(n.toLowerCase());
  return n;
}

// Style indexes in styles.xml (cellXfs). Keep in step with STYLES below.
export const S = {
  plain: 0, headLeft: 1, headRight: 2, text: 3, int: 4, decimal: 5, date: 6,
  critText: 7, critBold: 8, critInt: 9, totalText: 10, totalInt: 11,
  title: 12, subtitle: 13, heading: 14, itemLabel: 15, itemValue: 16, itemNote: 17,
  critLabel: 18, critValue: 19, critNote: 20, aboutTitle: 21, aboutLabel: 22, headingCell: 23,
};

export const STYLES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="0.0"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy"/></numFmts>
<fonts count="7">
<font><sz val="10"/><color rgb="FF15181C"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="10"/><color rgb="FF15181C"/><name val="Arial"/><family val="2"/></font>
<font><sz val="10"/><color rgb="FF8C1D17"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="10"/><color rgb="FF8C1D17"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="14"/><color rgb="FF15181C"/><name val="Arial"/><family val="2"/></font>
<font><sz val="10"/><color rgb="FF4F5861"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="10"/><color rgb="FF2152C4"/><name val="Arial"/><family val="2"/></font>
</fonts>
<fills count="4">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFEEF2FB"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFBECEA"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="4">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left/><right/><top/><bottom style="thin"><color rgb="FFD5D9D4"/></bottom><diagonal/></border>
<border><left/><right/><top/><bottom style="thin"><color rgb="FF15181C"/></bottom><diagonal/></border>
<border><left/><right/><top style="thin"><color rgb="FF15181C"/></top><bottom/><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="24">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="1" fillId="2" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
<xf numFmtId="1" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="3" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="1" fontId="2" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="3" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="1" fontId="1" fillId="0" borderId="3" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="6" fillId="0" borderId="2" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
<xf numFmtId="1" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="1" fontId="3" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="0" fontId="5" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="2" xfId="0" applyBorder="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;

const cellXml = (ref, value, style) => {
  if (value === null || value === undefined || value === '') return style ? `<c r="${ref}" s="${style}"/>` : '';
  if (typeof value === 'object' && value.f) return `<c r="${ref}" s="${style}"><f>${esc(value.f)}</f></c>`;
  if (typeof value === 'number') return Number.isFinite(value) ? `<c r="${ref}" s="${style}"><v>${value}</v></c>` : '';
  if (typeof value === 'boolean') return `<c r="${ref}" s="${style}" t="b"><v>${value ? 1 : 0}</v></c>`;
  return `<c r="${ref}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${esc(value)}</t></is></c>`;
};

function cellValue(value, type) {
  if (value === null || value === undefined || value === '') return null;
  if (type === 'date') return /^\d{4}-\d{2}-\d{2}/.test(String(value)) ? excelDate(String(value).slice(0, 10)) : String(value);
  if ((type === 'int' || type === 'decimal') && typeof value === 'string' && value.trim() !== '' && !Number.isNaN(Number(value))) return Number(value);
  return value;
}

function bodyStyle(type, critical, key) {
  if (critical && ['issue', 'severity'].includes(key)) return S.critBold;
  if (critical && ['alerts', 'days'].includes(key)) return type === 'int' ? S.critInt : S.critText;
  if (type === 'int') return S.int;
  if (type === 'decimal') return S.decimal;
  if (type === 'date') return S.date;
  return S.text;
}

function sheetFrame(sheet, rtl, rowsXml, extra) {
  const cols = sheet.columns.map((c, i) => `<col min="${i + 1}" max="${i + 1}" width="${c.width || 14}" customWidth="1"/>`).join('');
  const table = sheet.kind === 'table';
  const pane = table ? '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/>' : '';
  const wide = sheet.columns.reduce((n, c) => n + (c.width || 14), 0) > 100;
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    + '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    + '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
    + `<sheetViews><sheetView workbookViewId="0"${rtl ? ' rightToLeft="1"' : ''}>${pane}</sheetView></sheetViews>`
    + '<sheetFormatPr defaultRowHeight="15"/>'
    + `<cols>${cols}</cols>`
    + `<sheetData>${rowsXml}</sheetData>`
    + (extra.autoFilter ? `<autoFilter ref="${extra.autoFilter}"/>` : '')
    + '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
    + `<pageSetup paperSize="9" orientation="${wide ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>`
    + '</worksheet>';
}

function tableSheet(sheet, rtl) {
  const cols = sheet.columns;
  const keys = cols.map((c) => c.key);
  const letter = Object.fromEntries(keys.map((k, i) => [k, colLetter(i + 1)]));
  const rows = [];
  const head = cols.map((c, i) => cellXml(`${colLetter(i + 1)}1`, c.label,
    ((c.type === 'int' || c.type === 'decimal') !== rtl) ? S.headRight : S.headLeft)).join('');
  rows.push(`<row r="1">${head}</row>`);
  const rowFormulas = sheet.rowFormulas || {};
  sheet.rows.forEach((row, idx) => {
    const r = idx + 2;
    const critical = row.style === 'critical';
    const cells = cols.map((c, i) => {
      const ref = `${colLetter(i + 1)}${r}`;
      if (rowFormulas[c.key]) {
        const [num, den] = rowFormulas[c.key].ratio;
        return cellXml(ref, { f: `IF(${letter[den]}${r}=0,"",ROUND(${letter[num]}${r}/${letter[den]}${r},0))` }, bodyStyle(c.type, critical, c.key));
      }
      return cellXml(ref, cellValue(row[c.key], c.type), bodyStyle(c.type, critical, c.key));
    }).join('');
    rows.push(`<row r="${r}">${cells}</row>`);
  });
  const last = sheet.rows.length + 1;
  const totals = sheet.totals;
  if (totals) {
    const tr = last + 1;
    const cells = cols.map((c, i) => {
      const ref = `${colLetter(i + 1)}${tr}`;
      if (i === 0) return cellXml(ref, totals.label, S.totalText);
      if (totals.sum.includes(c.key)) return cellXml(ref, { f: `SUM(${letter[c.key]}2:${letter[c.key]}${last})` }, S.totalInt);
      const f = (totals.formulas || {})[c.key];
      if (f) { const [num, den] = f.ratio; return cellXml(ref, { f: `IF(${letter[den]}${tr}=0,"",ROUND(${letter[num]}${tr}/${letter[den]}${tr},0))` }, S.totalInt); }
      return cellXml(ref, null, S.totalText);
    }).join('');
    rows.push(`<row r="${tr}">${cells}</row>`);
  }
  const autoFilter = sheet.rows.length ? `A1:${colLetter(cols.length)}${last}` : null;
  return { xml: sheetFrame(sheet, rtl, rows.join(''), { autoFilter }), autoFilter, printTitles: true };
}

function summarySheet(sheet, rtl) {
  const rows = [];
  sheet.rows.forEach((row, idx) => {
    const r = idx + 1;
    const A = `A${r}`, B = `B${r}`, C = `C${r}`;
    let cells = '';
    if (row.kind === 'title') cells = cellXml(A, row.label, S.title);
    else if (row.kind === 'subtitle') cells = cellXml(A, row.label, S.subtitle);
    else if (row.kind === 'heading') cells = cellXml(A, row.label, S.heading) + cellXml(B, null, S.headingCell) + cellXml(C, null, S.headingCell);
    else if (row.kind === 'item') {
      const crit = row.style === 'critical';
      cells = cellXml(A, row.label, crit ? S.critLabel : S.itemLabel)
        + cellXml(B, row.value === undefined ? null : row.value, crit ? S.critValue : S.itemValue)
        + cellXml(C, row.note || null, crit ? S.critNote : S.itemNote);
    }
    rows.push(cells ? `<row r="${r}">${cells}</row>` : `<row r="${r}"/>`);
  });
  return { xml: sheetFrame(sheet, rtl, rows.join(''), {}), autoFilter: null, printTitles: false };
}

function aboutSheet(about) {
  const lines = [['WO Tracker data copy', ''], ['Generated', about.generatedAt], ['Orders', about.orders], ['Format version', about.format],
    ['Note', 'A complete copy of every order. Columns marked "calculated" are for reading only.'], ['Not in this file', about.notIncluded || '']];
  const rows = lines.map(([a, b], i) => `<row r="${i + 1}">${cellXml(`A${i + 1}`, a, i === 0 ? S.aboutTitle : S.aboutLabel)}${cellXml(`B${i + 1}`, b, S.plain)}</row>`).join('');
  return { xml: sheetFrame({ kind: 'about', columns: [{ width: 22 }, { width: 60 }] }, false, rows, {}), autoFilter: null, printTitles: false };
}

/** The .xlsx file for a workbook model, as bytes. */
export function workbookXlsx(model) {
  const rtl = model.dir === 'rtl';
  const used = new Set();
  const sheets = model.sheets.map((sh) => ({ name: sheetName(sh.name, used), ...(sh.kind === 'summary' ? summarySheet(sh, rtl) : tableSheet(sh, rtl)) }));
  if (model.about) sheets.push({ name: sheetName('About', used), ...aboutSheet(model.about) });
  const files = [];
  const add = (name, text) => files.push({ name, data: utf8(text) });
  add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
    + '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    + '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    + sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')
    + '</Types>');
  add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  const quoted = (n) => `'${n.replace(/'/g, "''")}'`;
  const defined = [];
  sheets.forEach((s, i) => {
    if (s.autoFilter) {
      const [a, b] = s.autoFilter.split(':');
      const abs = (ref) => ref.replace(/^([A-Z]+)(\d+)$/, '$$$1$$$2');
      defined.push(`<definedName name="_xlnm._FilterDatabase" localSheetId="${i}" hidden="1">${esc(quoted(s.name))}!${abs(a)}:${abs(b)}</definedName>`);
    }
    if (s.printTitles) defined.push(`<definedName name="_xlnm.Print_Titles" localSheetId="${i}">${esc(quoted(s.name))}!$1:$1</definedName>`);
  });
  add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    + '<bookViews><workbookView/></bookViews>'
    + `<sheets>${sheets.map((s, i) => `<sheet name="${esc(s.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')}</sheets>`
    + (defined.length ? `<definedNames>${defined.join('')}</definedNames>` : '')
    + '<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>');
  add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join('')
    + `<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`);
  add('xl/styles.xml', STYLES);
  sheets.forEach((s, i) => add(`xl/worksheets/sheet${i + 1}.xml`, s.xml));
  return zipStored(files);
}
