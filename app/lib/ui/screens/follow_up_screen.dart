// Follow-up: for each contractor, what they must do next, most urgent first, and a
// message to send them (copy, or share to WhatsApp) in English or Arabic.
import 'package:flutter/material.dart' hide Actions;
import 'package:flutter/services.dart';

import '../../app/app_state.dart';
import '../../app/scope.dart';
import '../../domain/insights.dart';
import '../../i18n/strings.dart';
import '../../report/files.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({super.key});
  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (!app.data.loaded) return const DelayedLoader();
    final list = app.memo('followUp', () => app.insights.followUp(app.orders, app.today, alertSettings: app.alertSettings));
    if (list.isEmpty) return EmptyState(icon: Icons.groups_outlined, title: s.t('followUp.empty'));
    final cur = list.firstWhere((c) => c.contractor == _selected, orElse: () => list.first);
    final wide = isWide(context);
    final side = ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text(s.t('followUp.title'), style: Theme.of(context).textTheme.titleLarge),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Text(s.t('followUp.subtitle'), style: const TextStyle(color: C.muted, fontSize: 13))),
      for (final c in list)
        ListTile(
          selected: c.contractor == cur.contractor,
          selectedTileColor: C.accentSoft,
          title: Text(_name(s, c.contractor)),
          subtitle: c.late > 0 ? Text(s.t('followUp.late', {'count': c.late}), style: const TextStyle(color: C.critical)) : null,
          trailing: Mono('${c.orders}', color: C.muted),
          onTap: () {
            setState(() => _selected = c.contractor);
            if (!wide) {
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _DetailPage(contractor: c.contractor)));
            }
          },
        ),
    ]);
    if (!wide) return side;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 300, child: DecoratedBox(decoration: const BoxDecoration(color: C.card, border: BorderDirectional(end: BorderSide(color: C.line))), child: side)),
      Expanded(child: _Detail(key: ValueKey(cur.contractor), con: cur)),
    ]);
  }
}

/// Phone: one contractor as its own page, kept up to date as orders change.
class _DetailPage extends StatelessWidget {
  const _DetailPage({required this.contractor});
  final String contractor;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final list = app.memo('followUp', () => app.insights.followUp(app.orders, app.today, alertSettings: app.alertSettings));
    final con = list.where((c) => c.contractor == contractor).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(_name(app.s, contractor))),
      body: con == null ? EmptyState(icon: Icons.done_all, title: app.s.t('followUp.empty')) : _Detail(con: con),
    );
  }
}

String _name(Strings s, String c) => c == unassignedContractor ? s.t('common.unassigned') : c;

class _Detail extends StatefulWidget {
  const _Detail({super.key, required this.con});
  final ContractorFollowUp con;
  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  late String lang = context.appRead.lang;
  ContractorFollowUp get con => widget.con;
  void onLang(String l) => setState(() => lang = l);

  /// The message for the contractor, in [l].
  static String message(AppState app, ContractorFollowUp c, String l) {
    final s = app.stringsFor(l);
    final b = StringBuffer()
      ..writeln(s.t('followUp.msgTitle', {'contractor': _name(s, c.contractor), 'date': s.date(app.today)}))
      ..writeln(s.t('followUp.msgFrom', {'name': app.data.settings.preparedBy}))
      ..writeln();
    for (final g in c.sortedGroups) {
      b.writeln('${s.t('followUp.group.${g.group}')} (${g.items.length})');
      b.writeln(g.items.map((i) => i.woNumber ?? '').join(' · '));
      b.writeln();
    }
    return b.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final last = _lastFollowUp(app, con.contractor);
    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_name(s, con.contractor), style: Theme.of(context).textTheme.titleLarge),
          Text(s.t('followUp.inProgress', {'count': con.orders}), style: const TextStyle(color: C.muted)),
        ]),
        if (last != null) Text(s.t('followUp.lastFollowedUp', {'when': last}), style: const TextStyle(color: C.faint, fontSize: 12.5)),
      ]),
      const SizedBox(height: 16),
      for (final g in con.sortedGroups) ...[
        SectionCard(
          title: s.t('followUp.group.${g.group}'),
          trailing: g.severity == null
              ? Mono('${g.items.length}', color: C.muted)
              : Pill(s.t('followUp.late', {'count': g.items.where((i) => i.severity != null).length}), color: severityColor(g.severity), background: g.severity == 'critical' ? C.criticalSoft : C.warningSoft),
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Column(children: [
            for (final i in g.items)
              if (app.orderById(i.id) != null)
                OrderTile(
                  order: app.orderById(i.id)!,
                  dense: true,
                  onTap: () => openOrder(context, i.id),
                  subtitle: [
                    app.orderById(i.id)!.district,
                    i.steps.map((x) => s.step(x.split('@').first)).toSet().join(', '),
                    if (i.startsOn != null) s.t('board.startsOn', {'date': app.dateShort(i.startsOn!)}),
                  ].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                  trailing: i.startsOn == null ? Mono(s.t('common.daysShort', {'count': i.daysWaiting}), size: 11.5, color: i.severity == null ? C.faint : severityColor(i.severity)) : null,
                ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      SectionCard(
        title: s.t('followUp.send'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ar', label: Text('العربية'))],
            selected: {lang},
            onSelectionChanged: (v) => onLang(v.first),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF8F9F7), borderRadius: BorderRadius.circular(8)),
            child: Directionality(
              textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
              child: SelectableText(message(app, con, lang), style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () async {
                final text = message(app, con, lang);
                try {
                  await shareText(text);
                } catch (_) {
                  // No share option on this computer: copy instead, and say so.
                  await Clipboard.setData(ClipboardData(text: text));
                  app.showToast(s.t('toast.shareCopied'));
                }
              },
              icon: const Icon(Icons.share_outlined, size: 18),
              label: Text(s.t('followUp.share')),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message(app, con, lang)));
                app.showToast(s.t('toast.copied'));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: Text(s.t('followUp.copyText')),
            ),
            OutlinedButton.icon(
              onPressed: () => _markFollowed(context, app),
              icon: const Icon(Icons.done_all, size: 18),
              label: Text(s.t('followUp.markFollowedUp')),
            ),
          ]),
        ]),
      ),
    ]);
  }

  String? _lastFollowUp(AppState app, String contractor) {
    final ids = app.data.contractors.where((c) => c.name == contractor).map((c) => c.id).toSet();
    final f = app.data.followUps.where((x) => ids.contains(x.contractorId)).toList()..sort((a, b) => b.followedAt.compareTo(a.followedAt));
    if (f.isEmpty) return null;
    final t = f.first.followedAt.toUtc().add(const Duration(hours: 3));
    final ymd = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return '${app.dateShort(ymd)}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _markFollowed(BuildContext context, AppState app) async {
    final c = app.data.contractors.where((x) => x.name == con.contractor && !x.deleted).toList();
    if (c.isEmpty) {
      app.showToast(app.s.t('followUp.noContractor'), error: true);
      return;
    }
    try {
      await app.repo.markFollowedUp(c.first.id);
      app.showToast(app.s.t('toast.followedUp'));
    } catch (e) {
      app.showError(e);
    }
  }
}
