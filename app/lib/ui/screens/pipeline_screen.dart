// Pipeline: how many open orders wait on each step, and what starts in the next 7 days.
// Every number opens those orders as a list (to bulk-update or export).
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../domain/insights.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});
  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> {
  int _day = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (!app.data.loaded) return const DelayedLoader();
    final p = app.memo('pipeline', () => app.insights.pipeline(app.orders, app.today, alertSettings: app.alertSettings));
    final starts = app.memo('startsByDay', () => app.insights.startsByDay(app.orders, app.today, alertSettings: app.alertSettings));
    final startTotal = starts.fold<int>(0, (n, d) => n + d.count);
    final phone = isPhone(context);
    final day = starts[_day.clamp(0, starts.length - 1)];

    void list(String title, FilterCriteria f) => app.showOrders(f, title: title);
    const active = ['open', 'on_hold'];

    Widget stepRow(String key) {
      final c = p.steps[key];
      if (c == null || c.total == 0) return const SizedBox.shrink();
      final name = s.step(key);
      return _CountRow(
        label: name,
        ready: c.ready,
        total: c.total,
        onReady: () => list('${s.t('pipeline.readyNow')}: $name', FilterCriteria(status: active, steps: [StepCondition(key, 'ready')])),
        onTotal: () => list('${s.t('filter.stepState.not_done')}: $name', FilterCriteria(status: active, steps: [StepCondition(key, 'not_done')])),
      );
    }

    Widget bucket(String key, FilterCriteria f) {
      final n = p.buckets[key] ?? 0;
      return _CountRow(label: s.t('pipeline.bucket.$key'), total: n, onTotal: n == 0 ? null : () => list(s.t('pipeline.bucket.$key'), f));
    }

    // The steps that can be done today, most orders first.
    final doNow = [for (final e in p.steps.entries) if (e.value.ready > 0) MapEntry(e.key, e.value.ready)]..sort((a, b) => b.value - a.value);

    final segRecipes = (app.rules['segmentRecipes'] as Map).cast<String, dynamic>();
    final sections = <Widget>[
      _Section(title: s.t('pipeline.section.paperwork'), color: stageColor('tasreeh'), max: p.activeCount, children: [
        stepRow('kashfeya'),
        bucket('tasreehNotApplied', FilterCriteria(status: active, steps: const [StepCondition('tasreeh_applied', 'not_done')])),
        bucket('appliedNoDates', FilterCriteria(status: active, tasreeh: const ['none'], steps: const [StepCondition('tasreeh_applied', 'done')])),
        bucket('startsInFuture', FilterCriteria(status: active, tasreeh: const ['future'])),
        bucket('expiredWorkOpen', const FilterCriteria(quick: ['expired'])),
      ]),
      _Section(title: s.t('pipeline.section.civil'), color: stageColor('civil'), max: p.activeCount, children: [
        for (final k in const ['excavation', 'cable_installed', 'warning_tape', 'poles', 'stringing', 'stay_earthing', 'line_energized']) stepRow(k),
        bucket('lateStart', const FilterCriteria(quick: ['late_start'])),
      ]),
      _Section(title: s.t('pipeline.section.restoration'), color: stageColor('restoration'), max: p.activeCount, children: [
        for (final entry in segRecipes.entries) ...[
          _SubHead(s.t('pipeline.recipe.${entry.key}')),
          for (final k in (entry.value as List).cast<String>()) stepRow(k),
        ],
        _SubHead(s.t('pipeline.recipe.tiles')),
        stepRow(app.rules['tiledStep'] as String),
        _SubHead(s.t('pipeline.recipe.transformer')),
        for (final k in const ['foundation', 'transformer_installed', 'earthing', 'transformer_energized']) stepRow(k),
      ]),
      _Section(title: s.t('pipeline.section.meter'), color: stageColor('meter'), max: p.activeCount, children: [
        for (final k in const ['meter_installed', 'breaker_meter_changed', 'meter_relocated', 'meter_on', 'form_190', 'form_200', 'certificate', 'documents_submitted']) stepRow(k),
      ]),
    ];

    return ListView(padding: EdgeInsets.all(phone ? 12 : 16), children: [
      Text(s.t('pipeline.title'), style: Theme.of(context).textTheme.titleLarge),
      Text(s.t('pipeline.subtitle', {'count': p.activeCount}), style: TextStyle(color: C.muted, fontSize: 13)),
      const SizedBox(height: 10),
      SectionCard(
        title: s.t('pipeline.doNow'),
        trailing: Text(s.t('pipeline.doNowNote'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.faint, fontSize: 12)),
        child: doNow.isEmpty
            ? Text(s.t('pipeline.doNowNone'), style: TextStyle(color: C.faint))
            : Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in doNow)
                  ActionChip(
                    backgroundColor: C.accentSoft,
                    side: BorderSide(color: C.accent, width: 0.8),
                    onPressed: () => list('${s.t('pipeline.readyNow')}: ${s.step(e.key)}', FilterCriteria(status: active, steps: [StepCondition(e.key, 'ready')])),
                    avatar: CircleAvatar(backgroundColor: C.accent, child: Text('${e.value}', style: TextStyle(color: C.onSolid, fontSize: 11.5, fontWeight: FontWeight.w600))),
                    label: Text(s.step(e.key), style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
              ]),
      ),
      const SizedBox(height: 10),
      SectionCard(
        title: s.t('pipeline.startsNext7', {'count': startTotal}),
        trailing: Text(s.t('pipeline.startsNote'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.faint, fontSize: 12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < starts.length; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    selected: i == _day,
                    onSelected: (_) => setState(() => _day = i),
                    label: Text('${i == 0 ? s.t('common.today') : '${s.weekday(starts[i].date).substring(0, app.lang == 'ar' ? s.weekday(starts[i].date).length : 3)} ${app.dateShort(starts[i].date)}'} · ${starts[i].count}'),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          if (day.orders.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Text(s.t('pipeline.noStarts'), style: TextStyle(color: C.faint)))
          else
            for (final id in day.orders)
              if (app.orderById(id) != null) OrderTile(order: app.orderById(id)!, dense: true, onTap: () => openOrder(context, id)),
        ]),
      ),
      const SizedBox(height: 14),
      Text(s.t('pipeline.notDoneTitle'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      Text(s.t('pipeline.notDoneNote'), style: TextStyle(color: C.faint, fontSize: 12.5)),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final per = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        final w = (c.maxWidth - (per - 1) * 14) / per;
        return Wrap(spacing: 14, runSpacing: 14, children: [for (final sec in sections) SizedBox(width: w, child: sec)]);
      }),
      const SizedBox(height: 10),
      Text(s.t('pipeline.footer'), style: TextStyle(color: C.faint, fontSize: 12)),
    ]);
  }
}

