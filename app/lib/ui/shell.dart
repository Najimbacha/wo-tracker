// The frame around every screen: menu, search (Ctrl+K), New order (Ctrl+N), the sync
// badge, and banners for offline / demo / changes that need a decision.
import 'package:flutter/material.dart' hide Actions;
import 'package:flutter/services.dart';

import '../app/scope.dart';
import 'nav.dart';
import 'screens/board_screen.dart';
import 'screens/follow_up_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/pipeline_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/search_dialog.dart';
import 'screens/settings_screen.dart';
import 'screens/today_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

const _icons = <String, IconData>{
  'today': Icons.wb_sunny_outlined,
  'board': Icons.view_kanban_outlined,
  'pipeline': Icons.stacked_bar_chart,
  'followUp': Icons.groups_outlined,
  'orders': Icons.list_alt_outlined,
  'reports': Icons.description_outlined,
  'settings': Icons.settings_outlined,
};

const _navKeys = <String, String>{
  'today': 'nav.today',
  'board': 'nav.board',
  'pipeline': 'nav.pipeline',
  'followUp': 'nav.followUp',
  'orders': 'nav.allOrders',
  'reports': 'nav.reports',
  'settings': 'nav.settings',
};

class Shell extends StatelessWidget {
  const Shell({super.key});

  Widget _page(String screen) => switch (screen) {
        'board' => const BoardScreen(),
        'pipeline' => const PipelineScreen(),
        'followUp' => const FollowUpScreen(),
        'orders' => const OrdersScreen(),
        'reports' => const ReportsScreen(),
        'settings' => const SettingsScreen(),
        _ => const TodayScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final phone = isPhone(context);
    final body = Column(children: [
      const _Banners(),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(key: ValueKey(app.screen), child: _page(app.screen)),
        ),
      ),
    ]);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showSearchDialog(context),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => newOrder(context),
      },
      child: Focus(
        autofocus: true,
        child: phone
            ? Scaffold(
                appBar: AppBar(
                  backgroundColor: C.card,
                  surfaceTintColor: C.card,
                  titleSpacing: 16,
                  title: Text(app.s.t(_navKeys[app.screen]!), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
                  actions: [
                    IconButton(tooltip: app.s.t('nav.search'), icon: const Icon(Icons.search), onPressed: () => showSearchDialog(context)),
                    const _SyncBadge(),
                    const SizedBox(width: 8),
                  ],
                ),
                body: body,
                floatingActionButton: app.screen == 'today' || app.screen == 'orders'
                    ? FloatingActionButton(tooltip: app.s.t('nav.newOrder'), onPressed: () => newOrder(context), child: const Icon(Icons.add))
                    : null,
                bottomNavigationBar: _PhoneNav(current: app.screen),
              )
            : Scaffold(
                body: Column(children: [
                  const _TopBar(),
                  Expanded(child: body),
                ]),
              ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    return Container(
      height: 56,
      decoration: const BoxDecoration(color: C.card, border: Border(bottom: BorderSide(color: C.line))),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        const Icon(Icons.bolt, color: C.accent, size: 22),
        const SizedBox(width: 8),
        Text(app.s.t('app.name'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(width: 20),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final d in const ['today', 'board', 'pipeline', 'followUp', 'orders', 'reports', 'settings'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 2),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: app.screen == d ? C.ink : C.muted,
                      backgroundColor: app.screen == d ? C.chip : Colors.transparent,
                      textStyle: TextStyle(fontWeight: app.screen == d ? FontWeight.w600 : FontWeight.w400, fontSize: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onPressed: () => app.go(d),
                    icon: wide ? Icon(_icons[d], size: 17) : const SizedBox.shrink(),
                    label: Text(app.s.t(_navKeys[d]!)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => showSearchDialog(context),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: wide ? 260 : 180,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: const Color(0xFFF8F9F7), border: Border.all(color: C.line), borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.search, size: 17, color: C.faint),
              const SizedBox(width: 8),
              Expanded(child: Text(app.s.t('nav.search'), style: const TextStyle(color: C.faint, fontSize: 13), overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(border: Border.all(color: C.field), borderRadius: BorderRadius.circular(4)),
                child: const Text('Ctrl K', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: C.faint, fontFamily: mono)),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () => newOrder(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(app.s.t('nav.newOrder')),
        ),
        const SizedBox(width: 10),
        const _SyncBadge(),
      ]),
    );
  }
}

class _PhoneNav extends StatelessWidget {
  const _PhoneNav({required this.current});
  final String current;
  static const _main = ['today', 'orders', 'board', 'reports'];
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final idx = _main.contains(current) ? _main.indexOf(current) : 4;
    return NavigationBar(
      height: 64,
      selectedIndex: idx,
      onDestinationSelected: (i) {
        if (i < 4) {
          app.go(_main[i]);
        } else {
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final d in const ['pipeline', 'followUp', 'settings'])
                  ListTile(
                    leading: Icon(_icons[d]),
                    title: Text(app.s.t(_navKeys[d]!)),
                    onTap: () {
                      Navigator.pop(c);
                      app.go(d);
                    },
                  ),
              ]),
            ),
          );
        }
      },
      destinations: [
        for (final d in _main) NavigationDestination(icon: Icon(_icons[d]), label: app.s.t(_navKeys[d]!)),
        NavigationDestination(icon: const Icon(Icons.more_horiz), label: app.s.t('nav.more')),
      ],
    );
  }
}

/// Synced / syncing / offline / on this device only. Tap for details.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final sy = app.sync;
    final (IconData icon, Color color, String key) = app.repo.isDemo
        ? (Icons.science_outlined, C.warning, 'sync.badge.demo')
        : switch (sy.state) {
            'synced' => (Icons.cloud_done_outlined, C.success, 'sync.badge.synced'),
            'syncing' => (Icons.cloud_sync_outlined, C.accent, 'sync.badge.syncing'),
            'offline' => (Icons.cloud_off_outlined, C.warning, 'sync.badge.offline'),
            _ => (Icons.computer_outlined, C.muted, 'sync.badge.local'),
          };
    final pending = sy.pendingChanges;
    return Tooltip(
      message: app.s.t('$key.tip', {'count': pending}),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => app.go('settings'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 5),
            Text(app.s.t(key), style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w500)),
            if (pending > 0) ...[const SizedBox(width: 4), Mono('$pending', size: 11.5, color: color)],
          ]),
        ),
      ),
    );
  }
}

class _Banners extends StatelessWidget {
  const _Banners();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final out = <Widget>[];
    if (app.startupError != null) {
      out.add(Banner2(text: app.s.t('banner.startupError', {'reason': app.startupError}), icon: Icons.error_outline, color: C.critical, background: C.criticalSoft));
    }
    if (app.repo.isDemo) {
      out.add(Banner2(
        text: app.s.t('banner.demo'),
        icon: Icons.science_outlined,
        color: C.warning,
        background: C.warningSoft,
        action: TextButton(onPressed: () => app.setDemoMode(false), child: Text(app.s.t('banner.leaveDemo'))),
      ));
    } else if (app.sync.state == 'offline') {
      out.add(Banner2(text: app.s.t('toast.offline'), icon: Icons.cloud_off_outlined, color: C.warning, background: C.warningSoft));
    }
    if (app.refused.isNotEmpty) {
      out.add(Banner2(
        text: app.s.t('refused.intro', {'count': app.refused.length}),
        icon: Icons.report_gmailerrorred_outlined,
        color: C.critical,
        background: C.criticalSoft,
        action: TextButton(onPressed: () => openDataHealth(context), child: Text(app.s.t('refused.title'))),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: out);
  }
}
