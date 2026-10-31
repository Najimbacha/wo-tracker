// Plan: the work that can be done right now, grouped so a day's jobs can be done in one trip.
//
// The question this screen answers is "what do I do next, and can I do several at once?".
// Each order that has a step ready to start appears once, under its district, with the step it
// is ready for. Pick a step to batch by kind of work (all Kashfeya visits), and read the
// districts to plan one trip. An abstract count of orders per step told nobody anything.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../domain/order_input.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// One order and the steps it is ready to start, with the longest wait on any of them.
class _Ready {
  const _Ready(this.order, this.steps, this.days);
  final OrderInput order;
  final List<String> steps;
  final int days;
}

class PipelineScreen extends StatefulWidget {
  const PipelineScreen({super.key});
  @override
  State<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends State<PipelineScreen> {
  String? _step; // null = every kind of work

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (!app.data.loaded) return const DelayedLoader();

    // Every order that can be started now, with the steps open to it.
    final rows = <_Ready>[];
    for (final x in app.evaluated) {
      if (x.ev.status != 'open' && x.ev.status != 'on_hold') continue;
      final keys = <String>[];
      var days = 0;
      for (final st in x.ev.steps) {
        if (st.state != 'ready') continue;
        if (!keys.contains(st.step.key)) keys.add(st.step.key);
        final d = app.insights.daysWaiting(x.order, x.ev, st.id, app.today);
        if (d > days) days = d;
      }
      if (keys.isNotEmpty) rows.add(_Ready(x.order, keys, days));
    }

    // How many orders each kind of work would cover: the size of each batch.
    final counts = <String, int>{};
    for (final r in rows) {
      for (final k in r.steps) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final stepKeys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    final shown = _step == null ? rows : rows.where((r) => r.steps.contains(_step)).toList();

    // Grouped by district: everything in one group can be done on one visit.
    final groups = <String, List<_Ready>>{};
    for (final r in shown) {
      final d = (r.order.district ?? '').trim();
      groups.putIfAbsent(d.isEmpty ? s.t('plan.noDistrict') : d, () => []).add(r);
    }
    final groupNames = groups.keys.toList()
      ..sort((a, b) {
        final byCount = groups[b]!.length.compareTo(groups[a]!.length);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    for (final g in groups.values) {
      g.sort((a, b) => b.days.compareTo(a.days)); // longest waiting first
    }

    final hold = app.evaluated.where((x) => x.ev.status == 'on_hold').length;
    final phone = isPhone(context);

    return ListView(padding: EdgeInsets.all(phone ? 12 : 16), children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 2, children: [
        Text(s.t('pipeline.title'), style: Theme.of(context).textTheme.titleLarge),
        Text(
          hold > 0
              ? '${s.t('pipeline.subtitle', {'count': rows.length})} · ${s.t('pipeline.subtitleHold', {'count': hold})}'
              : s.t('pipeline.subtitle', {'count': rows.length}),
          style: TextStyle(color: C.muted, fontSize: 13),
        ),
      ]),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        EmptyState(icon: Icons.check_circle_outline, title: s.t('plan.emptyTitle'), body: s.t('plan.emptyBody'))
      else ...[
        // One chip per kind of work, biggest batch first. Tapping narrows the list below.
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            selected: _step == null,
            onSelected: (_) => setState(() => _step = null),
            label: Text('${s.t('plan.all')} · ${rows.length}'),
          ),
          for (final k in stepKeys)
            ChoiceChip(
              selected: _step == k,
              onSelected: (_) => setState(() => _step = _step == k ? null : k),
              label: Text('${s.step(k)} · ${counts[k]}'),
            ),
        ]),
        const SizedBox(height: 8),
        Text(s.t('plan.hint'), style: TextStyle(color: C.faint, fontSize: 12)),
        const SizedBox(height: 10),
        for (final name in groupNames) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(Icons.place_outlined, size: 16, color: C.faint),
              const SizedBox(width: 6),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
              Mono('${groups[name]!.length}', size: 12.5, color: C.muted),
            ]),
          ),
          for (final r in groups[name]!)
            OrderTile(
              order: r.order,
              dense: true,
              subtitle: [
                if (_step == null) ...r.steps.map(s.step),
                if ((r.order.contractor ?? '').trim().isNotEmpty) r.order.contractor!.trim(),
              ].join(' · '),
              trailing: Mono(s.t('common.daysShort', {'count': r.days}), size: 11.5, color: r.days >= 14 ? C.critical : C.faint),
              onTap: () => openOrder(context, r.order.id),
            ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 60),
      ],
    ]);
  }
}
