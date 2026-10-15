// Today: what needs attention, what starts this week, and where everything else is
// waiting. On a wide screen the chosen order opens on the right.
import 'package:flutter/material.dart' hide Actions;

import '../../app/app_state.dart';
import '../../app/scope.dart';
import '../../domain/insights.dart';
import '../../domain/rules_engine.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'order_detail.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.data.loaded) return const DelayedLoader();
    final wide = isWide(context);
    final queue = _Queue(selected: wide ? app.selectedOrderId : null);
    if (!wide) return queue;
    final sel = app.orderById(app.selectedOrderId);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: MediaQuery.sizeOf(context).width >= 1600 ? 480 : 420, // more room for the reason on a big monitor
        child: DecoratedBox(
          decoration: const BoxDecoration(color: C.card, border: BorderDirectional(end: BorderSide(color: C.line))),
          child: queue,
        ),
      ),
      Expanded(
        child: sel == null
            ? EmptyState(icon: Icons.touch_app_outlined, title: app.s.t('today.pickOrder'), body: app.s.t('today.pickOrderBody'))
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                layoutBuilder: fillLayout,
                child: KeyedSubtree(key: ValueKey(sel.id), child: OrderDetail(orderId: sel.id!)),
              ),
      ),
    ]);
  }
}

class _Queue extends StatelessWidget {
  const _Queue({this.selected});
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final all = app.evaluated;
    if (app.orders.isEmpty) {
      return EmptyState(
        icon: Icons.post_add,
        title: s.t('empty.firstOrder'),
        body: s.t('empty.firstOrderBody'),
        action: FilledButton.icon(onPressed: () => newOrder(context), icon: const Icon(Icons.add), label: Text(s.t('nav.newOrder'))),
      );
    }
    final active = all.where((x) => x.ev.status == 'open' || x.ev.status == 'on_hold').toList();
    final attention = active.where((x) => x.ev.alerts.isNotEmpty).toList()
      ..sort((a, b) {
        final sa = worstSeverity(a.ev.alerts) == 'critical' ? 2 : 1, sb = worstSeverity(b.ev.alerts) == 'critical' ? 2 : 1;
        if (sa != sb) return sb - sa;
        return _days(b.ev) - _days(a.ev);
      });
    final lateStarts = attention.where((x) => x.ev.alerts.any((a) => a.code == 'late_start')).toList();
    final others = attention.where((x) => !x.ev.alerts.any((a) => a.code == 'late_start')).toList();
    final starts = app.memo('startsByDay', () => app.insights.startsByDay(app.orders, app.today, alertSettings: app.alertSettings));
    final startCount = starts.fold<int>(0, (n, d) => n + d.count);
    final board = app.memo('board', () => app.insights.board(app.orders, app.today, alertSettings: app.alertSettings));
    final receivedToday = app.orders.where((o) => o.receivedDate == app.today).length;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(s.t('nav.today'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${s.weekday(app.today)} ${app.dateShort(app.today)}${app.showHijri ? ' · ${s.hijri(app.today, app.calendar)}' : ''}',
                style: const TextStyle(color: C.muted, fontSize: 13)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text.rich(TextSpan(style: const TextStyle(color: C.muted, fontSize: 13), children: [
          TextSpan(text: s.t('today.summary', {'open': active.length, 'received': receivedToday})),
          if (attention.isNotEmpty) TextSpan(text: ' · ${s.t('today.needAttention', {'count': attention.length})}', style: const TextStyle(color: C.critical, fontWeight: FontWeight.w500)),
        ])),
      ),
      _Head(title: s.t('today.needsAttention'), count: attention.length, onTap: () => app.showOrders(const FilterCriteria(quick: ['needs_attention']), title: s.t('today.needsAttention'))),
      if (attention.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, color: C.success, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${s.t('empty.nothingAttention')} — ${s.t('empty.nothingAttentionBody', {'count': active.length})}', style: const TextStyle(color: C.muted))),
          ]),
        ),
      if (lateStarts.length > 1)
        _GroupLink(
          severity: 'critical',
          text: s.t('today.lateStarts', {'count': lateStarts.length, 'days': lateStarts.map((x) => _alertDays(x.ev, 'late_start')).reduce((a, b) => a > b ? a : b)}),
          onTap: () => app.showOrders(const FilterCriteria(quick: ['late_start']), title: s.t('filter.quick.late_start')),
        )
      else
        for (final x in lateStarts) _AlertTile(x: x, selected: selected),
      for (final x in others.take(12)) _AlertTile(x: x, selected: selected),
      if (others.length > 12)
        _More(count: others.length - 12, onTap: () => app.showOrders(const FilterCriteria(quick: ['needs_attention']), title: s.t('today.needsAttention'))),
      _Head(
        title: s.t('today.startsThisWeek'),
        count: startCount,
        onTap: () => app.go('pipeline'),
      ),
      for (final d in starts)
        for (final id in d.orders.take(3))
          if (app.orderById(id) != null)
            OrderTile(
              order: app.orderById(id)!,
              selected: id == selected,
              dense: true,
              onTap: () => openOrder(context, id),
              trailing: Text(d.date == app.today ? s.t('today.startsToday') : s.t('board.startsOn', {'date': '${s.weekday(d.date)} ${app.dateShort(d.date)}'}),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
            ),
      for (final col in board)
        if (col.cards.isNotEmpty && col.stage != 'starting') ...[
          _Head(
            title: s.t('today.stage.${col.stage}'),
            count: col.cards.length,
            onTap: () => app.go('board'),
          ),
          for (final c in col.cards.take(4))
            if (app.orderById(c.id) != null)
              OrderTile(
                order: app.orderById(c.id)!,
                selected: c.id == selected,
                dense: true,
                onTap: () => openOrder(context, c.id),
                subtitle: [c.district, c.nextKey == null ? null : s.t('order.nextStep', {'step': s.step(c.nextKey!)})].whereType<String>().join(' · '),
                trailing: c.onHold ? Pill(s.status('on_hold'), color: C.warning, background: C.warningSoft) : Mono(s.t('common.daysShort', {'count': c.daysWaiting}), size: 11.5, color: C.faint),
              ),
          if (col.cards.length > 4) _More(count: col.cards.length - 4, onTap: () => app.go('board')),
        ],
      const SizedBox(height: 80),
    ];
    return ListView(children: children);
  }

  static int _days(Evaluation ev) => ev.alerts.map((a) => (a['days'] as int?) ?? 0).fold<int>(0, (m, d) => d > m ? d : m);
  static int _alertDays(Evaluation ev, String code) => ev.alerts.where((a) => a.code == code).map((a) => (a['days'] as int?) ?? 0).fold<int>(0, (m, d) => d > m ? d : m);
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.x, this.selected});
  final Evaluated x;
  final String? selected;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final a = x.ev.alerts.first;
    return OrderTile(
      order: x.order,
      selected: x.order.id == selected,
      onTap: () => openOrder(context, x.order.id),
      subtitle: [x.order.district, s.alert(a)].whereType<String>().join(' · '),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.title, required this.count, this.onTap});
  final String title;
  final int count;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
            Mono('$count', size: 12.5, color: C.muted),
            if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: C.faint),
          ]),
        ),
      );
}

class _GroupLink extends StatelessWidget {
  const _GroupLink({required this.text, required this.onTap, this.severity});
  final String text;
  final VoidCallback onTap;
  final String? severity;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: severityEdge(severity), width: 3))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(children: [
            SeverityDot(severity),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: severityColor(severity), fontWeight: FontWeight.w500))),
            const Icon(Icons.chevron_right, size: 18, color: C.faint),
          ]),
        ),
      );
}

class _More extends StatelessWidget {
  const _More({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: TextButton(onPressed: onTap, child: Text('+ ${context.t('common.more', {'count': count})}')),
        ),
      );
}

/// Used by other screens: today's date line.
String todayLine(AppState app) => '${app.s.weekday(app.today)} ${app.dateShort(app.today)}';
