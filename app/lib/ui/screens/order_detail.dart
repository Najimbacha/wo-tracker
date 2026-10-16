// One work order: what it is, what is done, what is next. Every step can be ticked
// here (today or another date), marked Not applicable with a reason, or cleared.
import 'package:flutter/material.dart' hide Actions, StepState;

import '../../data/repository.dart';
import '../../app/scope.dart';
import '../../domain/order_input.dart';
import '../../domain/rules_engine.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/photos.dart';
import 'history_sheet.dart';
import 'permit_dialog.dart';
import 'status_dialog.dart';

/// The order as its own page (phone, or opened from a list).
class OrderPage extends StatelessWidget {
  const OrderPage({super.key, required this.orderId});
  final String orderId;
  @override
  Widget build(BuildContext context) {
    final o = context.app.orderById(orderId);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.card,
        surfaceTintColor: C.card,
        title: o == null ? null : Mono(o.woNumber ?? '', size: 16),
      ),
      body: o == null ? EmptyState(icon: Icons.search_off, title: context.t('order.notFound')) : OrderDetail(orderId: orderId),
    );
  }
}

class OrderDetail extends StatelessWidget {
  const OrderDetail({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final o = app.orderById(orderId);
    if (o == null) return EmptyState(icon: Icons.search_off, title: app.s.t('order.notFound'));
    final ev = app.evaluate(o);
    final phone = isPhone(context);
    return LayoutBuilder(builder: (context, box) {
      // On a big monitor the details stay at a readable width (names, dates and buttons
      // close together) instead of stretching across the whole screen.
      // A very wide screen puts the step groups in two columns, so the page is filled with
      // work to do instead of empty space.
      final twoCols = !phone && box.maxWidth >= 1500;
      final maxW = twoCols ? 1700.0 : 1100.0;
      final end = phone ? 12.0 : (box.maxWidth - maxW - 16).clamp(16.0, double.infinity);
      return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(phone ? 12 : 16, phone ? 12 : 14, end, phone ? 12 : 16),
      children: [
        _Header(order: o, ev: ev),
        const SizedBox(height: 10),
        if (_StageBar.applies(o)) ...[_StageBar(order: o, ev: ev), const SizedBox(height: 10)],
        if (o.deleted)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Banner2(
              text: app.s.t('order.deletedBanner', {'reason': o.deletedReason ?? ''}),
              icon: Icons.delete_outline,
              color: C.critical,
              background: C.criticalSoft,
              action: TextButton(onPressed: () => _restore(context, o), child: Text(app.s.t('common.restore'))),
            ),
          ),
        if (ev.alerts.isNotEmpty) ...[_Alerts(ev: ev), const SizedBox(height: 10)],
        _Facts(order: o, ev: ev),
        const SizedBox(height: 10),
        if (twoCols) _twoColumns(_stepGroups(context, o, ev)) else ..._spaced(_stepGroups(context, o, ev)),
        const SizedBox(height: 10),
        _Notes(order: o),
        const SizedBox(height: 40),
      ],
    );
    });
  }

  static Future<void> _restore(BuildContext context, OrderInput o) async {
    final app = context.appRead;
    await app.apply(o, app.actions.restoreOrder(o, app.data.orders), toast: 'toast.restored');
  }

  static List<Widget> _spaced(List<Widget> groups) => [
        for (final w in groups) ...[w, const SizedBox(height: 10)]
      ];

  /// Groups split over two columns, each new group going under the shorter column.
  static Widget _twoColumns(List<Widget> groups) {
    final left = <Widget>[], right = <Widget>[];
    var l = 0, r = 0;
    for (final g in groups) {
      final weight = g is _StepGroup ? g.steps.length + 2 : 3;
      if (l <= r) {
        left.add(g);
        l += weight;
      } else {
        right.add(g);
        r += weight;
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(children: _spaced(left))),
      const SizedBox(width: 12),
      Expanded(child: Column(children: _spaced(right))),
    ]);
  }

  List<Widget> _stepGroups(BuildContext context, OrderInput o, Evaluation ev) {
    final app = context.app;
    final s = app.s;
    final pkgDefs = (app.rules['packages'] as Map).cast<String, dynamic>();
    final out = <Widget>[];
    // Order-level packages first, grouped as on the design: field work, then each surface
    // segment, then each meter, then close-out.
    final orderSteps = ev.steps.where((x) => x.step.scope == 'order' && x.step.package != 'closeout').toList();
    if (orderSteps.isNotEmpty) {
      out.add(_StepGroup(
        title: s.t('order.section.field'),
        order: o,
        color: stageColor('civil'),
        steps: orderSteps,
      ));
    }
    for (final seg in o.segments) {
      final segSteps = ev.steps.where((x) => x.step.instance == seg.id && x.step.scope == 'segment').toList();
      if (segSteps.isEmpty) continue;
      final base = s.t('order.base.${seg.base}');
      final width = seg.base == 'asphalt' ? (seg.width >= 80 ? s.t('order.width80') : s.t('order.width40')) : null;
      out.add(_StepGroup(
        title: [base, width, s.t('common.metres', {'value': _num(seg.lengthM)}), if (seg.tiled) s.t('order.tiled')].whereType<String>().join(' · '),
        order: o,
        color: stageColor('restoration'),
        steps: segSteps,
      ));
    }
    if (ev.steps.any((x) => x.step.scope == 'segment') == false && app.engine.orderPackages(o).contains('restoration')) {
      out.add(SectionCard(
        title: s.t('order.segments'),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18, color: C.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(s.t('lock.missing_segments'), style: const TextStyle(color: C.warning))),
          TextButton(onPressed: () => editOrder(context, o), child: Text(s.t('order.addSegment'))),
        ]),
      ));
    }
    for (var i = 0; i < o.meters.length; i++) {
      final m = o.meters[i];
      final mSteps = ev.steps.where((x) => x.step.instance == m.id && x.step.scope == 'meter').toList();
      if (mSteps.isEmpty) continue;
      final pkg = mSteps.first.step.package;
      final title = o.meters.length > 1 ? s.t('order.meterOf', {'index': i + 1, 'total': o.meters.length}) : _pkgName(pkgDefs, pkg, app.lang);
      out.add(_StepGroup(title: [title, if (m.number != null && m.number!.isNotEmpty) m.number!].join(' · '), order: o, color: stageColor('meter'), steps: mSteps));
    }
    final close = ev.steps.where((x) => x.step.package == 'closeout').toList();
    if (close.isNotEmpty) out.add(_StepGroup(title: _pkgName(pkgDefs, 'closeout', app.lang), order: o, color: stageColor('closeout'), steps: close));
    return out;
  }

  static String _pkgName(Map<String, dynamic> defs, String pkg, String lang) {
    final d = defs[pkg] as Map?;
    return (d?[lang] ?? d?['en'] ?? pkg) as String;
  }
}

