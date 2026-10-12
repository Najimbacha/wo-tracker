// The report as an A4 PDF, in the approved design (tools/report-preview/render.mjs).
// Nothing is calculated here: the content comes from ReportDoc.build.
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class _P {
  static final ink = PdfColor.fromHex('#15181C');
  static final muted = PdfColor.fromHex('#4F5861');
  static final faint = PdfColor.fromHex('#6B747C');
  static final line = PdfColor.fromHex('#D5D9D4');
  static final soft = PdfColor.fromHex('#E2E5E1');
  static final track = PdfColor.fromHex('#F4F5F3');
  static final accent = PdfColor.fromHex('#2152C4');
  static final accentDark = PdfColor.fromHex('#173C94');
  static final grey = PdfColor.fromHex('#B8BEB7');
  static final greyDark = PdfColor.fromHex('#8F968E');
  static final alertBg = PdfColor.fromHex('#FBECEA');
  static final alert = PdfColor.fromHex('#8C1D17');
}

class ReportFonts {
  final pw.Font sans, sansBold, arabic, arabicBold;
  const ReportFonts(this.sans, this.sansBold, this.arabic, this.arabicBold);

  static ReportFonts? _cache;
  static Future<ReportFonts> load() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
    _cache = ReportFonts(
      await f('IBMPlexSans-Regular'),
      await f('IBMPlexSans-SemiBold'),
      await f('IBMPlexSansArabic-Regular'),
      await f('IBMPlexSansArabic-SemiBold'),
    );
    return _cache!;
  }
}

