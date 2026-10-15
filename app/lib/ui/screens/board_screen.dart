// Board: every order with work under way, in the column of its next step.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../domain/insights.dart';
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 18, phone ? 12 : 16, 10),
        child: Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('board.title'), style: Theme.of(context).textTheme.titleLarge),
            Text(s.t('board.summary', {'count': total, 'late': late, 'hold': hold}), style: const TextStyle(color: C.muted, fontSize: 13)),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Pick(label: s.t('order.contractor'), value: _contractor, all: s.t('filter.all'), options: contractors, show: (v) => v == unassignedContractor ? s.t('common.unassigned') : v, onChanged: (v) => setState(() => _contractor = v)),
            _Pick(label: s.t('order.district'), value: _district, all: s.t('filter.all'), options: districts, onChanged: (v) => setState(() => _district = v)),
            FilterChip(label: Text(s.t('board.lateOnly')), selected: _lateOnly, onSelected: (v) => setState(() => _lateOnly = v)),
          ]),
        ]),
      ),
      Expanded(
        child: total == 0
            ? EmptyState(icon: Icons.view_kanban_outlined, title: s.t('board.empty'))
            : ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 0, phone ? 12 : 16, 20),
                children: [
                  for (final (stage, cards) in shown)
                    Container(
                      width: phone ? 280 : 250,
                      margin: const EdgeInsetsDirectional.only(end: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Color.alphaBlend(stageColor(stage).withAlpha(20), C.lineSoft), borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                          child: Row(children: [
                            Container(width: 10, height: 10, margin: const EdgeInsetsDirectional.only(end: 8), decoration: BoxDecoration(color: stageColor(stage), shape: BoxShape.circle)),
                            Expanded(child: Text(s.stage(stage), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: stageColor(stage)))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                              decoration: BoxDecoration(color: stageColor(stage), borderRadius: BorderRadius.circular(999)),
                              child: Mono('${cards.length}', size: 12, color: Colors.white),
                            ),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Text(s.t('board.hint.$stage'), style: const TextStyle(fontSize: 11.5, color: C.faint)),
                        ),
                        Expanded(
                          child: cards.isEmpty
                              ? Center(child: Text(s.t('board.none'), style: const TextStyle(color: C.faint, fontSize: 12.5)))
                              : ListView.separated(
                                  itemCount: cards.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (_, i) => _Card(card: cards[i]),
                                ),
                        ),
                      ]),
                    ),
                ],
              ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 0, phone ? 12 : 16, 12),
        child: Text(s.t('board.footer'), style: const TextStyle(fontSize: 12, color: C.faint)),
      ),
    ]);
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
    return Material(
      color: C.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openOrder(context, c.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: C.line),
          ),
          child: Container(
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: severityEdge(c.severity), width: 3))),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Mono(c.woNumber ?? '—', size: 13, weight: FontWeight.w600)), TypeTag(c.type ?? '')]),
              const SizedBox(height: 3),
              Text([c.district, c.contractor ?? s.t('common.unassigned')].whereType<String>().join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                    c.startsOn != null ? s.t('board.startsOn', {'date': app.dateShort(c.startsOn!)}) : (c.nextKey == null ? '' : s.step(c.nextKey!)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                if (c.onHold)
                  Pill(s.status('on_hold'), color: C.warning, background: C.warningSoft)
                else if (c.startsOn == null)
                  Mono(s.t('common.daysShort', {'count': c.daysWaiting}), size: 11.5, color: c.severity == null ? C.faint : severityColor(c.severity)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(border: Border.all(color: C.field), borderRadius: BorderRadius.circular(6), color: C.card),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$label ', style: const TextStyle(color: C.faint, fontSize: 13)),
            Text(value == null ? all : (show?.call(value!) ?? value!), style: const TextStyle(fontSize: 13)),
            const Icon(Icons.arrow_drop_down, size: 18, color: C.faint),
          ]),
        ),
      );
}
