// Excel (.xlsx) writer with no packages. Follows tools/rules-check/xlsx.mjs line by
// line (that copy is opened with openpyxl and LibreOffice in its tests); the Dart test
// checks this file produces the very same bytes for the shared workbook fixtures.
import 'dart:convert' show utf8;
import 'dart:typed_data';

// ---------------------------------------------------------------- zip (stored)

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c & 0xffffffff;
  }
  return t;
}();

int crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

class ZipEntry {
  final String name;
  final List<int> data;
  const ZipEntry(this.name, this.data);
}

/// A zip with every file stored (no compression), which every Excel version reads.
Uint8List zipStored(List<ZipEntry> files) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;
  List<int> u16(int v) => [v & 0xff, (v >> 8) & 0xff];
  List<int> u32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  const dosTime = 0;
  const dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;
  for (final f in files) {
    final name = utf8.encode(f.name);
    final data = f.data;
    final crc = crc32(data);
    final local = <int>[
      ...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosTime), ...u16(dosDate),
      ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0),
    ];
    out
      ..add(local)
      ..add(name)
      ..add(data);
    central.add(<int>[
      ...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosTime), ...u16(dosDate),
      ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0), ...u16(0),
      ...u16(0), ...u16(0), ...u32(0), ...u32(offset), ...name,
    ]);
    offset += local.length + name.length + data.length;
  }
  final centralBytes = central.takeBytes();
  out
    ..add(centralBytes)
    ..add(<int>[
      ...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length),
      ...u32(centralBytes.length), ...u32(offset), ...u16(0),
    ]);
  return out.takeBytes();
}

// ---------------------------------------------------------------- SpreadsheetML

final _badXml = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]');

String esc(Object s) => '$s'
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(_badXml, '');

String colLetter(int i) {
  var s = '';
  while (i > 0) {
    final m = (i - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    i = (i - 1) ~/ 26;
  }
  return s;
}

/// Excel serial day for 'YYYY-MM-DD' (days since 1899-12-30).
int excelDate(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).difference(DateTime.utc(1899, 12, 30)).inDays;
}

/// Excel sheet names: at most 31 characters, none of []:*?/\ , unique.
String sheetName(String name, Set<String> used) {
  var base = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (base.length > 31) base = base.substring(0, 31);
  if (base.isEmpty) base = 'Sheet';
  var n = base;
  var i = 2;
  while (used.contains(n.toLowerCase())) {
    final suffix = ' (${i++})';
    final keep = 31 - suffix.length;
    n = (base.length > keep ? base.substring(0, keep) : base) + suffix;
  }
  used.add(n.toLowerCase());
  return n;
}

class _S {
  static const plain = 0, headLeft = 1, headRight = 2, text = 3, int_ = 4, decimal = 5, date = 6;
  static const critText = 7, critBold = 8, critInt = 9, totalText = 10, totalInt = 11;
  static const title = 12, subtitle = 13, heading = 14, itemLabel = 15, itemValue = 16, itemNote = 17;
  static const critLabel = 18, critValue = 19, critNote = 20, aboutTitle = 21, aboutLabel = 22, headingCell = 23;
}