String _num(double v) => v == v.truncateToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

/// The order's journey as a row: stages done (green tick), the one it is in (coloured),
/// and what is still ahead (grey). Only the stages this kind of order goes through.
class _StageBar extends StatelessWidget {
  const _StageBar({required this.order, required this.ev});
  final OrderInput order;
  final Evaluation ev;

  static bool applies(OrderInput o) => o.state != 'cancelled' && o.state != 'merged' && !o.deleted;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final packages = {for (final x in ev.steps) x.step.package};
    final keys = <String>[];
    for (final st in (app.rules['stages'] as List).cast<Map<String, dynamic>>()) {
      final key = st['key'] as String;
      final pk = (st['packages'] as List?)?.cast<String>();
      // "Starting soon" has no steps of its own: it sits between tasreeh and the field work.
      if (pk == null ? packages.contains('tasreeh') : pk.any(packages.contains)) keys.add(key);
    }
    if (keys.length < 2) return const SizedBox.shrink();
    final completed = ev.status == 'completed';
    final at = completed ? keys.length : keys.indexOf(ev.stage ?? '');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) Container(width: 16, height: 2, color: i <= at ? C.success : C.line),
          _chip(s.stage(keys[i]), i < at ? 'done' : (i == at ? 'now' : 'next'), stageColor(keys[i])),
        ],
      ]),
    );
  }

  Widget _chip(String label, String state, Color color) {
    final (bg, fg) = switch (state) {
      'done' => (C.successSoft, C.success),
      'now' => (color, Colors.white),
      _ => (C.chip, C.faint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (state == 'done') ...[Icon(Icons.check, size: 15, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 13, color: fg, fontWeight: state == 'now' ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order, required this.ev});
  final OrderInput order;
  final Evaluation ev;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final o = order;
    final place = [o.district, o.street].whereType<String>().where((x) => x.trim().isNotEmpty).join(', ');
    final line = [
      if (place.isNotEmpty) place,
      o.contractor ?? s.t('common.unassigned'),
      if (o.networkRef != null && o.networkRef!.isNotEmpty) o.networkRef!,
      // The received date (with its Hijri date) stays on one line instead of breaking in the middle.
      if (o.receivedDate != null) s.t('order.receivedOn', {'date': app.date(o.receivedDate!)}).replaceAll(' ', '\u00a0'),
    ].join(' · ');
    final active = ev.status == 'open' || ev.status == 'on_hold';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      runSpacing: 12,
      spacing: 16,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Pill(s.category(o.category), color: o.category == 'emergency' ? C.critical : C.muted, background: o.category == 'emergency' ? C.criticalSoft : C.chip),
              Text('${s.t('order.type')} ${o.type} · ${s.type(o.type)}', style: const TextStyle(color: C.muted, fontSize: 13)),
              StatusChip(ev.status),
            ]),
            const SizedBox(height: 6),
            SelectableText(o.woNumber ?? '—', style: monoStyle.copyWith(fontSize: 26, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(line, style: const TextStyle(color: C.muted, fontSize: 13)),
            if (o.state == 'cancelled' || o.state == 'merged')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  o.state == 'merged'
                      ? s.t('order.mergedInfo', {'wo': app.orderById(o.mergedInto)?.woNumber ?? '—', 'reason': o.stateReason ?? '', 'date': o.stateDate == null ? '' : app.dateShort(o.stateDate!)})
                      : s.t('order.cancelledInfo', {'reason': o.stateReason ?? '', 'date': o.stateDate == null ? '' : app.dateShort(o.stateDate!)}),
                  style: const TextStyle(color: C.muted, fontSize: 13),
                ),
              ),
          ]),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!o.deleted) OutlinedButton.icon(onPressed: () => editOrder(context, o), icon: const Icon(Icons.edit_outlined, size: 17), label: Text(s.t('common.edit'))),
          if (o.state == 'on_hold')
            FilledButton.icon(onPressed: () => _resume(context, o), icon: const Icon(Icons.play_arrow, size: 18), label: Text(s.t('action.resume')))
          else if (active && !o.deleted)
            OutlinedButton.icon(onPressed: () => showStatusDialog(context, o), icon: const Icon(Icons.pause, size: 17), label: Text(s.t('order.putOnHold'))),
          if (o.state == 'cancelled' || o.state == 'merged')
            OutlinedButton.icon(onPressed: () => _reopen(context, o), icon: const Icon(Icons.undo, size: 17), label: Text(s.t('action.reopen'))),
          PopupMenuButton<String>(
            tooltip: s.t('order.moreActions'),
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              switch (v) {
                case 'status':
                  showStatusDialog(context, o);
                case 'history':
                  showHistorySheet(context, o);
                case 'delete':
                  _delete(context, o);
                case 'restore':
                  OrderDetail._restore(context, o);
                case 'permit':
                  showPermitDialog(context, o, null);
              }
            },
            itemBuilder: (_) => [
              if (active && !o.deleted) PopupMenuItem(value: 'status', child: Text(s.t('order.changeStatus'))),
              if (!o.deleted && app.engine.orderPackages(o).contains('tasreeh')) PopupMenuItem(value: 'permit', child: Text(s.t('tasreeh.add'))),
              PopupMenuItem(value: 'history', child: Text(s.t('order.history'))),
              if (!o.deleted) PopupMenuItem(value: 'delete', child: Text(s.t('common.delete'), style: const TextStyle(color: C.critical))),
              if (o.deleted) PopupMenuItem(value: 'restore', child: Text(s.t('common.restore'))),
            ],
          ),
        ]),
      ],
    );
  }

  static Future<void> _resume(BuildContext context, OrderInput o) async {
    final app = context.appRead;
    final open = o.holdPeriods.where((h) => h.to == null);
    final date = await pickDate(context, initial: app.today, first: open.isEmpty ? null : open.first.from, help: app.s.t('hold.resumeOn'));
    if (date == null || !context.mounted) return;
    await app.apply(o, app.actions.resume(o, date, app.today), toast: 'toast.resumed');
  }

  static Future<void> _reopen(BuildContext context, OrderInput o) async {
    final app = context.appRead;
    final ok = await confirmDialog(context,
        title: app.s.t('confirm.reopenTitle', {'wo': o.woNumber ?? ''}), body: app.s.t('confirm.reopenBody'), confirm: app.s.t('action.reopen'));
    if (!ok || !context.mounted) return;
    await app.apply(o, app.actions.reopen(o), toast: 'toast.reopened');
  }

  static Future<void> _delete(BuildContext context, OrderInput o) async {
    final app = context.appRead;
    final reason = await reasonDialog(
      context,
      title: app.s.t('confirm.deleteOrder', {'wo': o.woNumber ?? ''}),
      body: app.s.t('confirm.deleteOrderBody'),
      confirm: app.s.t('confirm.moveToDeleted'),
      suggestions: [app.s.t('delete.reason.twice'), app.s.t('delete.reason.wrongNumber')],
      danger: true,
    );
    if (reason == null || !context.mounted) return;
    final ok = await app.apply(o, app.actions.deleteOrder(o, reason), toast: 'toast.movedToDeleted');
    if (ok && app.selectedOrderId == o.id) app.select(null);
    if (ok && context.mounted && Navigator.of(context).canPop()) Navigator.of(context).maybePop();
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.ev});
  final Evaluation ev;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(children: [
      for (final a in ev.alerts)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: a.severity == 'critical' ? C.criticalSoft : C.warningSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(a.severity == 'critical' ? Icons.error_outline : Icons.warning_amber_rounded, size: 18, color: severityColor(a.severity)),
            const SizedBox(width: 10),
            Expanded(child: Text(s.alert(a), style: TextStyle(color: severityColor(a.severity), fontWeight: FontWeight.w500))),
          ]),
        ),
    ]);
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.order, required this.ev});
  final OrderInput order;
  final Evaluation ev;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final o = order;
    final pkgs = app.engine.orderPackages(o);
    final cards = <Widget>[];
    if (pkgs.contains('tasreeh')) {
      final cur = app.engine.currentPermit(o, app.today);
      final last = o.permits.isEmpty ? null : o.permits.last;
      final p = cur ?? last;
      String sub;
      if (p == null) {
        sub = s.t('tasreeh.state.none');
      } else if (p.endDate == null) {
        sub = p.appliedDate == null ? s.t('tasreeh.noDates') : s.t('tasreeh.appliedOn', {'date': app.dateShort(p.appliedDate!)});
      } else {
        final left = toDay(p.endDate!) - toDay(app.today);
        sub = left >= 0
            ? '${s.t('tasreeh.endsOn', {'date': app.dateShort(p.endDate!)})} · ${s.t('tasreeh.daysLeft', {'count': left})}'
            : s.t('tasreeh.endedOn', {'date': app.dateShort(p.endDate!)});
      }
      cards.add(_Fact(
        accent: stageColor('tasreeh'),
        label: s.t('tasreeh.title'),
        value: p?.number ?? (p == null ? s.t('tasreeh.add') : '—'),
        sub: sub,
        onTap: o.deleted ? null : () => showPermitDialog(context, o, p == null ? null : o.permits.indexOf(p)),
      ));
    }
    if (pkgs.contains('civil')) {
      final runs = o.cableRuns;
      final total = runs.fold<double>(0, (n, r) => n + (r.lengthM ?? 0));
      final missing = runs.where((r) => r.lengthM == null).length;
      cards.add(_Fact(
        accent: stageColor('civil'),
        label: s.t('order.cableRuns'),
        value: runs.isEmpty ? '—' : runs.map((r) => '${r.voltage} ${r.sizeMm2}').toSet().join(', '),
        sub: runs.isEmpty
            ? s.t('order.addCable')
            : missing == runs.length
                ? s.t('order.lengthNotEntered')
                : [s.t('common.metres', {'value': _num(total)}), if (missing > 0) s.t('order.someLengthsMissing', {'count': missing})].join(' · '),
        onTap: o.deleted ? null : () => editOrder(context, o),
      ));
    }
    if (pkgs.contains('restoration')) {
      cards.add(_Fact(
        accent: stageColor('restoration'),
        label: s.t('order.segments'),
        value: o.segments.isEmpty ? '—' : o.segments.map((g) => s.t('order.base.${g.base}')).toSet().join(', '),
        sub: o.segments.isEmpty
            ? s.t('order.addSegment')
            : o.segments.map((g) => '${_num(g.lengthM)} × ${g.base == 'asphalt' ? '${g.width}' : '—'}').join(' · '),
        onTap: o.deleted ? null : () => editOrder(context, o),
      ));
    }
    cards.add(_Fact(
      accent: stageColor('closeout'),
      label: s.t('order.progressTitle'),
      value: s.t('order.progress', {'closed': ev.closed, 'total': ev.total}),
      sub: ev.stage == null ? s.status(ev.status) : s.stage(ev.stage!),
      child: ProgressLine(ev.closed, ev.total, showText: false),
    ));
    return LayoutBuilder(builder: (context, c) {
      final per = c.maxWidth >= 760 ? 4 : (c.maxWidth >= 480 ? 2 : 1);
      final w = (c.maxWidth - (per - 1) * 12) / per;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final card in cards) SizedBox(width: w, child: card)]);
    });
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.sub, this.onTap, this.child, this.accent = C.faint});
  final String label, value;
  final Color accent;
  final String? sub;
  final VoidCallback? onTap;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, margin: const EdgeInsetsDirectional.only(end: 6), decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w500))),
              ]),
              const SizedBox(height: 4),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (sub != null) ...[const SizedBox(height: 2), Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: C.muted))],
              if (child != null) ...[const SizedBox(height: 8), child!],
            ]),
          ),
        ),
      );
}

