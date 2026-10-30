// Settings: language, alert timings, contractors, districts, cable sizes, the report
// signature, sync (sign in), local backup, Demo mode and Data health.
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart' hide Actions;
import 'package:flutter/services.dart';

import '../../app/app_state.dart';
import '../../app/scope.dart';
import '../../data/local_backup.dart';
import '../../data/models.dart';
import '../../data/powersync_repository.dart' show supabaseStarted;
import '../../data/repository.dart';
import '../../report/files.dart';
import '../../report/xlsx_writer.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final phone = isPhone(context);
    final cards = <Widget>[
      const _SyncCard(),
      const _LanguageCard(),
      const _AppearanceCard(),
      const _AlertsCard(),
      const _ContractorsCard(),
      const _DistrictsCard(),
      const _CableCard(),
      const _ReportCard(),
      SectionCard(
        title: s.t('settings.dataHealth'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('settings.dataHealthNote'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => openDataHealth(context), icon: const Icon(Icons.health_and_safety_outlined, size: 18), label: Text(s.t('settings.openDataHealth'))),
            OutlinedButton.icon(onPressed: () => exportEverything(context), icon: const Icon(Icons.download, size: 18), label: Text(s.t('settings.exportEverything'))),
          ]),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: app.demoMode,
            onChanged: (v) => app.setDemoMode(v),
            title: Text(s.t('settings.demoMode')),
            subtitle: Text(s.t('settings.demoModeNote')),
          ),
        ]),
      ),
      const _BackupCard(),
    ];
    return LayoutBuilder(builder: (context, c) {
      final per = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 720 ? 2 : 1);
      // Cards stack in columns (each column as tall as its own cards), so a short card
      // never leaves a big empty gap beside a tall one.
      // 0 sync, 1 language, 2 alerts, 3 contractors, 4 districts, 5 cables, 6 report,
      // 7 data health, 8 local backup
      final columns = switch (per) {
        3 => const [[0, 3], [1, 4, 5, 6], [2, 7, 8]],
        2 => const [[0, 1, 3, 6], [2, 4, 5, 7, 8]],
        _ => const [[0, 1, 2, 3, 4, 5, 6, 7, 8]],
      };
      Widget column(List<int> ids) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < ids.length; i++) ...[if (i > 0) const SizedBox(height: 16), cards[ids[i]]],
          ]);
      return ListView(padding: EdgeInsets.all(phone ? 12 : 16), children: [
        Text(s.t('settings.title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < columns.length; i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: column(columns[i]))],
        ]),
        const SizedBox(height: 20),
        Text(s.t('settings.version', {'version': '1.0.0'}), style: TextStyle(color: C.faint, fontSize: 12)),
      ]);
    });
  }
}

Future<void> exportEverything(BuildContext context) async {
  final app = context.appRead;
  // Building the file can take a moment with thousands of orders: say so first, and let
  // the message draw before the work starts.
  app.showToast(app.s.t('toast.preparingFile'));
  await Future<void>.delayed(const Duration(milliseconds: 60));
  try {
    final wb = app.exportDoc.dataWorkbook(app.data.orders, app.today, riyadhNow());
    final saved = await saveOrShare(workbookXlsx(wb), wb['fileName'] as String);
    if (saved != null && !saved.shared) app.showToast(app.s.t('toast.fileSaved', {'path': saved.path}));
  } catch (e) {
    app.showToast(app.s.t('toast.exportFailed', {'reason': fileErrorReason(e, app.s.t)}), error: true);
  }
}

/// Local backup: the whole data folder (orders, photos, settings) saved as one .zip file the
/// user keeps wherever they like, and restored from it. Separate from the nightly cloud backup.
class _BackupCard extends StatefulWidget {
  const _BackupCard();
  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;

