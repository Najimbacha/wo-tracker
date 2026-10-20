// Board: every order with work under way, in the column of its next step.
// Stages with nothing in them fold into a slim strip so the busy ones get the room.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../domain/insights.dart';
import '../../i18n/strings.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  String? _contractor;
  String? _district;
  bool _lateOnly = false;

  bool _keep(BoardCard c) =>
      (_contractor == null || (c.contractor ?? unassignedContractor) == _contractor) &&
      (_district == null || c.district == _district) &&
      (!_lateOnly || c.severity != null);

  static const _railWidth = 56.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (!app.data.loaded) return const DelayedLoader();
    final cols = app.memo('board', () => app.insights.board(app.orders, app.today, alertSettings: app.alertSettings));
    final shown = [for (final c in cols) (c.stage, c.cards.where(_keep).toList())];
    final total = cols.fold<int>(0, (n, c) => n + c.cards.length);
    final late = cols.fold<int>(0, (n, c) => n + c.cards.where((x) => x.severity != null).length);
    final hold = cols.fold<int>(0, (n, c) => n + c.cards.where((x) => x.onHold).length);
    final contractors = {for (final c in cols) for (final k in c.cards) k.contractor ?? unassignedContractor}.toList()..sort();
    final districts = {for (final c in cols) for (final k in c.cards) if (k.district != null) k.district!}.toList()..sort();
    final phone = isPhone(context);
    final pad = phone ? 14.0 : 24.0;
    final busy = shown.where((c) => c.$2.isNotEmpty).length;
    final rails = shown.length - busy;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: s.t('board.title'),
        chips: [
          StatChip(total, s.t('board.statOpen')),
          StatChip(late, s.t('board.statLate'), tone: late > 0 ? 'critical' : null),
          StatChip(hold, s.t('board.statHold'), tone: hold > 0 ? 'warning' : null),
        ],
        actions: [
          _Pick(label: s.t('order.contractor'), value: _contractor, all: s.t('filter.all'), options: contractors, show: (v) => v == unassignedContractor ? s.t('common.unassigned') : v, onChanged: (v) => setState(() => _contractor = v)),
          _Pick(label: s.t('order.district'), value: _district, all: s.t('filter.all'), options: districts, onChanged: (v) => setState(() => _district = v)),
          _Toggle(label: s.t('board.lateOnly'), on: _lateOnly, onChanged: (v) => setState(() => _lateOnly = v)),
        ],
      ),
      Expanded(
        child: total == 0
            ? EmptyState(icon: Icons.view_kanban_outlined, title: s.t('board.empty'))
            : LayoutBuilder(builder: (context, box) {
                // The busy columns share what the strips leave; never thinner than a phone card.
                final room = box.maxWidth - 2 * pad - rails * (_railWidth + _gap) - (busy > 0 ? (busy - 1) * _gap : 0);
                final colWidth = phone ? 290.0 : (busy == 0 ? 300.0 : (room / busy).clamp(300.0, 560.0));
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
                  children: [
                    for (final (stage, cards) in shown)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: _gap),
                        child: cards.isEmpty
                            ? _Rail(stage: stage)
                            : _Column(stage: stage, cards: cards, width: colWidth),
                      ),
                  ],
                );
              }),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 14),
        child: Text(s.t('board.footer'), style: TextStyle(fontSize: 12.5, color: C.faint)),
      ),
    ]);
  }
}

BoxDecoration _columnBox() => BoxDecoration(color: C.col, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line));

