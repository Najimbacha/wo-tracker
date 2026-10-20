// Tasreeh (work permit), typed by hand: applied first, then number and dates once
// Baladiya approves. A long project can have several in a row.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../domain/order_input.dart';
import '../../domain/rules_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// [index] is the tasreeh to change, or null to add one.
Future<void> showPermitDialog(BuildContext context, OrderInput order, int? index) =>
    showDialog<void>(context: context, builder: (_) => _PermitDialog(order: order, index: index));

class _PermitDialog extends StatefulWidget {
  const _PermitDialog({required this.order, this.index});
  final OrderInput order;
  final int? index;
  @override
  State<_PermitDialog> createState() => _PermitDialogState();
}

class _PermitDialogState extends State<_PermitDialog> {
  static String _plus(String ymd, int days) => fromDay(toDay(ymd) + days);

  late final Permit? _old = widget.index == null ? null : widget.order.permits[widget.index!];
  late final _number = TextEditingController(text: _old?.number ?? '');
  late String? _applied = _old?.appliedDate ?? (widget.index == null ? context.appRead.today : null);
  late String? _start = _old?.startDate;
  late String? _end = _old?.endDate;
  List<String> _errors = [];
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _number.text.trim() != (_old?.number ?? '') || _applied != _old?.appliedDate || _start != _old?.startDate || _end != _old?.endDate;

  Future<void> _save() async {
    final app = context.appRead;
    final o = app.orderById(widget.order.id) ?? widget.order;
    final r = app.actions.savePermit(
      o,
      widget.index,
      Permit(number: _number.text, appliedDate: _applied, startDate: _start, endDate: _end),
      app.data.orders.where((x) => x.id != o.id).toList(),
      app.today,
    );
    if (!r.ok) {
      setState(() => _errors = r.errors.map(app.s.error).toList());
      return;
    }
    setState(() => _saving = true);
    final ok = await app.apply(o, r, toast: r.markedApplied ? 'toast.tasreehApplied' : 'toast.tasreehSaved');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final app = context.appRead;
    final ok = await confirmDialog(context,
        title: app.s.t('tasreeh.removeTitle', {'number': _old?.number ?? ''}), body: app.s.t('tasreeh.removeBody'), confirm: app.s.t('common.delete'), danger: true);
    if (!ok || !mounted) return;
    final o = app.orderById(widget.order.id) ?? widget.order;
    final done = await app.apply(o, app.actions.removePermit(o, widget.index!), toast: 'toast.tasreehRemoved');
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final o = widget.order;
    String? info;
    if (_start != null && _end != null && toDay(_end!) >= toDay(_start!)) {
      final valid = toDay(_end!) - toDay(_start!) + 1;
      info = s.t('tasreeh.validDays', {'count': valid});
      if (toDay(_start!) > toDay(app.today)) {
        info = '$info · ${s.t('tasreeh.willShowSoon', {'date': app.dateShort(fromDay(toDay(_start!) + 1))})}';
      }
    }
    return UnsavedGuard(
      dirty: _dirty,
      child: AlertDialog(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s.t('order.woNumber')} ${o.woNumber ?? ''} · ${o.type}', style: TextStyle(fontSize: 12, color: C.faint)),
          const SizedBox(height: 4),
          Text(widget.index == null ? s.t('tasreeh.add') : s.t('tasreeh.title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              DateField(label: s.t('tasreeh.applied'), value: _applied, first: o.receivedDate, optional: true, onChanged: (v) => setState(() => _applied = v)),
              const SizedBox(height: 14),
              TextField(
                controller: _number,
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: s.t('tasreeh.number'), helperText: s.t('tasreeh.numberHint')),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: DateField(label: s.t('tasreeh.start'), value: _start, allowFuture: true, suggest: _plus(app.today, 5), quick: [(s.t('common.today'), app.today), for (final n in const [5, 7]) (s.t('date.afterDays', {'count': n}), _plus(app.today, n))], optional: true, first: _applied, onChanged: (v) => setState(() => _start = v))),
                const SizedBox(width: 12),
                Expanded(child: DateField(label: s.t('tasreeh.end'), value: _end, allowFuture: true, suggest: _plus(_start ?? app.today, 15), quick: [for (final n in const [15, 30]) (s.t('date.afterDays', {'count': n}), _plus(_start ?? app.today, n))], optional: true, first: _start, onChanged: (v) => setState(() => _end = v))),
              ]),
              if (info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(info, style: TextStyle(color: C.muted, fontSize: 13))),
              if (o.permits.length > 1 || (widget.index == null && o.permits.isNotEmpty)) ...[
                const SizedBox(height: 16),
                Text(s.t('tasreeh.others'), style: TextStyle(fontSize: 12, color: C.faint)),
                for (var i = 0; i < o.permits.length; i++)
                  if (i != widget.index)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Mono(o.permits[i].number ?? '—', size: 12.5),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            [o.permits[i].startDate, o.permits[i].endDate].whereType<String>().map(app.dateShort).join(' – '),
                            style: TextStyle(color: C.muted, fontSize: 12.5),
                          ),
                        ),
                      ]),
                    ),
              ],
              for (final e in _errors) Padding(padding: const EdgeInsets.only(top: 8), child: Text(e, style: TextStyle(color: C.critical))),
            ]),
          ),
        ),
        actions: [
          if (widget.index != null) TextButton(onPressed: _saving ? null : _remove, child: Text(s.t('common.delete'), style: TextStyle(color: C.critical))),
          TextButton(onPressed: () => Navigator.maybePop(context), child: Text(s.t('common.cancel'))),
          FilledButton(onPressed: _saving ? null : _save, child: Text(s.t('tasreeh.save'))),
        ],
      ),
    );
  }
}
