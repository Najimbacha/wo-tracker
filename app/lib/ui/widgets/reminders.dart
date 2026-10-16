// Reminders on an order ("check tasreeh on Sunday"): a card on the order, and a list on Today
// for the ones that are due. Ticking one off keeps it; removing one only hides it.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../data/models.dart';
import '../../domain/order_input.dart';
import '../../domain/rules_engine.dart';
import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';

String _plus(String ymd, int days) => fromDay(toDay(ymd) + days);

/// Days from today to [due]: negative when it has passed.
int daysUntil(String due, String today) => toDay(due) - toDay(today);

List<Reminder> remindersOf(BuildContext context, OrderInput o) =>
    [for (final r in context.app.data.reminders) if (r.orderId == o.id) r];

Future<void> showReminderDialog(BuildContext context, OrderInput order) async {
  final app = context.appRead;
  final s = app.s;
  final note = TextEditingController();
  String due = _plus(app.today, 1);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(s.t('reminder.add'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: note,
              autofocus: true,
              onChanged: (_) => setS(() {}),
              decoration: InputDecoration(labelText: s.t('reminder.note'), hintText: s.t('reminder.noteHint')),
            ),
            const SizedBox(height: 14),
            DateField(
              label: s.t('reminder.due'),
              value: due,
              allowFuture: true,
              quick: [
                (s.t('reminder.tomorrow'), _plus(app.today, 1)),
                for (final n in const [3, 7]) (s.t('date.afterDays', {'count': n}), _plus(app.today, n)),
              ],
              onChanged: (v) => setS(() => due = v ?? due),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
          FilledButton(onPressed: note.text.trim().isEmpty ? null : () => Navigator.pop(c, true), child: Text(s.t('common.save'))),
        ],
      ),
    ),
  );
  // The controller is not disposed here: the dialog is still fading out and would use it once more.
  final text = note.text;
  if (ok != true || order.id == null) return;
  try {
    await app.repo.addReminder(orderId: order.id!, due: due, note: text);
    app.showToast(s.t('reminder.added', {'date': app.dateShort(due)}));
  } on Object catch (e) {
    app.showToast('$e', error: true);
  }
}

/// "Today" / "Tomorrow" / "3 days late" / "in 4 days" for a reminder's day.
String dueLabel(BuildContext context, String due) {
  final app = context.app;
  final s = app.s;
  final d = daysUntil(due, app.today);
  if (d < 0) return s.t('reminder.late', {'count': -d});
  if (d == 0) return s.t('common.today');
  if (d == 1) return s.t('reminder.tomorrow');
  return '${s.weekday(due)} ${app.dateShort(due)}';
}

/// The reminders of one order, with an add button.
class RemindersCard extends StatelessWidget {
  const RemindersCard({super.key, required this.order, required this.canEdit});
  final OrderInput order;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final all = remindersOf(context, order);
    // Open ones first (by day), done ones after.
    final list = [...all.where((r) => !r.done), ...all.where((r) => r.done)];
    if (list.isEmpty && !canEdit) return const SizedBox.shrink();
    return SectionCard(
      title: s.t('reminder.title'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      trailing: canEdit ? TextButton.icon(onPressed: () => showReminderDialog(context, order), icon: const Icon(Icons.add, size: 18), label: Text(s.t('reminder.addShort'))) : null,
      child: list.isEmpty
          ? Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(s.t('reminder.none'), style: const TextStyle(color: C.faint, fontSize: 13)))
          : Column(children: [for (final r in list) _ReminderRow(r: r, canEdit: canEdit)]),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.r, required this.canEdit});
  final Reminder r;
  final bool canEdit;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final overdue = !r.done && daysUntil(r.due, app.today) < 0;
    return Row(children: [
      Checkbox(value: r.done, onChanged: canEdit ? (v) => app.repo.setReminderDone(r.id, v ?? false) : null),
      Expanded(
        child: Text(r.note, style: TextStyle(color: r.done ? C.faint : C.ink, decoration: r.done ? TextDecoration.lineThrough : null)),
      ),
      const SizedBox(width: 8),
      Text(dueLabel(context, r.due), style: TextStyle(fontSize: 12.5, color: overdue ? C.critical : C.muted, fontWeight: overdue ? FontWeight.w600 : FontWeight.w400)),
      if (canEdit) IconButton(tooltip: app.s.t('common.remove'), visualDensity: VisualDensity.compact, onPressed: () => app.repo.removeReminder(r.id), icon: const Icon(Icons.close, size: 18, color: C.faint)),
    ]);
  }
}