List<Map<String, Object?>> _rows(Object? section) => (((section as Map?)?['rows'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
String _str(Object? v) => v == null ? '' : '$v';
String _num(Object? v) => v == null ? '–' : '$v';

/// Builds the PDF for a report document.
Future<Uint8List> reportPdf(Map<String, Object?> doc, ReportFonts fonts) async {
  final rtl = doc['dir'] == 'rtl';
  final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final base = rtl ? fonts.arabic : fonts.sans;
  final bold = rtl ? fonts.arabicBold : fonts.sansBold;
  final theme = pw.ThemeData.withFont(base: base, bold: bold, fontFallback: rtl ? [fonts.sans] : [fonts.arabic]);
  final pdf = pw.Document(theme: theme, title: '${(doc['header'] as Map)['eyebrow']} · ${(doc['header'] as Map)['title']}', creator: 'WO Tracker');

  final h = Map<String, Object?>.from(doc['header'] as Map);
  final limits = Map<String, Object?>.from((doc['limits'] as Map?) ?? const {});
  final moreText = _str(doc['moreText']);
  final empty = _str(doc['empty']);

  pw.TextStyle st({double size = 9, PdfColor? color, bool strong = false}) => pw.TextStyle(fontSize: size, color: color ?? _P.ink, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal);
  pw.Widget t(String s, {double size = 9, PdfColor? color, bool strong = false, pw.TextAlign? align}) =>
      pw.Text(s, style: st(size: size, color: color, strong: strong), textAlign: align);
  // Numbers and codes always read left to right.
  pw.Widget n(String s, {double size = 9, PdfColor? color, bool strong = false, pw.TextAlign? align}) =>
      pw.Text(s, style: st(size: size, color: color, strong: strong), textAlign: align, textDirection: pw.TextDirection.ltr);
  pw.Widget more(int total, int shown) => total > shown
      ? pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: t(moreText.replaceAll('{count}', '${total - shown}'), size: 8.5, color: _P.muted))
      : pw.SizedBox();
  pw.Widget heading(String title, [String? small]) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 9),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Expanded(child: t(title, size: 11, strong: true)),
          if (small != null && small.isNotEmpty) t(small, size: 8.5, color: _P.faint),
        ]),
      );

  // Header
  final header = pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 11),
    decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _P.ink, width: 1.6))),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          t(_str(h['eyebrow']), size: 8.5, color: _P.accent, strong: true),
          pw.SizedBox(height: 5),
          t(_str(h['title']), size: 19, strong: true),
          if (h['hijri'] != null) t(_str(h['hijri']), size: 10, color: _P.muted),
        ]),
      ),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        t(_str(h['preparedBy']), size: 8.5, color: _P.muted),
        t(_str(h['generated']), size: 8.5, color: _P.muted),
      ]),
    ]),
  );

  // KPI tiles
  final kpis = ((doc['kpis'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
  final kpiRow = pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(color: _P.line), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
    child: pw.Row(children: [
      for (var i = 0; i < kpis.length; i++)
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: pw.BoxDecoration(
              color: kpis[i]['tone'] == 'alert' ? _P.alertBg : null,
              // The divider sits on the side facing the next tile (rows run right to left in Arabic).
              border: i == kpis.length - 1 ? null : (rtl ? pw.Border(left: pw.BorderSide(color: _P.line)) : pw.Border(right: pw.BorderSide(color: _P.line))),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t(_str(kpis[i]['label']), size: 8.5, color: kpis[i]['tone'] == 'alert' ? _P.alert : _P.muted),
              n(_num(kpis[i]['value']), size: 21, strong: true, color: kpis[i]['tone'] == 'alert' ? _P.alert : _P.ink),
              t(_str(kpis[i]['note']), size: 8, color: kpis[i]['tone'] == 'alert' ? _P.alert : _P.muted),
            ]),
          ),
        ),
    ]),
  );

  // Trend chart
  final tr = Map<String, Object?>.from(doc['trend'] as Map);
  final days = ((tr['days'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
  final maxV = ((tr['max'] as num?) ?? 1).toDouble().clamp(1, double.infinity);
  const chartH = 110.0;
  final legend = Map<String, Object?>.from((tr['legend'] as Map?) ?? const {});
  final lastDay = days.isEmpty ? null : days.last;
  final trend = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    pw.Row(children: [
      pw.Expanded(child: t(_str(tr['title']), size: 11, strong: true)),
      pw.Container(width: 8, height: 8, color: _P.grey),
      pw.SizedBox(width: 4),
      t(_str(legend['received']), size: 8.5, color: _P.muted),
      pw.SizedBox(width: 10),
      pw.Container(width: 8, height: 8, color: _P.accent),
      pw.SizedBox(width: 4),
      t(_str(legend['completed']), size: 8.5, color: _P.muted),
    ]),
    pw.SizedBox(height: 9),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.SizedBox(
        width: 18,
        height: chartH,
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          n('${maxV.round()}', size: 7.5, color: _P.faint),
          n('${(maxV / 2).round()}', size: 7.5, color: _P.faint),
          n('0', size: 7.5, color: _P.faint),
        ]),
      ),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Container(
          height: chartH,
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _P.greyDark))),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            for (var i = 0; i < days.length; i++)
              pw.Expanded(
                child: pw.Padding(
                  padding: pw.EdgeInsets.symmetric(horizontal: days.length > 20 ? 1 : 3),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Expanded(
                      child: pw.Container(
                          height: ((days[i]['received'] as num?) ?? 0) / maxV * (chartH - 2),
                          color: i == days.length - 1 ? _P.greyDark : _P.grey),
                    ),
                    pw.SizedBox(width: 1.5),
                    pw.Expanded(
                      child: pw.Container(
                          height: ((days[i]['completed'] as num?) ?? 0) / maxV * (chartH - 2),
                          color: i == days.length - 1 ? _P.accentDark : _P.accent),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    ]),
    pw.SizedBox(height: 5),
    pw.Padding(
      padding: const pw.EdgeInsetsDirectional.only(start: 24), // under the bars, past the axis labels
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        if (days.isNotEmpty) t(_str(days.first['label']), size: 7.5, color: _P.faint),
        if (days.length > 2) t(_str(days[(days.length - 1) ~/ 2]['label']), size: 7.5, color: _P.faint),
        if (lastDay != null) t('${_str(lastDay['label'])}: ${lastDay['received']} / ${lastDay['completed']}', size: 7.5, strong: true),
      ]),
    ),
    pw.SizedBox(height: 6),
    t(_str(tr['summary']), size: 8.5, color: _P.muted),
  ]);

  // Open orders by stage
  final stageRows = _rows(doc['stages']);
  final stageMax = stageRows.fold<num>(1, (m, r) => ((r['value'] as num?) ?? 0) > m ? (r['value'] as num) : m);
  final stages = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    heading(_str((doc['stages'] as Map)['title'])),
    for (final r in stageRows)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(children: [
          pw.SizedBox(width: 110, child: t(_str(r['label']), size: 9)),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Container(
              height: 11,
              color: _P.track,
              alignment: rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              child: pw.LayoutBuilder(builder: (ctx, c) => pw.Container(width: (c?.maxWidth ?? 200) * (((r['value'] as num?) ?? 0) / stageMax), height: 11, color: _P.accent)),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.SizedBox(width: 26, child: n(_num(r['value']), strong: true, align: pw.TextAlign.right)),
        ]),
      ),
  ]);

  // A three-column list (steps completed, orders completed)
  pw.Widget grid3(List<pw.Widget> cells) => pw.LayoutBuilder(builder: (ctx, c) {
        final w = ((c?.maxWidth ?? 500) - 2 * 18) / 3;
        return pw.Wrap(spacing: 18, children: [for (final cell in cells) pw.SizedBox(width: w, child: cell)]);
      });
  pw.Widget cell(String label, String value, {bool small = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _P.soft))),
        child: pw.Row(children: [
          pw.Expanded(child: t(label, size: small ? 8.5 : 9)),
          n(value, size: small ? 8.5 : 9, strong: !small, color: small ? _P.muted : _P.ink),
        ]),
      );

  final stepRows = _rows(doc['steps']);
  final steps = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    heading(_str((doc['steps'] as Map)['title'])),
    if (stepRows.isEmpty) t(empty, color: _P.faint) else grid3([for (final r in stepRows) cell(_str(r['label']), _num(r['value']))]),
  ]);

  // Tables
  // The PDF library's tables don't follow right-to-left text, so for Arabic the column
  // order is reversed here (the first column then sits on the right, as in the design).
  List<T> ord<T>(List<T> l) => rtl ? l.reversed.toList() : l;
  pw.Widget table(List<Map<String, Object?>> columns, List<List<pw.Widget>> body, {List<pw.Widget>? total, Map<int, pw.TableColumnWidth>? widths}) => pw.Table(
        columnWidths: widths == null || !rtl ? widths : {for (final e in widths.entries) columns.length - 1 - e.key: e.value},
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _P.ink))),
            repeat: true,
            children: [
              for (final c in ord(columns))
                pw.Padding(
                  padding: const pw.EdgeInsetsDirectional.fromSTEB(0, 5, 6, 5),
                  child: t(_str(c['label']), size: 8, color: _P.muted, strong: true, align: c['numeric'] == true ? pw.TextAlign.right : null),
                ),
            ],
          ),
          for (final r in body)
            pw.TableRow(
              decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _P.soft))),
              children: [for (final w in ord(r)) pw.Padding(padding: const pw.EdgeInsetsDirectional.fromSTEB(0, 5, 6, 5), child: w)],
            ),
          if (total != null)
            pw.TableRow(
              decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _P.ink))),
              children: [for (final w in ord(total)) pw.Padding(padding: const pw.EdgeInsetsDirectional.fromSTEB(0, 5, 6, 5), child: w)],
            ),
        ],
      );

  final delaysSec = Map<String, Object?>.from(doc['delays'] as Map);
  final delayAll = _rows(delaysSec);
  final delayLimit = (limits['delays'] as num?)?.toInt() ?? 25;
  final delayRows = delayAll.take(delayLimit).toList();
  final delayCols = ((delaysSec['columns'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
  // Tables are direct page items (not inside a Column) so a long one continues on the
  // next page instead of failing to fit.
  final delays = <pw.Widget>[
    heading(_str(delaysSec['title']), _str(delaysSec['subtitle'])),
    if (delayRows.isEmpty)
      t(empty, color: _P.faint)
    else
      table(
        delayCols,
        [
          for (final d in delayRows)
            [
              n(_str(d['wo']), size: 8.5),
              n(_str(d['type']), size: 8.5),
              t(_str(d['district']), size: 8.5),
              t(_str(d['contractor']), size: 8.5),
              t(_str(d['issue']), size: 8.5, color: d['severity'] == 'critical' ? _P.alert : _P.ink, strong: d['severity'] == 'critical'),
              n(_num(d['days']), size: 8.5, strong: true, align: pw.TextAlign.right),
            ],
        ],
        widths: const {0: pw.FixedColumnWidth(62), 1: pw.FixedColumnWidth(30), 2: pw.FlexColumnWidth(1.1), 3: pw.FlexColumnWidth(1.2), 4: pw.FlexColumnWidth(2.2), 5: pw.FixedColumnWidth(32)},
      ),
    more(delayAll.length, delayRows.length),
  ];

  final ct = Map<String, Object?>.from(doc['contractors'] as Map);
  final ctCols = ((ct['columns'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
  final ctTotal = Map<String, Object?>.from((ct['total'] as Map?) ?? const {});
  List<pw.Widget> ctRow(Map<String, Object?> c, {bool strong = false}) => [
        t(_str(c['contractor']), size: 8.5, strong: strong),
        n(_num(c['open']), size: 8.5, strong: strong, align: pw.TextAlign.right),
        n(_num(c['completed']), size: 8.5, strong: strong, align: pw.TextAlign.right),
        n(_num(c['lateStarts']), size: 8.5, strong: strong || ((c['lateStarts'] as num?) ?? 0) > 0, color: ((c['lateStarts'] as num?) ?? 0) > 0 && !strong ? _P.alert : _P.ink, align: pw.TextAlign.right),
        n(_num(c['avgDays']), size: 8.5, strong: strong, align: pw.TextAlign.right),
      ];
  final contractors = <pw.Widget>[
    heading(_str(ct['title']), _str(ct['subtitle'])),
    table(ctCols, [for (final c in _rows(ct)) ctRow(c)], total: ctRow(ctTotal, strong: true),
        widths: const {0: pw.FlexColumnWidth(2.4), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1), 4: pw.FlexColumnWidth(1.2)}),
  ];

  final q = Map<String, Object?>.from(doc['quantities'] as Map);
  final qItems = ((q['items'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList();
  final quantities = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    heading(_str(q['title']), _str(q['subtitle'])),
    pw.Row(children: [
      for (var i = 0; i < qItems.length; i++) ...[
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _P.line), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5))),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              n(_num(qItems[i]['value']), size: 14, strong: true),
              t(_str(qItems[i]['label']), size: 7.5, color: _P.muted),
            ]),
          ),
        ),
        if (i < qItems.length - 1) pw.SizedBox(width: 6),
      ],
    ]),
  ]);

  final comp = Map<String, Object?>.from(doc['completed'] as Map);
  final compAll = _rows(comp);
  final compLimit = (limits['completed'] as num?)?.toInt() ?? 30;
  final compRows = compAll.take(compLimit).toList();
  final completed = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    heading(_str(comp['title']), _str(comp['subtitle'])),
    if (compRows.isEmpty)
      t(empty, color: _P.faint)
    else
      grid3([for (final c in compRows) cell('${_str(c['wo'])} · ${_str(c['type'])}', _str(c['daysText']), small: true)]),
    more(compAll.length, compRows.length),
  ]);

  final footerText = _str(doc['footer']);
  final pageText = _str(doc['pageText']);
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(42, 40, 42, 44),
    textDirection: dir,
    maxPages: 60,
    footer: (ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _P.line))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        t(footerText, size: 7, color: _P.faint),
        t(pageText.replaceAll('{page}', '${ctx.pageNumber}').replaceAll('{pages}', '${ctx.pagesCount}'), size: 7, color: _P.faint),
      ]),
    ),
    build: (ctx) => [
      header,
      pw.SizedBox(height: 16),
      kpiRow,
      pw.SizedBox(height: 18),
      trend,
      pw.SizedBox(height: 18),
      stages,
      pw.SizedBox(height: 16),
      steps,
      pw.NewPage(),
      ...delays,
      pw.SizedBox(height: 18),
      ...contractors,
      pw.SizedBox(height: 18),
      quantities,
      pw.SizedBox(height: 18),
      completed,
    ],
  ));
  return pdf.save();
}