/// A stage with nothing in it: just its name, running up the side, and a 0.
class _Rail extends StatelessWidget {
  const _Rail({required this.stage});
  final String stage;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Tooltip(
      message: s.t('board.hint.$stage'),
      child: Container(
        width: _BoardScreenState._railWidth,
        decoration: _columnBox(),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(height: 3, color: stageColor(stage)),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(minWidth: 24),
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(999)),
            child: Mono('0', size: 12, color: C.faint),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: RotatedBox(quarterTurns: 3, child: Text(s.stage(stage), maxLines: 1, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: C.muted))),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.stage, required this.cards, required this.width});
  final String stage;
  final List<BoardCard> cards;
  final double width;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final color = stageColor(stage);
    return Container(
      width: width,
      decoration: _columnBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 3, color: color),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.stage(stage), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: color)),
                const SizedBox(height: 3),
                Text(s.t('board.hint.$stage'), style: TextStyle(fontSize: 12.5, color: C.faint)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              constraints: const BoxConstraints(minWidth: 26),
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
              child: Mono('${cards.length}', size: 13, weight: FontWeight.w600, color: C.onSolid),
            ),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _Card(card: cards[i]),
          ),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card});
  final BoardCard card;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final c = card;
    final nextText = c.startsOn != null ? s.t('board.startsOn', {'date': app.dateShort(c.startsOn!)}) : (c.nextKey == null ? '' : s.todo(c.nextKey!));
    final who = c.contractor ?? s.t('common.unassigned');
    final place = [who, if (c.district != null) c.district!].join(' · ');
    final edge = severityEdge(c.severity);
    final f = c.total == 0 ? 0.0 : (c.closed / c.total).clamp(0.0, 1.0);
    return Material(
      color: C.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: C.accentSoft.withAlpha(90),
        onTap: () => openOrder(context, c.id),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3, color: edge),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Mono(c.woNumber ?? '—', size: 17, weight: FontWeight.w600)),
                      TypeTag(c.type ?? ''),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.person_outline, size: 17, color: C.faint),
                      const SizedBox(width: 7),
                      Expanded(child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: C.muted))),
                    ]),
                    const SizedBox(height: 14),
                    Text(s.t('board.nextLabel').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.8, color: C.faint)),
                    const SizedBox(height: 4),
                    Text(nextText, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(value: f, minHeight: 4, backgroundColor: C.chip, color: C.accent),
                          ),
                          const SizedBox(height: 6),
                          Text(s.t('board.stepsOf', {'closed': c.closed, 'total': c.total}), style: TextStyle(fontSize: 12, color: C.faint)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      _waiting(s, c),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _waiting(Strings s, BoardCard c) {
    if (c.onHold) return Pill(s.status('on_hold'), color: C.warning, background: C.warningSoft);
    if (c.startsOn != null) return const SizedBox.shrink();
    final text = c.daysWaiting <= 0 ? s.t('board.waitingNew') : s.t('board.waitingDays', {'count': c.daysWaiting});
    if (c.severity == 'critical') return Pill(text, color: C.critical, background: C.criticalSoft);
    if (c.severity == 'warning') return Pill(text, color: C.warning, background: C.warningSoft);
    if (c.daysWaiting <= 0) return Pill(text, color: C.accentDark, background: C.accentSoft);
    return Pill(text);
  }
}

/// "Late only": a switch that looks like the other filters.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.on, required this.onChanged});
  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!on),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? C.criticalSoft : C.card,
            border: Border.all(color: on ? C.critical : C.field),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: C.critical, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13.5, color: on ? C.critical : C.ink, fontWeight: on ? FontWeight.w500 : FontWeight.w400)),
          ]),
        ),
      );
}

class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.value, required this.all, required this.options, required this.onChanged, this.show});
  final String label;
  final String? value;
  final String all;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String Function(String)? show;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String?>(
        tooltip: label,
        onSelected: (v) => onChanged(v == '\u0000' ? null : v),
        itemBuilder: (_) => [
          PopupMenuItem<String?>(value: '\u0000', child: Text(all)),
          for (final o in options) PopupMenuItem<String?>(value: o, child: Text(show?.call(o) ?? o)),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(border: Border.all(color: C.field), borderRadius: BorderRadius.circular(8), color: C.card),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$label ', style: TextStyle(color: C.muted, fontSize: 13.5)),
            Text(value == null ? all : (show?.call(value!) ?? value!), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: C.ink)),
            Icon(Icons.arrow_drop_down, size: 20, color: C.faint),
          ]),
        ),
      );
}