/// A group of steps. A group whose steps are all done starts folded to one line, so
/// the steps still to do are what fills the screen; tap it to see the dates.
class _StepGroup extends StatefulWidget {
  _StepGroup({required this.title, required this.order, required this.steps, this.color = C.accent}) : super(key: ValueKey('${order.id}|$title'));
  final String title;
  final Color color;
  final OrderInput order;
  final List<StepState> steps;
  @override
  State<_StepGroup> createState() => _StepGroupState();
}

class _StepGroupState extends State<_StepGroup> {
  late bool _open = !widget.steps.every((x) => x.closed);

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final closed = steps.where((x) => x.closed).length;
    final allDone = closed == steps.length;
    final count = Mono(context.t('order.progress', {'closed': closed, 'total': steps.length}), size: 12, color: allDone ? C.success : C.faint);
    final head = InkWell(
      onTap: allDone ? () => setState(() => _open = !_open) : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 10, (_open || !allDone) ? 2 : 10),
        child: Row(children: [
          if (allDone) ...[const Icon(Icons.check_circle, size: 18, color: C.success), const SizedBox(width: 8)],
          Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14))),
          const SizedBox(width: 8),
          count,
          if (allDone) Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: C.faint),
        ]),
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: allDone ? C.success : widget.color, width: 4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        head,
        if (_open || !allDone)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 4),
            child: Column(children: [for (final st in steps) _StepRow(order: widget.order, st: st)]),
          ),
      ]),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.order, required this.st});
  final OrderInput order;
  final StepState st;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final name = s.step(st.step.key);
    final note = order.steps[st.id]?.note;
    final editable = !order.deleted && order.state != 'cancelled' && order.state != 'merged';
    Widget icon;
    String? sub;
    Color color = C.ink;
    switch (st.state) {
      case 'done':
        icon = const _Tick(done: true);
        sub = app.dateShort(st.doneDate!);
      case 'na':
        icon = const Icon(Icons.remove_circle_outline, size: 22, color: C.locked);
        sub = '${s.t('common.notApplicable')} · ${st.naReason ?? ''}';
        color = C.muted;
      case 'ready':
        icon = const _Tick(done: false);
      default:
        icon = const Icon(Icons.lock_outline, size: 20, color: C.locked);
        sub = st.reasons.map(s.reason).join(' · ');
        color = C.faint;
    }
    final ready = st.state == 'ready' && editable;
    // A done step shows its date on the same line, so each finished step takes one short row.
    final inline = st.state == 'done';
    return Container(
      decoration: BoxDecoration(color: ready ? C.accentSoft : null, border: const Border(bottom: BorderSide(color: C.lineSoft))),
      padding: EdgeInsets.symmetric(vertical: ready ? 5 : 4, horizontal: ready ? 6 : 0),
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 28, child: Center(child: icon)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: TextStyle(color: color, fontWeight: ready ? FontWeight.w600 : FontWeight.w400, fontSize: 14)),
                if (inline && sub != null) TextSpan(text: '   $sub', style: const TextStyle(fontSize: 12, color: C.faint)),
              ]),
            ),
            if (!inline && sub != null && sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 12, color: C.faint)),
            if (note != null && note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const Icon(Icons.sticky_note_2_outlined, size: 13, color: C.muted),
                  const SizedBox(width: 4),
                  Flexible(child: Text(note, style: const TextStyle(fontSize: 12, color: C.muted))),
                ]),
              ),
            PhotoStrip(order: order, stepKey: st.id, canEdit: editable),
          ]),
        ),
        if (ready) ...[
          if (!isPhone(context))
            TextButton(onPressed: app.saving ? null : () => _markOther(context), child: Text(s.t('common.otherDate'))),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            onPressed: app.saving ? null : () => _mark(context, app.today),
            child: Text(s.t('common.markDoneToday')),
          ),
        ],
        if (editable && !isPhone(context))
          IconButton(
            tooltip: s.t('step.addPhoto'),
            visualDensity: VisualDensity.compact,
            onPressed: () => addPhotosToStep(context, order, st.id, name),
            icon: const Icon(Icons.add_a_photo_outlined, size: 20, color: C.faint),
          ),
        if (editable)
          PopupMenuButton<String>(
            tooltip: s.t('order.stepMenu'),
            icon: const Icon(Icons.more_vert, size: 20, color: C.faint),
            onSelected: (v) {
              switch (v) {
                case 'other':
                  _markOther(context);
                case 'na':
                  _markNA(context);
                case 'clear':
                  _clear(context);
                case 'note':
                  _note(context);
                case 'photo':
                  addPhotosToStep(context, order, st.id, name);
              }
            },
            itemBuilder: (_) => [
              if (st.state != 'done' && st.state != 'na') PopupMenuItem(value: 'other', child: Text(s.t('step.markOnDate'))),
              if (st.state != 'done' && st.state != 'na') PopupMenuItem(value: 'na', child: Text(s.t('action.markNA'))),
              if (st.closed) PopupMenuItem(value: 'clear', child: Text(s.t('action.clearStep'))),
              PopupMenuItem(value: 'note', child: Text(s.t(note == null ? 'step.addNote' : 'step.editNote'))),
              PopupMenuItem(value: 'photo', child: Text(s.t('step.addPhoto'))),
            ],
          ),
      ]),
    );
  }

  Future<void> _mark(BuildContext context, String date) async {
    final app = context.appRead;
    final o = app.orderById(order.id) ?? order;
    await app.apply(o, app.actions.markDone(o, st.id, date, app.today), toast: 'toast.stepDone', toastParams: {'step': app.s.step(st.step.key)});
  }

  Future<void> _markOther(BuildContext context) async {
    final app = context.appRead;
    final deps = st.step.deps.map((d) => order.steps[d]?.done).whereType<String>().toList()..sort();
    // Not before the order was received, nor before the step it waits for was done.
    final first = [if (deps.isNotEmpty) deps.last, if (order.receivedDate != null) order.receivedDate!].fold<String?>(null, (m, x) => m == null || x.compareTo(m) > 0 ? x : m);
    // When that is today, no other day can be chosen: say why instead of showing a calendar
    // with every day greyed out.
    if (first != null && first.compareTo(app.today) >= 0) {
      app.showToast(app.s.t('step.onlyToday', {'date': app.dateShort(first)}));
      return;
    }
    final d = await pickDate(context, first: first, help: app.s.step(st.step.key));
    if (d == null || !context.mounted) return;
    await _mark(context, d);
  }

  Future<void> _markNA(BuildContext context) async {
    final app = context.appRead;
    final reason = await reasonDialog(context,
        title: app.s.t('step.naTitle', {'step': app.s.step(st.step.key)}), body: app.s.t('step.naBody'), confirm: app.s.t('action.markNA'));
    if (reason == null || !context.mounted) return;
    final o = app.orderById(order.id) ?? order;
    await app.apply(o, app.actions.markNA(o, st.id, reason, app.today), toast: 'toast.stepNA', toastParams: {'step': app.s.step(st.step.key)});
  }

  Future<void> _clear(BuildContext context) async {
    final app = context.appRead;
    final o = app.orderById(order.id) ?? order;
    final p = app.actions.clearPreview(o, st.id);
    if (!p.ok) {
      app.showToast(p.errors.map(app.s.error).join(' '), error: true);
      return;
    }
    if (p.alsoClears.isNotEmpty) {
      final names = p.alsoClears.map((id) => app.s.step(id.split('@').first)).toSet().toList();
      final ok = await confirmDialog(
        context,
        title: app.s.t('confirm.clearTitle', {'step': app.s.step(st.step.key)}),
        body: app.s.t('confirm.clearStep', {'step': app.s.step(st.step.key), 'count': p.alsoClears.length, 'steps': names}),
        confirm: app.s.t('action.clearStep'),
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    await app.apply(o, app.actions.clearStep(o, st.id), toast: 'toast.stepCleared', toastParams: {'step': app.s.step(st.step.key)});
  }

  Future<void> _note(BuildContext context) async {
    final app = context.appRead;
    final o = app.orderById(order.id) ?? order;
    final cur = o.steps[st.id];
    final text = await showDialog<String>(
      context: context,
      builder: (c) => _NoteDialog(title: app.s.step(st.step.key), initial: cur?.note ?? ''),
    );
    if (text == null || !context.mounted) return;
    final trimmed = text.trim();
    final rec = StepRecord(done: cur?.done, na: cur?.na ?? false, reason: cur?.reason, note: trimmed.isEmpty ? null : trimmed);
    final steps = Map<String, StepRecord>.from(o.steps);
    if (!rec.closed && rec.note == null) {
      steps.remove(st.id);
    } else {
      steps[st.id] = rec;
    }
    await app.save([OrderChange(o, o.copyWith(steps: steps))], toast: 'toast.saved');
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: done ? C.success : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: done ? C.success : C.accent, width: 2),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: done ? const Icon(Icons.check, key: ValueKey('t'), size: 14, color: Colors.white) : const SizedBox(key: ValueKey('o')),
        ),
      );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _ctl = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 420,
          child: TextField(controller: _ctl, autofocus: true, minLines: 2, maxLines: 6, decoration: InputDecoration(labelText: context.t('common.note'))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, _ctl.text), child: Text(context.t('common.save'))),
        ],
      );
}

class _Notes extends StatelessWidget {
  const _Notes({required this.order});
  final OrderInput order;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final note = order.notes;
    return SectionCard(
      title: s.t('order.notes'),
      trailing: order.deleted
          ? null
          : TextButton(
              onPressed: () async {
                final app = context.appRead;
                final text = await showDialog<String>(context: context, builder: (c) => _NoteDialog(title: s.t('order.notes'), initial: note ?? ''));
                if (text == null || !context.mounted) return;
                final o = app.orderById(order.id) ?? order;
                await app.save([OrderChange(o, o.copyWith(notes: text.trim().isEmpty ? null : text.trim()))], toast: 'toast.saved');
              },
              child: Text(s.t(note == null ? 'common.add' : 'common.edit')),
            ),
      child: Text(note ?? s.t('order.noNotes'), style: TextStyle(color: note == null ? C.faint : C.ink, height: 1.45)),
    );
  }
}
