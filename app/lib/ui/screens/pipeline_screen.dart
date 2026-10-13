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

    final segRecipes = (app.rules['segmentRecipes'] as Map).cast<String, dynamic>();
    final sections = <Widget>[
      _Section(title: s.t('pipeline.section.paperwork'), children: [
        stepRow('kashfeya'),
        bucket('tasreehNotApplied', FilterCriteria(status: active, steps: const [StepCondition('tasreeh_applied', 'not_done')])),
        bucket('appliedNoDates', FilterCriteria(status: active, tasreeh: const ['none'], steps: const [StepCondition('tasreeh_applied', 'done')])),
        bucket('startsInFuture', FilterCriteria(status: active, tasreeh: const ['future'])),
        bucket('expiredWorkOpen', const FilterCriteria(quick: ['expired'])),
      ]),
      _Section(title: s.t('pipeline.section.civil'), children: [
        for (final k in const ['excavation', 'cable_installed', 'warning_tape', 'poles', 'stringing', 'stay_earthing', 'line_energized']) stepRow(k),
        bucket('lateStart', const FilterCriteria(quick: ['late_start'])),
      ]),
      _Section(title: s.t('pipeline.section.restoration'), children: [
        for (final entry in segRecipes.entries) ...[
          _SubHead(s.t('pipeline.recipe.${entry.key}')),
          for (final k in (entry.value as List).cast<String>()) stepRow(k),
        ],
        _SubHead(s.t('pipeline.recipe.tiles')),
        stepRow(app.rules['tiledStep'] as String),
        _SubHead(s.t('pipeline.recipe.transformer')),
        for (final k in const ['foundation', 'transformer_installed', 'earthing', 'transformer_energized']) stepRow(k),
      ]),
      _Section(title: s.t('pipeline.section.meter'), children: [
        for (final k in const ['meter_installed', 'breaker_meter_changed', 'meter_relocated', 'meter_on', 'form_190', 'form_200', 'certificate', 'documents_submitted']) stepRow(k),
      ]),
    ];

    return ListView(padding: EdgeInsets.all(phone ? 12 : 16), children: [
      Text(s.t('pipeline.title'), style: Theme.of(context).textTheme.titleLarge),
      Text(s.t('pipeline.subtitle', {'count': p.activeCount}), style: const TextStyle(color: C.muted, fontSize: 13)),
      const SizedBox(height: 10),
      SectionCard(
        title: s.t('pipeline.startsNext7', {'count': startTotal}),
        trailing: Text(s.t('pipeline.startsNote'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.faint, fontSize: 12)),
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
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Text(s.t('pipeline.noStarts'), style: const TextStyle(color: C.faint)))
          else
            for (final id in day.orders)
              if (app.orderById(id) != null) OrderTile(order: app.orderById(id)!, dense: true, onTap: () => openOrder(context, id)),
        ]),
      ),
      const SizedBox(height: 14),
      Text(s.t('pipeline.notDoneTitle'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      Text(s.t('pipeline.notDoneNote'), style: const TextStyle(color: C.faint, fontSize: 12.5)),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final per = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        final w = (c.maxWidth - (per - 1) * 14) / per;
        return Wrap(spacing: 14, runSpacing: 14, children: [for (final sec in sections) SizedBox(width: w, child: sec)]);
      }),
      const SizedBox(height: 10),
      Text(s.t('pipeline.footer'), style: const TextStyle(color: C.faint, fontSize: 12)),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SectionCard(
        title: title,
        trailing: Text('${context.t('pipeline.readyNow')} · ${context.t('pipeline.totalNotDone')}', style: const TextStyle(fontSize: 11.5, color: C.faint)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

class _SubHead extends StatelessWidget {
  const _SubHead(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text(text, style: const TextStyle(fontSize: 12, color: C.faint, fontWeight: FontWeight.w500)));
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, this.ready, required this.total, this.onReady, this.onTotal});
  final String label;
  final int? ready;
  final int total;
  final VoidCallback? onReady, onTotal;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          if (ready != null)
            SizedBox(
              width: 44,
              child: InkWell(onTap: ready == 0 ? null : onReady, child: Mono('$ready', size: 13.5, color: ready == 0 ? C.faint : C.accent)),
            ),
          SizedBox(width: 44, child: InkWell(onTap: total == 0 ? null : onTotal, child: Mono('$total', size: 13.5, color: total == 0 ? C.faint : C.ink))),
        ]),
      );
}
