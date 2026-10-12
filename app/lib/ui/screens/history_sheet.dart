// Every change ever made to an order, from the server's append-only history.
// Needs internet; the order itself always works offline.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../data/ids.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../domain/order_input.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showHistorySheet(BuildContext context, OrderInput order) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _History(order: order)),
    );

class _History extends StatefulWidget {
  const _History({required this.order});
  final OrderInput order;
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  late Future<List<HistoryEntry>> _future = context.appRead.repo.history(widget.order);

  /// Row id → what that row is ("Excavation", "Asphalt · 40 cm", "Tasreeh P-1").
  Map<String, String> _labels(BuildContext context) {
    final app = context.appRead;
    final s = app.s;
    final o = widget.order;
    final out = <String, String>{o.id!: s.t('history.order')};
    for (final st in app.engine.generate(o)) {
      final seg = st.scope == 'segment' ? st.instance : null;
      final meter = st.scope == 'meter' ? st.instance : null;
      out[StepIds.stepRowId(o.id!, st.key, segmentId: seg, meterId: meter)] = s.step(st.key);
    }
    for (final p in o.permits) {
      if (p.id != null) out[p.id!] = '${s.t('tasreeh.title')} ${p.number ?? ''}';
    }
    for (final g in o.segments) {
      out[g.id] = '${s.t('order.base.${g.base}')} · ${g.width} cm';
    }
    for (var i = 0; i < o.meters.length; i++) {
      out[o.meters[i].id] = s.t('order.meterOf', {'index': i + 1, 'total': o.meters.length});
    }
    for (final c in o.cableRuns) {
      if (c.id != null) out[c.id!] = '${s.t('order.cableRuns')} ${c.voltage} ${c.sizeMm2}';
    }
    for (final h in o.holdPeriods) {
      if (h.id != null) out[h.id!] = s.t('hold.onHold');
    }
    return out;
  }

  String _describe(BuildContext context, HistoryEntry e, Map<String, String> labels) {
    final s = context.s;
    final what = labels[e.rowId] ?? s.t('history.table.${e.table}');
    if (e.action == 'insert') return s.t('history.added', {'what': what});
    if (e.action == 'soft_delete') return s.t('history.deleted', {'what': what});
    if (e.action == 'restore') return s.t('history.restored', {'what': what});
    if (e.table == 'steps') {
      final n = e.newData;
      if (n['done_date'] != null) return s.t('history.stepDone', {'step': what, 'date': '${n['done_date']}'});
      if (n['not_applicable'] == true) return s.t('history.stepNA', {'step': what, 'reason': '${n['na_reason'] ?? ''}'});
      if (n.containsKey('done_date') || n.containsKey('not_applicable')) return s.t('history.stepCleared', {'step': what});
      if (n.containsKey('note')) return s.t('history.noteChanged', {'what': what});
    }
    String field(String k) {
      final label = s.t('history.field.$k');
      return label == 'history.field.$k' ? k.replaceAll('_', ' ') : label;
    }
    final fields = e.newData.keys.map(field).join(', ');
    return s.t('history.changed', {'what': what, 'fields': fields});
  }

  String _values(HistoryEntry e) {
    if (e.action != 'update') return '';
    final parts = <String>[];
    for (final k in e.newData.keys) {
      final a = e.oldData[k], b = e.newData[k];
      if (a is Map || b is Map) continue;
      parts.add('${a ?? '—'} → ${b ?? '—'}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('history.title', {'wo': widget.order.woNumber ?? ''}), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(s.t('history.note'), style: const TextStyle(color: C.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<HistoryEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const DelayedLoader();
              if (snap.hasError) {
                final e = snap.error;
                final key = e is RepoException ? e.key : 'history.offline';
                return EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: s.t(key),
                  action: OutlinedButton(onPressed: () => setState(() => _future = app.repo.history(widget.order)), child: Text(s.t('common.retry'))),
                );
              }
              final items = snap.data!;
              if (items.isEmpty) return EmptyState(icon: Icons.history, title: s.t('history.empty'));
              final labels = _labels(context);
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) {
                  final e = items[i];
                  final when = '${app.dateShort(e.at.toIso8601String().substring(0, 10))}, ${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}';
                  final values = _values(e);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(width: 9, height: 9, decoration: BoxDecoration(color: i == 0 ? C.accent : C.locked, shape: BoxShape.circle)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_describe(context, e, labels)),
                          Text([when, if (values.isNotEmpty) values].join(' · '), style: const TextStyle(fontSize: 12, color: C.faint)),
                        ]),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
