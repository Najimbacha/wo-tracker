// Reports for management: daily, weekly (Saturday–Friday), monthly, for everyone or
// one contractor, in English or Arabic, as PDF, Excel or images.
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Actions;
import 'package:printing/printing.dart';

import '../../app/app_state.dart';
import '../../app/scope.dart';
import '../../domain/order_input.dart';
import '../../report/files.dart';
import '../../report/pdf_report.dart';
import '../../report/xlsx_writer.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _kind = 'daily';
  late String _date = context.appRead.today;
  late String _lang = context.appRead.lang;
  String? _contractor; // null = everyone
  bool _busy = false;
  Future<Uint8List>? _pdf;
  String _pdfKey = '';

  List<OrderInput> _orders(AppState app) =>
      _contractor == null ? app.orders : app.orders.where((o) => (o.contractor ?? '') == _contractor).toList();

  Map<String, Object?> _doc(AppState app) => app.reportDoc.build(
        _orders(app),
        _kind,
        _date,
        app.today,
        s: app.stringsFor(_lang),
        hijri: app.calendar,
        preparedBy: app.data.settings.preparedBy,
        generatedAt: riyadhNow(),
      );

  String _fileStem() {
    final name = switch (_kind) { 'weekly' => 'weekly-report', 'monthly' => 'monthly-report', _ => 'daily-report' };
    final con = _contractor == null ? '' : '-${_contractor!.replaceAll(RegExp(r'[^A-Za-z0-9؀-ۿ]+'), '-')}';
    return '$name-$_date$con${_lang == 'ar' ? '-ar' : ''}';
  }

  Future<Uint8List> _buildPdf(AppState app) async => reportPdf(_doc(app), await ReportFonts.load());

  Future<void> _savePdf(AppState app) async {
    await _run(app, () async {
      final bytes = await _buildPdf(app);
      return saveOrShare(bytes, '${_fileStem()}.pdf');
    });
  }

  Future<void> _saveExcel(AppState app) async {
    await _run(app, () async {
      final wb = app.exportDoc.reportWorkbook(_orders(app), _kind, _date, app.today,
          s: app.stringsFor(_lang), hijri: app.calendar, preparedBy: app.data.settings.preparedBy, generatedAt: riyadhNow());
      return saveOrShare(workbookXlsx(wb), '${_fileStem()}.xlsx');
    });
  }

  Future<void> _saveImages(AppState app) async {
    await _run(app, () async {
      final bytes = await _buildPdf(app);
      final pages = <(Uint8List, String)>[];
      var i = 0;
      await for (final page in Printing.raster(bytes, dpi: 160)) {
        i++;
        pages.add((await page.toPng(), '${_fileStem()}${i == 1 ? '' : '-$i'}.png'));
      }
      return saveOrShareMany(pages);
    });
  }

  Future<void> _run(AppState app, Future<SavedFile?> Function() job) async {
    setState(() => _busy = true);
    try {
      final saved = await job();
      if (saved != null && !saved.shared) {
        app.showToast(app.s.t('toast.reportSaved', {'report': app.s.t('report.$_kind'), 'format': saved.path.split('.').last.toUpperCase()}));
      }
    } catch (e) {
      app.showToast(app.s.t('toast.exportFailed', {'reason': fileErrorReason(e, app.s.t)}), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (!app.data.loaded) return const DelayedLoader();
    // Rebuilt only when something in the orders changes (not on every sync reload, which
    // would make the preview flicker while it is being read).
    final fingerprint = Object.hashAll([
      for (final o in app.orders)
        Object.hash(o.id, o.woNumber, o.lastChangeDate, o.state, o.stateDate, o.contractor, o.district, o.type, o.receivedDate,
            // category, excavation and meters change which steps an order has, and so its alerts
            Object.hash(o.category, o.needsExcavation, Object.hashAll(o.meters.map((m) => m.id))),
            Object.hashAll(o.steps.entries.map((e) => Object.hash(e.key, e.value.done, e.value.na))),
            Object.hashAll(o.holdPeriods.map((h) => Object.hash(h.from, h.to))),
            Object.hashAll(o.permits.map((p) => Object.hash(p.startDate, p.endDate))),
            Object.hashAll(o.segments.map((g) => Object.hash(g.id, g.base, g.width, g.lengthM, g.tiled))), Object.hashAll(o.cableRuns.map((c) => Object.hash(c.voltage, c.sizeMm2, c.lengthM)))),
      // changed alert timings in Settings change the report's alerts too
      Object.hashAll(app.alertSettings.entries.map((e) => Object.hash(e.key, e.value))),
    ]);
    final key = '$_kind|$_date|$_lang|$_contractor|$fingerprint|${app.today}|${app.data.settings.preparedBy}';
    if (key != _pdfKey) {
      _pdfKey = key;
      _pdf = _buildPdf(app);
    }
    final contractors = [for (final c in app.data.contractors) if (!c.deleted) c.name];
    final phone = isPhone(context);
    final controls = ListView(padding: const EdgeInsets.all(20), children: [
      Text(s.t('nav.reports'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      SegmentedButton<String>(
        segments: [for (final k in const ['daily', 'weekly', 'monthly']) ButtonSegment(value: k, label: Text(s.t('report.$k')))],
        selected: {_kind},
        onSelectionChanged: (v) => setState(() => _kind = v.first),
      ),
      const SizedBox(height: 14),
      DateField(label: s.t('report.date'), value: _date, onChanged: (v) => setState(() => _date = v ?? app.today)),
      const SizedBox(height: 6),
      Text(s.t('report.periodHint.$_kind'), style: TextStyle(color: C.faint, fontSize: 12)),
      const SizedBox(height: 14),
      DropdownButtonFormField<String?>(
        style: Theme.of(context).textTheme.bodyLarge,
        initialValue: _contractor,
        isExpanded: true,
        decoration: InputDecoration(labelText: s.t('report.forContractor')),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(s.t('report.allContractors'))),
          for (final c in contractors) DropdownMenuItem<String?>(value: c, child: Text(c)),
          if (_contractor != null && !contractors.contains(_contractor)) DropdownMenuItem<String?>(value: _contractor, child: Text(_contractor!)),
        ],
        onChanged: (v) => setState(() => _contractor = v),
      ),
      const SizedBox(height: 14),
      Text(s.t('report.language'), style: TextStyle(fontSize: 12.5, color: C.muted)),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ar', label: Text('العربية'))],
        selected: {_lang},
        onSelectionChanged: (v) => setState(() => _lang = v.first),
      ),
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: _busy ? null : () => _savePdf(app),
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: Text(s.t('report.savePdf')),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _saveExcel(app),
        icon: const Icon(Icons.table_chart_outlined, size: 18),
        label: Text(s.t('report.saveExcel')),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _saveImages(app),
        icon: const Icon(Icons.image_outlined, size: 18),
        label: Text(s.t('report.saveImage')),
      ),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
      const SizedBox(height: 16),
      Text(s.t('report.preparedByNote', {'name': app.data.settings.preparedBy}), style: TextStyle(color: C.faint, fontSize: 12)),
    ]);
    final preview = FutureBuilder<Uint8List>(
      future: _pdf,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(icon: Icons.error_outline, title: s.t('report.previewFailed'), body: '${snap.error}');
        }
        if (!snap.hasData) return const DelayedLoader();
        final bytes = snap.data!;
        return PdfPreview(
          key: ValueKey(_pdfKey),
          build: (_) async => bytes,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          allowSharing: false,
          allowPrinting: true,
          pdfFileName: '${_fileStem()}.pdf',
          maxPageWidth: 760,
          scrollViewDecoration: BoxDecoration(color: C.bg),
        );
      },
    );
    if (phone) {
      return ListView(children: [
        SizedBox(height: 600, child: controls),
        SizedBox(height: 640, child: preview),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 340, child: DecoratedBox(decoration: BoxDecoration(color: C.card, border: BorderDirectional(end: BorderSide(color: C.line))), child: controls)),
      Expanded(child: preview),
    ]);
  }
}