const _styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
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
</styleSheet>''';

class _Formula {
  final String f;
  const _Formula(this.f);
}

/// Numbers written as JavaScript would ('3', not '3.0').
String _num(num v) {
  if (v is int) return '$v';
  if (v == v.truncateToDouble() && v.abs() < 1e15) return '${v.toInt()}';
  return '$v';
}

String _cell(String ref, Object? value, int style) {
  if (value == null || value == '') return style != 0 ? '<c r="$ref" s="$style"/>' : '';
  if (value is _Formula) return '<c r="$ref" s="$style"><f>${esc(value.f)}</f></c>';
  if (value is num) return value.isFinite ? '<c r="$ref" s="$style"><v>${_num(value)}</v></c>' : '';
  if (value is bool) return '<c r="$ref" s="$style" t="b"><v>${value ? 1 : 0}</v></c>';
  return '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${esc(value)}</t></is></c>';
}

Object? _cellValue(Object? value, String type) {
  if (value == null || value == '') return null;
  if (type == 'date') {
    final s = '$value';
    return RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s) ? excelDate(s.substring(0, 10)) : s;
  }
  if ((type == 'int' || type == 'decimal') && value is String && value.trim().isNotEmpty && num.tryParse(value) != null) {
    return num.parse(value);
  }
  return value;
}

int _bodyStyle(String type, bool critical, String key) {
  if (critical && (key == 'issue' || key == 'severity')) return _S.critBold;
  if (critical && (key == 'alerts' || key == 'days')) return type == 'int' ? _S.critInt : _S.critText;
  if (type == 'int') return _S.int_;
  if (type == 'decimal') return _S.decimal;
  if (type == 'date') return _S.date;
  return _S.text;
}

class _Sheet {
  final String name;
  final String xml;
  final String? autoFilter;
  final bool printTitles;
  const _Sheet(this.name, this.xml, this.autoFilter, this.printTitles);
}

List<Map<String, Object?>> _maps(Object? v) => ((v as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
num _width(Map<String, Object?> c) => (c['width'] as num?) ?? 14;

String _frame(String kind, List<Map<String, Object?>> columns, bool rtl, String rowsXml, String? autoFilter) {
  final cols = [
    for (var i = 0; i < columns.length; i++) '<col min="${i + 1}" max="${i + 1}" width="${_num(_width(columns[i]))}" customWidth="1"/>',
  ].join();
  final table = kind == 'table';
  final pane = table ? '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/>' : '';
  final wide = columns.fold<num>(0, (n, c) => n + _width(c)) > 100;
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<sheetViews><sheetView workbookViewId="0"${rtl ? ' rightToLeft="1"' : ''}>$pane</sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="15"/>'
      '<cols>$cols</cols>'
      '<sheetData>$rowsXml</sheetData>'
      '${autoFilter != null ? '<autoFilter ref="$autoFilter"/>' : ''}'
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
      '<pageSetup paperSize="9" orientation="${wide ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>'
      '</worksheet>';
}

_Sheet _table(String name, Map<String, Object?> sheet, bool rtl) {
  final cols = _maps(sheet['columns']);
  final rowsIn = _maps(sheet['rows']);
  final keys = cols.map((c) => c['key'] as String).toList();
  final letter = {for (var i = 0; i < keys.length; i++) keys[i]: colLetter(i + 1)};
  final rows = <String>[];
  final head = [
    for (var i = 0; i < cols.length; i++)
      _cell('${colLetter(i + 1)}1', cols[i]['label'],
          ((cols[i]['type'] == 'int' || cols[i]['type'] == 'decimal') != rtl) ? _S.headRight : _S.headLeft),
  ].join();
  rows.add('<row r="1">$head</row>');
  final rowFormulas = ((sheet['rowFormulas'] as Map?) ?? const {}).cast<String, Object?>();
  for (var idx = 0; idx < rowsIn.length; idx++) {
    final row = rowsIn[idx];
    final r = idx + 2;
    final critical = row['style'] == 'critical';
    final cells = StringBuffer();
    for (var i = 0; i < cols.length; i++) {
      final c = cols[i];
      final key = c['key'] as String;
      final type = c['type'] as String;
      final ref = '${colLetter(i + 1)}$r';
      final rf = rowFormulas[key] as Map?;
      if (rf != null) {
        final ratio = (rf['ratio'] as List).cast<String>();
        cells.write(_cell(ref, _Formula('IF(${letter[ratio[1]]}$r=0,"",ROUND(${letter[ratio[0]]}$r/${letter[ratio[1]]}$r,0))'),
            _bodyStyle(type, critical, key)));
      } else {
        cells.write(_cell(ref, _cellValue(row[key], type), _bodyStyle(type, critical, key)));
      }
    }
    rows.add('<row r="$r">$cells</row>');
  }
  final last = rowsIn.length + 1;
  final totals = (sheet['totals'] as Map?)?.cast<String, Object?>();
  if (totals != null) {
    final tr = last + 1;
    final sum = ((totals['sum'] as List?) ?? const []).cast<String>();
    final formulas = ((totals['formulas'] as Map?) ?? const {}).cast<String, Object?>();
    final cells = StringBuffer();
    for (var i = 0; i < cols.length; i++) {
      final key = cols[i]['key'] as String;
      final ref = '${colLetter(i + 1)}$tr';
      if (i == 0) {
        cells.write(_cell(ref, totals['label'], _S.totalText));
      } else if (sum.contains(key)) {
        cells.write(_cell(ref, _Formula('SUM(${letter[key]}2:${letter[key]}$last)'), _S.totalInt));
      } else if (formulas[key] != null) {
        final ratio = ((formulas[key] as Map)['ratio'] as List).cast<String>();
        cells.write(_cell(ref, _Formula('IF(${letter[ratio[1]]}$tr=0,"",ROUND(${letter[ratio[0]]}$tr/${letter[ratio[1]]}$tr,0))'), _S.totalInt));
      } else {
        cells.write(_cell(ref, null, _S.totalText));
      }
    }
    rows.add('<row r="$tr">$cells</row>');
  }
  final autoFilter = rowsIn.isNotEmpty ? 'A1:${colLetter(cols.length)}$last' : null;
  return _Sheet(name, _frame('table', cols, rtl, rows.join(), autoFilter), autoFilter, true);
}

_Sheet _summary(String name, Map<String, Object?> sheet, bool rtl) {
  final rowsIn = _maps(sheet['rows']);
  final rows = StringBuffer();
  for (var idx = 0; idx < rowsIn.length; idx++) {
    final row = rowsIn[idx];
    final r = idx + 1;
    var cells = '';
    switch (row['kind']) {
      case 'title':
        cells = _cell('A$r', row['label'], _S.title);
      case 'subtitle':
        cells = _cell('A$r', row['label'], _S.subtitle);
      case 'heading':
        cells = _cell('A$r', row['label'], _S.heading) + _cell('B$r', null, _S.headingCell) + _cell('C$r', null, _S.headingCell);
      case 'item':
        final crit = row['style'] == 'critical';
        final note = row['note'];
        cells = _cell('A$r', row['label'], crit ? _S.critLabel : _S.itemLabel) +
            _cell('B$r', row['value'], crit ? _S.critValue : _S.itemValue) +
            _cell('C$r', (note == null || note == '') ? null : note, crit ? _S.critNote : _S.itemNote);
    }
    rows.write(cells.isNotEmpty ? '<row r="$r">$cells</row>' : '<row r="$r"/>');
  }
  return _Sheet(name, _frame('summary', _maps(sheet['columns']), rtl, rows.toString(), null), null, false);
}

_Sheet _about(String name, Map<String, Object?> about) {
  final lines = <List<Object?>>[
    ['WO Tracker data copy', ''],
    ['Generated', about['generatedAt']],
    ['Orders', about['orders']],
    ['Format version', about['format']],
    ['Note', 'A complete copy of every order. Columns marked "calculated" are for reading only.'],
    ['Not in this file', about['notIncluded'] ?? ''],
  ];
  final rows = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    rows.write('<row r="${i + 1}">${_cell('A${i + 1}', lines[i][0], i == 0 ? _S.aboutTitle : _S.aboutLabel)}${_cell('B${i + 1}', lines[i][1], _S.plain)}</row>');
  }
  return _Sheet(name, _frame('about', const [{'width': 22}, {'width': 60}], false, rows.toString(), null), null, false);
}

/// The .xlsx file for a workbook model (from ExportDoc), as bytes.
Uint8List workbookXlsx(Map<String, Object?> model) {
  final rtl = model['dir'] == 'rtl';
  final used = <String>{};
  final sheets = <_Sheet>[];
  for (final sh in _maps(model['sheets'])) {
    final name = sheetName(sh['name'] as String, used);
    sheets.add(sh['kind'] == 'summary' ? _summary(name, sh, rtl) : _table(name, sh, rtl));
  }
  final about = (model['about'] as Map?)?.cast<String, Object?>();
  if (about != null) sheets.add(_about(sheetName('About', used), about));

  final files = <ZipEntry>[];
  void add(String name, String text) => files.add(ZipEntry(name, utf8.encode(text)));
  add(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
          '</Types>');
  add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  String quoted(String n) => "'${n.replaceAll("'", "''")}'";
  String abs(String ref) => ref.replaceAllMapped(RegExp(r'^([A-Z]+)(\d+)$'), (m) => '\$${m[1]}\$${m[2]}');
  final defined = <String>[];
  for (var i = 0; i < sheets.length; i++) {
    final s = sheets[i];
    if (s.autoFilter != null) {
      final parts = s.autoFilter!.split(':');
      defined.add('<definedName name="_xlnm._FilterDatabase" localSheetId="$i" hidden="1">${esc(quoted(s.name))}!${abs(parts[0])}:${abs(parts[1])}</definedName>');
    }
    if (s.printTitles) defined.add('<definedName name="_xlnm.Print_Titles" localSheetId="$i">${esc(quoted(s.name))}!\$1:\$1</definedName>');
  }
  add(
      'xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<bookViews><workbookView/></bookViews>'
          '<sheets>${[for (var i = 0; i < sheets.length; i++) '<sheet name="${esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets>'
          '${defined.isNotEmpty ? '<definedNames>${defined.join()}</definedNames>' : ''}'
          '<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>');
  add(
      'xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
          '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
  add('xl/styles.xml', _styles);
  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', sheets[i].xml);
  }
  return zipStored(files);
}