  Future<void> _backupNow() async {
    final app = context.appRead;
    final s = app.s;
    final loc = await fs.getSaveLocation(
      suggestedName: LocalBackup.fileNameFor(DateTime.now()),
      acceptedTypeGroups: [fs.XTypeGroup(label: 'Backup', extensions: const ['zip'])],
    );
    if (loc == null) return;
    var path = loc.path;
    if (!path.toLowerCase().endsWith('.zip')) path = '$path.zip';
    setState(() => _busy = true);
    try {
      final info = await app.backupTo(path);
      await app.prefs.setString('lastLocalBackup', info.createdAt);
      app.showToast(s.t('backup.saved', {'path': path}));
    } catch (e) {
      app.showToast(s.t('toast.exportFailed', {'reason': fileErrorReason(e, s.t)}), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreNow() async {
    final app = context.appRead;
    final s = app.s;
    final picked = await fs.openFile(acceptedTypeGroups: [fs.XTypeGroup(label: 'Backup', extensions: const ['zip'])]);
    if (picked == null) return;
    BackupInfo info;
    try {
      info = await LocalBackup.inspect(picked.path);
    } on BackupException {
      app.showToast(s.t('backup.notBackup'), error: true);
      return;
    }
    if (!mounted) return;
    String when(BackupInfo i) => i.createdAt.length >= 10 ? s.date(i.createdAt.substring(0, 10)) : i.createdAt;
    final ok = await confirmDialog(
      context,
      title: s.t('backup.restoreTitle'),
      body: s.t('backup.restoreBody', {'when': when(info), 'orders': info.orders ?? '–', 'photos': info.photos}),
      confirm: s.t('settings.restoreBackup'),
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final restored = await app.restoreFrom(picked.path);
      app.showToast(s.t('backup.restored', {'orders': restored.orders ?? '–', 'photos': restored.photos}));
    } on BackupException {
      app.showToast(s.t('backup.notBackup'), error: true);
    } catch (e) {
      app.showToast(s.t('toast.exportFailed', {'reason': '$e'}), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final last = app.prefs.getString('lastLocalBackup');
    final lastText = last == null
        ? s.t('settings.noBackupYet')
        : s.t('settings.lastBackup', {'when': last.length >= 10 ? s.date(last.substring(0, 10)) : last});
    return SectionCard(
      title: s.t('settings.backup'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('settings.backupNote'), style: TextStyle(color: C.muted, fontSize: 13)),
        const SizedBox(height: 6),
        Text(lastText, style: TextStyle(color: C.faint, fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : _backupNow,
            icon: const Icon(Icons.save_alt_outlined, size: 18),
            label: Text(s.t('settings.backupNow')),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restoreNow,
            icon: const Icon(Icons.settings_backup_restore_outlined, size: 18),
            label: Text(s.t('settings.restoreBackup')),
          ),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ]),
    );
  }
}

/// Light, dark, or follow Windows / the phone. Kept on this device only.
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return SectionCard(
      title: s.t('settings.appearance'),
      child: SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'system', icon: const Icon(Icons.brightness_auto_outlined, size: 18), label: Text(s.t('theme.system'))),
          ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode_outlined, size: 18), label: Text(s.t('theme.light'))),
          ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode_outlined, size: 18), label: Text(s.t('theme.dark'))),
        ],
        selected: {app.themeMode},
        onSelectionChanged: (v) => app.setThemeMode(v.first),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return SectionCard(
      title: s.t('settings.languageDates'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ar', label: Text('العربية'))],
          selected: {app.lang},
          onSelectionChanged: (v) => app.setLanguage(v.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: app.showHijri,
          onChanged: (v) => _saveSettings(app, app.data.settings.copyWith(showHijri: v)),
          title: Text(s.t('settings.showHijri')),
        ),
      ]),
    );
  }
}

/// Returns true when saved; on failure the reason is shown.
Future<bool> _saveSettings(AppState app, AppSettings next) async {
  try {
    await app.repo.saveSettings(next);
    return true;
  } catch (e) {
    app.showError(e);
    return false;
  }
}

class _AlertsCard extends StatefulWidget {
  const _AlertsCard();
  @override
  State<_AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<_AlertsCard> {
  static const _keys = ['lateStartDays', 'openTrenchDays', 'restorationOverdueDays', 'tasreehEndingDays', 'meterNotOnDays', 'stalledDays'];
  final Map<String, TextEditingController> _ctl = {};

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final defaults = (app.rules['alertDefaults'] as Map).cast<String, dynamic>();
    final cur = app.data.settings.alertOverrides;
    return SectionCard(
      title: s.t('settings.alerts'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('settings.alertsNote'), style: TextStyle(color: C.muted, fontSize: 12.5)),
        const SizedBox(height: 8),
        for (final k in _keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(s.t('settings.alert.$k'))),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _ctl.putIfAbsent(k, () => TextEditingController(text: '${cur[k] ?? defaults[k]}')),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _save(app),
                ),
              ),
              const SizedBox(width: 8),
              Text(s.t('settings.days'), style: TextStyle(color: C.muted)),
            ]),
          ),
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => _save(app), child: Text(s.t('common.save')))),
      ]),
    );
  }

  Future<void> _save(AppState app) async {
    final defaults = (app.rules['alertDefaults'] as Map).cast<String, dynamic>();
    final next = <String, int>{};
    for (final k in _keys) {
      final v = int.tryParse(_ctl[k]?.text ?? '');
      if (v != null && v >= 0 && v <= 365 && v != defaults[k]) next[k] = v;
    }
    // Only say "Saved" when it was (a failure shows its own message).
    if (await _saveSettings(app, app.data.settings.copyWith(alertOverrides: next))) app.showToast(app.s.t('toast.saved'));
  }
}

