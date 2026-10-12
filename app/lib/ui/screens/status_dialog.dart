// Put on hold / Cancelled / Merged (replaced by another work order). All three need
// a reason; nothing is lost: Reopen and Resume bring the order back.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../domain/order_input.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

Future<void> showStatusDialog(BuildContext context, OrderInput order) =>
    showDialog<void>(context: context, builder: (_) => _StatusDialog(order: order));

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.order});
  final OrderInput order;
  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  String _kind = 'hold'; // hold | cancel | merge
  final _reason = TextEditingController();
  late String _from = context.appRead.today;
  String? _review;
  OrderInput? _target;
  bool _carry = true;
  final _search = TextEditingController();
  List<String> _errors = [];
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  List<String> _reasons(BuildContext context) => switch (_kind) {
        'hold' => [for (final k in const ['customer', 'material', 'baladiya', 'road']) context.t('hold.reason.$k')],
        'cancel' => [context.t('cancel.reason.sec'), context.t('cancel.reason.customer')],
        _ => [context.t('merge.reason.newWo')],
      };

  Future<void> _submit() async {
    final app = context.appRead;
    final o = app.orderById(widget.order.id) ?? widget.order;
    final reason = _reason.text.trim();
    final r = switch (_kind) {
      'hold' => app.actions.putOnHold(o, _from, reason, app.today, reviewDate: _review),
      'cancel' => app.actions.cancel(o, reason, app.today),
      _ => app.actions.merge(o, _target, reason, _carry, app.today),
    };
    if (!r.ok) {
      setState(() => _errors = r.errors.map(app.s.error).toList());
      return;
    }
    setState(() => _saving = true);
    final ok = await app.apply(o, r,
        toast: switch (_kind) { 'hold' => 'toast.onHold', 'cancel' => 'toast.cancelled', _ => 'toast.merged' },
        toastParams: {'date': app.dateShort(_from), 'wo': _target?.woNumber ?? ''},
        toastExtra: _kind == 'merge' && r.carried.isNotEmpty ? app.s.t('toast.carried', {'count': r.carried.length, 'wo': _target?.woNumber ?? ''}) : null);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final o = widget.order;
    final candidates = _kind != 'merge' || _search.text.trim().isEmpty
        ? const <OrderInput>[]
        : app.orders
            .where((x) => x.id != o.id && (x.state == 'open' || x.state == 'on_hold') && (x.woNumber ?? '').contains(_search.text.trim()))
            .take(6)
            .toList();
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${s.t('order.woNumber')} ${o.woNumber ?? ''} · ${o.type}${o.district == null ? '' : ' · ${o.district}'}',
            style: const TextStyle(fontSize: 12, color: C.faint)),
        const SizedBox(height: 4),
        Text(s.t('hold.title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'hold', label: Text(s.t('hold.onHold')), icon: const Icon(Icons.pause, size: 16)),
                ButtonSegment(value: 'cancel', label: Text(s.t('hold.cancelled')), icon: const Icon(Icons.block, size: 16)),
                ButtonSegment(value: 'merge', label: Text(s.t('hold.merged')), icon: const Icon(Icons.call_merge, size: 16)),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() {
                _kind = v.first;
                _errors = [];
              }),
            ),
            const SizedBox(height: 6),
            Text(s.t('hold.hint.$_kind'), style: const TextStyle(fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in _reasons(context))
                ChoiceChip(
                  label: Text(r),
                  selected: _reason.text == r,
                  onSelected: (_) => setState(() => _reason.text = r),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _reason, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: s.t('common.reason'))),
            const SizedBox(height: 14),
            if (_kind == 'hold')
              Row(children: [
                Expanded(child: DateField(label: s.t('hold.from'), value: _from, first: o.receivedDate, onChanged: (v) => setState(() => _from = v ?? app.today))),
                const SizedBox(width: 12),
                Expanded(
                  child: DateField(
                      label: s.t('hold.reviewOptional'), value: _review, first: _from, allowFuture: true, optional: true, onChanged: (v) => setState(() => _review = v)),
                ),
              ]),
            if (_kind == 'merge') ...[
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t('hold.mergedInto'), prefixIcon: const Icon(Icons.search, size: 18)),
              ),
              if (_target != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: C.success, size: 18),
                    const SizedBox(width: 6),
                    Mono(_target!.woNumber ?? ''),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_target!.district ?? '', style: const TextStyle(color: C.muted))),
                  ]),
                ),
              for (final c in candidates)
                ListTile(
                  dense: true,
                  title: Mono(c.woNumber ?? ''),
                  subtitle: Text([c.type, c.district].whereType<String>().join(' · ')),
                  onTap: () => setState(() {
                    _target = c;
                    _search.clear();
                  }),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _carry,
                onChanged: (v) => setState(() => _carry = v ?? false),
                title: Text(s.t('hold.carrySteps')),
                subtitle: Text(s.t('hold.carryNote'), style: const TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8F9F7), borderRadius: BorderRadius.circular(8)),
              child: Text(s.t('hold.note.$_kind'), style: const TextStyle(fontSize: 13, color: C.muted, height: 1.45)),
            ),
            for (final e in _errors)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(e, style: const TextStyle(color: C.critical))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common.close'))),
        FilledButton(
          style: _kind == 'hold' ? null : FilledButton.styleFrom(backgroundColor: C.critical),
          onPressed: _saving ? null : _submit,
          child: Text(s.t('hold.submit.$_kind')),
        ),
      ],
    );
  }
}