/// Gives the rows inside a section their colour and the number the bars are measured against.
class _RowStyle extends InheritedWidget {
  const _RowStyle({required this.color, required this.max, required super.child});
  final Color color;
  final int max;
  static _RowStyle? of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_RowStyle>();
  @override
  bool updateShouldNotify(_RowStyle o) => o.color != color || o.max != max;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, required this.color, required this.max});
  final String title;
  final List<Widget> children;
  final Color color;
  final int max;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: color, width: 4))),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _RowStyle(
            color: color,
            max: max,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: color)),
              const SizedBox(height: 6),
              // Column heads: blue number = can be done today, grey = every open order not done yet.
              Row(children: [
                const Expanded(child: SizedBox()),
                SizedBox(width: 56, child: Text(context.t('pipeline.readyNow'), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.accent, fontWeight: FontWeight.w600))),
                SizedBox(width: 56, child: Text(context.t('pipeline.totalNotDone'), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.faint))),
              ]),
              ...children,
            ]),
          ),
        ),
      );
}

class _SubHead extends StatelessWidget {
  const _SubHead(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text(text, style: TextStyle(fontSize: 12, color: C.faint, fontWeight: FontWeight.w500)));
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, this.ready, required this.total, this.onReady, this.onTotal});
  final String label;
  final int? ready;
  final int total;
  final VoidCallback? onReady, onTotal;
  @override
  Widget build(BuildContext context) {
    final st = _RowStyle.of(context);
    final frac = st == null || st.max <= 0 ? 0.0 : (total / st.max).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))),
      child: Stack(children: [
        // The bar behind the row shows how many of the open orders are still at this step.
        if (st != null)
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: frac == 0 ? 0.0001 : frac,
              child: ColoredBox(color: st.color.withAlpha(22)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
            if (ready != null)
              SizedBox(
                width: 56,
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: ready == 0 ? null : onReady,
                    child: ready == 0
                        ? Mono('0', size: 13.5, color: C.faint)
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
                            decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(999)),
                            child: Mono('$ready', size: 13, color: C.onSolid, weight: FontWeight.w600),
                          ),
                  ),
                ),
              )
            else
              const SizedBox(width: 56),
            SizedBox(width: 56, child: Center(child: InkWell(onTap: total == 0 ? null : onTotal, child: Mono('$total', size: 13.5, color: total == 0 ? C.faint : C.ink)))),
          ]),
        ),
      ]),
    );
  }
}