class _ContractorsCard extends StatelessWidget {
  const _ContractorsCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final list = [for (final c in app.data.contractors) if (!c.deleted) c];
    final open = <String, int>{};
    for (final x in app.evaluated) {
      if (x.ev.status == 'open' || x.ev.status == 'on_hold') open[x.order.contractor ?? ''] = (open[x.order.contractor ?? ''] ?? 0) + 1;
    }
    return SectionCard(
      title: s.t('settings.contractors'),
      trailing: Text(s.t('settings.activeCount', {'count': list.where((c) => c.active).length}), style: TextStyle(color: C.faint, fontSize: 12.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('settings.contractorsNote'), style: TextStyle(color: C.muted, fontSize: 12.5)),
        for (final c in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(c.name, style: TextStyle(color: c.active ? C.ink : C.faint)),
            subtitle: Text([s.t('settings.openCount', {'count': open[c.name] ?? 0}), if (c.phone != null && c.phone!.isNotEmpty) c.phone!, if (!c.active) s.t('settings.inactive')].join(' · ')),
            trailing: IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(context, c)),
          ),
        TextButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add, size: 18), label: Text(s.t('settings.addContractor'))),
      ]),
    );
  }

  Future<void> _add(BuildContext context) async {
    final app = context.appRead;
    final name = await reasonDialog(context, title: app.s.t('settings.addContractor'), confirm: app.s.t('common.add'));
    if (name == null) return;
    try {
      await app.repo.addContractor(name);
    } catch (e) {
      app.showError(e);
    }
  }

  Future<void> _edit(BuildContext context, Contractor c) async {
    final app = context.appRead;
    final r = await showDialog<Contractor>(context: context, builder: (_) => _ContractorDialog(c: c));
    if (r == null) return;
    try {
      await app.repo.updateContractor(r);
      // Orders show contractors by name: rename them too (the database links by id).
      if (r.name != c.name && app.repo.isDemo == false) app.showToast(app.s.t('toast.saved'));
    } catch (e) {
      app.showError(e);
    }
  }
}

class _ContractorDialog extends StatefulWidget {
  const _ContractorDialog({required this.c});
  final Contractor c;
  @override
  State<_ContractorDialog> createState() => _ContractorDialogState();
}

class _ContractorDialogState extends State<_ContractorDialog> {
  late final _name = TextEditingController(text: widget.c.name);
  late final _phone = TextEditingController(text: widget.c.phone ?? '');
  late bool _active = widget.c.active;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.t('settings.editContractor')),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: s.t('settings.name'))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: s.t('settings.phone'))),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: Text(s.t('settings.activeContractor'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common.cancel'))),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, widget.c.copyWith(name: _name.text.trim(), phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(), active: _active)),
          child: Text(s.t('common.save')),
        ),
      ],
    );
  }
}

class _DistrictsCard extends StatelessWidget {
  const _DistrictsCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final list = [for (final d in app.data.districts) if (!d.deleted) d];
    return SectionCard(
      title: s.t('settings.districts'),
      trailing: Mono('${list.length}', color: C.faint),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('settings.districtsNote'), style: TextStyle(color: C.muted, fontSize: 12.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in list)
            ActionChip(
              label: Text(d.name),
              onPressed: () async {
                final name = await reasonDialog(context, title: s.t('settings.renameDistrict'), confirm: s.t('common.save'), initial: d.name);
                if (name == null || name == d.name) return;
                try {
                  await app.repo.renameDistrict(d.id, name);
                } catch (e) {
                  app.showError(e);
                }
              },
            ),
        ]),
        TextButton.icon(
          onPressed: () async {
            final name = await reasonDialog(context, title: s.t('settings.addDistrict'), confirm: s.t('common.add'));
            if (name == null) return;
            try {
              await app.repo.addDistrict(name);
            } catch (e) {
              app.showError(e);
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(s.t('settings.addDistrict')),
        ),
      ]),
    );
  }
}

class _CableCard extends StatelessWidget {
  const _CableCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return SectionCard(
      title: s.t('settings.cableSizes'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('settings.cableNote'), style: TextStyle(color: C.muted, fontSize: 12.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in app.data.cableSizes) InputChip(label: Text('${c.sizeMm2} mm²'), onDeleted: () async {
            await app.repo.removeCableSize(c.id);
            // Nothing is erased: Undo brings the size back.
            app.showToast(s.t('toast.cableSizeRemoved', {'size': c.sizeMm2}), onUndo: () => app.repo.addCableSize(c.sizeMm2));
          }),
        ]),
        TextButton.icon(
          onPressed: () async {
            final v = await reasonDialog(context, title: s.t('settings.addCableSize'), confirm: s.t('common.add'));
            final n = int.tryParse(v ?? '');
            if (n == null || n <= 0) return;
            await app.repo.addCableSize(n);
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(s.t('settings.addCableSize')),
        ),
      ]),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return SectionCard(
      title: s.t('settings.reports'),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(s.t('settings.preparedBy')),
        subtitle: Text(app.data.settings.preparedBy),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () async {
          final v = await reasonDialog(context, title: s.t('settings.preparedBy'), confirm: s.t('common.save'), initial: app.data.settings.preparedBy);
          if (v == null) return;
          if (await _saveSettings(app, app.data.settings.copyWith(preparedBy: v))) app.showToast(s.t('toast.saved'));
        },
      ),
    );
  }
}

