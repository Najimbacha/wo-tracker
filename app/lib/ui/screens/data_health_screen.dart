// Data health: is everything saved and synced, what the server refused, deleted
// orders (restorable any time), and how full the free database is.
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'order_detail.dart';
import 'settings_screen.dart';

class DataHealthScreen extends StatefulWidget {
  const DataHealthScreen({super.key});
  @override
  State<DataHealthScreen> createState() => _DataHealthScreenState();
}

class _DataHealthScreenState extends State<DataHealthScreen> {
  late Future<Map<String, dynamic>?> _health = context.appRead.repo.dataHealth();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final sy = app.sync;
    final deleted = app.deletedOrders;
    final ok = sy.pendingChanges == 0 && app.refused.isEmpty && (sy.state == 'synced' || app.repo.isDemo);
    return Scaffold(
      appBar: AppBar(backgroundColor: C.card, surfaceTintColor: C.card, title: Text(s.t('settings.dataHealth'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: ok ? C.successSoft : C.warningSoft, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(ok ? Icons.verified_user_outlined : Icons.sync_problem_outlined, color: ok ? C.success : C.warning, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t(ok ? 'health.allSafe' : 'health.needsLook'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ok ? C.success : C.warning)),
                Text(
                  [
                    if (sy.lastSyncedAt != null) s.t('data.syncedAgo', {'when': agoText(app, sy.lastSyncedAt!)}),
                    if (sy.pendingChanges > 0) s.t('toast.waitingSync', {'count': sy.pendingChanges}),
                    if (!sy.configured && !app.repo.isDemo) s.t('health.onlyThisDevice'),
                  ].join(' · '),
                  style: const TextStyle(color: C.muted),
                ),
              ]),
            ),
            OutlinedButton(onPressed: () => exportEverything(context), child: Text(s.t('settings.exportEverything'))),
          ]),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: s.t('health.places'),
          child: Column(children: [
            _Line(ok: true, label: s.t('health.thisDevice'), meta: s.t('health.ordersCount', {'count': app.data.orders.length})),
            _Line(ok: sy.signedIn && sy.connected, label: s.t('health.cloud'), meta: sy.signedIn ? (sy.connected ? s.t('sync.badge.synced') : s.t('sync.badge.offline')) : s.t('sync.signedOut')),
            _Line(ok: true, label: s.t('health.nightlyBackup'), meta: s.t('health.nightlyBackupMeta')),
            _Line(ok: true, label: s.t('health.history'), meta: s.t('health.historyMeta')),
          ]),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: s.t('health.size'),
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _health,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 40, child: DelayedLoader());
              final h = snap.data;
              if (h == null) {
                return Row(children: [
                  Expanded(child: Text(s.t('health.sizeOffline'), style: const TextStyle(color: C.muted))),
                  TextButton(onPressed: () => setState(() => _health = app.repo.dataHealth()), child: Text(s.t('common.retry'))),
                ]);
              }
              final pct = (h['percent'] as num?)?.toDouble() ?? 0;
              final warn = (h['warn_percent'] as num?)?.toDouble() ?? 80;
              final mb = ((h['db_bytes'] as num?) ?? 0) / 1048576;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s.t('health.sizeLine', {'mb': mb.toStringAsFixed(1), 'percent': pct.toStringAsFixed(1)})),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 8, color: pct >= warn ? C.critical : C.accent, backgroundColor: C.chip),
                if (pct >= warn) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.t('health.sizeWarn'), style: const TextStyle(color: C.critical))),
              ]);
            },
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '${s.t('refused.title')} · ${app.refused.length}',
          child: app.refused.isEmpty
              ? Text(s.t('health.noRefused'), style: const TextStyle(color: C.muted))
              : Column(children: [for (final r in app.refused) _Refused(r: r)]),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '${s.t('settings.deletedOrders')} · ${deleted.length}',
          child: deleted.isEmpty
              ? Text(s.t('health.noDeleted'), style: const TextStyle(color: C.muted))
              : Column(children: [
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(s.t('health.deletedNote'), style: const TextStyle(color: C.muted, fontSize: 12.5))),
                  for (final o in deleted)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Row(children: [Mono(o.woNumber ?? ''), const SizedBox(width: 8), TypeTag(o.type), const SizedBox(width: 8), Flexible(child: Text(o.district ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)))]),
                      subtitle: Text(o.deletedReason ?? ''),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderPage(orderId: o.id!))),
                      trailing: OutlinedButton(
                        onPressed: () => app.apply(o, app.actions.restoreOrder(o, app.data.orders), toast: 'toast.restored'),
                        child: Text(s.t('common.restore')),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.ok, required this.label, required this.meta});
  final bool ok;
  final String label, meta;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline, size: 18, color: ok ? C.success : C.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          // Long descriptions wrap instead of running off a phone screen.
          Flexible(child: Text(meta, textAlign: TextAlign.end, style: const TextStyle(color: C.faint, fontSize: 12.5))),
        ]),
      );
}

class _Refused extends StatelessWidget {
  const _Refused({required this.r});
  final RefusedChange r;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final order = app.orderById(r.workOrderId);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('refused.${r.code}', {'value': r.value ?? '', 'message': r.message ?? ''}), style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(
          [
            if (order != null) '${s.t('order.woNumber')} ${order.woNumber}',
            s.t('history.table.${r.table}'),
            app.dateShort(r.at.toIso8601String().substring(0, 10)),
          ].join(' · '),
          style: const TextStyle(color: C.faint, fontSize: 12),
        ),
        if (r.message != null && r.message!.isNotEmpty) Text(s.t('refused.details', {'message': r.message}), style: const TextStyle(color: C.faint, fontSize: 11.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          if (order != null)
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderPage(orderId: order.id!))),
              child: Text(s.t('refused.editAgain')),
            ),
          OutlinedButton(
            onPressed: () async {
              try {
                await app.repo.retryRefused(r.id);
                app.showToast(s.t('refused.sentAgain'));
              } catch (e) {
                app.showError(e);
              }
            },
            child: Text(s.t('common.retry')),
          ),
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(s.t('refused.undo')),
                  content: Text(s.t('refused.undoBody')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common.cancel'))),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('refused.undo'))),
                  ],
                ),
              );
              if (ok == true) {
                try {
                  await app.repo.dismissRefused(r.id);
                } catch (e) {
                  app.showError(e);
                }
              }
            },
            child: Text(s.t('refused.undo')),
          ),
        ]),
      ]),
    );
  }
}