class _SyncCard extends StatefulWidget {
  const _SyncCard();
  @override
  State<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<_SyncCard> {
  // Made when the card opens (not on first use: otherwise leaving Settings without opening
  // Cloud setup would create them while the screen is closing).
  late final TextEditingController _url, _key, _ps;

  @override
  void initState() {
    super.initState();
    final prefs = context.appRead.prefs;
    _url = TextEditingController(text: prefs.getString('supabaseUrl') ?? '');
    _key = TextEditingController(text: prefs.getString('supabaseAnonKey') ?? '');
    _ps = TextEditingController(text: prefs.getString('powersyncUrl') ?? '');
  }
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showSetup = false;

  @override
  void dispose() {
    for (final c in [_url, _key, _ps, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _do(Future<void> Function() f) async {
    final app = context.appRead; // read before waiting: the card may be gone after
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      app.showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final sy = app.sync;
    final status = app.repo.isDemo
        ? s.t('sync.badge.demo.tip', {'count': 0})
        : !sy.configured
            ? s.t('sync.notConfigured')
            : !sy.signedIn
                ? s.t('sync.signedOut')
                : sy.connected
                    ? s.t('sync.connectedAs', {'email': sy.userEmail ?? ''})
                    : s.t('sync.offlineAs', {'email': sy.userEmail ?? ''});
    return SectionCard(
      title: s.t('settings.sync'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(status, style: TextStyle(color: C.muted)),
        if (sy.lastSyncedAt != null)
          Text(s.t('data.syncedAgo', {'when': _ago(app, sy.lastSyncedAt!)}), style: TextStyle(color: C.faint, fontSize: 12.5)),
        if (sy.pendingChanges > 0) Text(s.t('toast.waitingSync', {'count': sy.pendingChanges}), style: TextStyle(color: C.warning, fontSize: 12.5)),
        const SizedBox(height: 10),
        if (sy.configured && !sy.signedIn && !app.repo.isDemo) ...[
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: s.t('sync.email'))),
          const SizedBox(height: 8),
          TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: s.t('sync.password'))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _busy ? null : () => _do(() => app.repo.signIn(_email.text, _password.text)), child: Text(s.t('sync.signIn'))),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _do(() async {
                        final signedIn = await app.repo.signUp(_email.text, _password.text);
                        if (!signedIn) app.showToast(s.t('sync.confirmEmail', {'email': _email.text.trim()}));
                      }),
              child: Text(s.t('sync.createAccount')),
            ),
          ]),
        ],
        if (sy.signedIn)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(onPressed: _busy ? null : () => _do(app.repo.signOut), child: Text(s.t('sync.signOut'))),
          ),
        const SizedBox(height: 6),
        TextButton(onPressed: () => setState(() => _showSetup = !_showSetup), child: Text(s.t(_showSetup ? 'sync.hideSetup' : 'sync.showSetup'))),
        if (_showSetup) ...[
          Text(s.t('sync.setupNote'), style: TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          TextField(controller: _url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Supabase URL', hintText: 'https://xxxx.supabase.co')),
          const SizedBox(height: 8),
          TextField(controller: _key, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Supabase anon key')),
          const SizedBox(height: 8),
          TextField(controller: _ps, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'PowerSync URL', hintText: 'https://xxxx.powersync.journeyapps.com')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              await app.saveSyncConfig(SyncConfig(supabaseUrl: _url.text, anonKey: _key.text, powersyncUrl: _ps.text));
              if (supabaseStarted) {
                // Supabase can only be pointed at a new address on the next start.
                app.showToast(s.t('sync.restartNeeded'));
              } else {
                // First time: connect now, no restart needed.
                await app.reopen();
                if (mounted) setState(() => _showSetup = false);
                app.showToast(s.t('toast.saved'));
              }
            },
            child: Text(s.t('common.save')),
          ),
        ],
      ]),
    );
  }
}

String _ago(AppState app, DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return app.s.t('time.justNow');
  if (d.inMinutes < 60) return app.s.t('time.minutesAgo', {'count': d.inMinutes});
  if (d.inHours < 24) return app.s.t('time.hoursAgo', {'count': d.inHours});
  return app.s.t('time.daysAgo', {'count': d.inDays});
}

String agoText(AppState app, DateTime t) => _ago(app, t);
