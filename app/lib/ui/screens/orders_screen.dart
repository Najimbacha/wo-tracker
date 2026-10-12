// All orders: search, filters, saved views, and bulk work on a selection
// (mark a step done on many orders at once, or export them to Excel).
import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../domain/insights.dart';
import '../../domain/order_input.dart';
import '../../report/files.dart';
import '../../report/xlsx_writer.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _query = TextEditingController();
  Set<String> _status = {'open', 'on_hold'};
  Set<String> _quick = {};
  Set<String> _types = {};
  Set<String> _categories = {};
  String? _contractor;
  Set<String> _surfaces = {};
  Set<String> _tasreeh = {};
  String _received = 'any'; // any | today | this_week | this_month | last_month
  String? _stepKey;
  String _stepState = 'not_done';
  final Set<String> _selected = {};
  String? _title;
  bool _showFilters = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.appRead;
    final f = app.ordersFilter;
    if (f != null) {
      _apply(f);
      _title = app.ordersFilterTitle;
      app.ordersFilter = null;
      app.ordersFilterTitle = null;
    }
  }

  void _apply(FilterCriteria f) {
    _status = {...?f.status};
    _quick = {...f.quick};
    _types = {...?f.types};
    _categories = {...?f.categories};
    _contractor = (f.contractors == null || f.contractors!.isEmpty) ? null : f.contractors!.first;
    _surfaces = {...?f.surfaces};
    _tasreeh = {...?f.tasreeh};
    _stepKey = f.steps.isEmpty ? null : f.steps.first.step;
    _stepState = f.steps.isEmpty ? 'not_done' : f.steps.first.state;
    _received = 'any';
    _selected.clear();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void update(VoidCallback f) => setState(f);

  FilterCriteria _criteria(String today) {
    DateRange? range;
    switch (_received) {
      case 'today':
        range = DateRange(today, today);
      case 'this_week':
        range = Insights.weekRange(today);
      case 'this_month':
        range = Insights.monthRange(today);
      case 'last_month':
        final m = Insights.monthRange(today);
        final p = DateTime.parse('${m.from}T00:00:00Z').subtract(const Duration(days: 1));
        range = Insights.monthRange('${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
    }
    return FilterCriteria(
      status: _status.isEmpty ? null : _status.toList(),
      quick: _quick.toList(),
      types: _types.isEmpty ? null : _types.toList(),
      categories: _categories.isEmpty ? null : _categories.toList(),
      contractors: _contractor == null ? null : [_contractor!],
      surfaces: _surfaces.isEmpty ? null : _surfaces.toList(),
      tasreeh: _tasreeh.isEmpty ? null : _tasreeh.toList(),
      receivedFrom: range?.from,
      receivedTo: range?.to,
      steps: _stepKey == null ? const [] : [StepCondition(_stepKey!, _stepState)],
    );
  }

  Map<String, dynamic> _toJson() => {
        'status': _status.toList(),
        'quick': _quick.toList(),
        'types': _types.toList(),
        'categories': _categories.toList(),
        if (_contractor != null) 'contractors': [_contractor],
        'surfaces': _surfaces.toList(),
        'tasreeh': _tasreeh.toList(),
        if (_stepKey != null) 'steps': [
          {'step': _stepKey, 'state': _stepState}
        ],
        'receivedPreset': _received,
      };

  void _fromJson(Map<String, dynamic> j) {
    _apply(FilterCriteria.fromJson(j));
    _received = j['receivedPreset'] as String? ?? 'any';
  }

  bool _matches(OrderInput o, String q) {
    if (q.isEmpty) return true;
    final n = Insights.normalizeText(q);
    final hay = [
      o.woNumber,
      o.district,
      o.street,
      o.contractor,
      o.networkRef,
      o.notes,
      for (final p in o.permits) p.number,
      for (final m in o.meters) m.number,
      for (final m in o.meters) m.oldNumber,
    ].whereType<String>().map(Insights.normalizeText);
    return hay.any((h) => h.contains(n));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    if (!app.data.loaded) return const DelayedLoader();
    final crit = _criteria(app.today);
    final ids = app.insights.filterOrders(app.orders, app.today, crit, alertSettings: app.alertSettings);
    final q = _query.text.trim();
    final rows = [for (final id in ids) if (app.orderById(id) != null && _matches(app.orderById(id)!, q)) app.orderById(id)!];
    _selected.removeWhere((id) => !rows.any((o) => o.id == id));
    final phone = isPhone(context);
    final wide = isWide(context);
    // Contractor, date, progress and status beside each order, when there is room.
    final roomForFacts = MediaQuery.sizeOf(context).width - (wide ? 300 : 0) >= 820;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(phone ? 14 : 24, 18, phone ? 14 : 24, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(_title ?? s.t('nav.allOrders'), style: Theme.of(context).textTheme.titleLarge)),
          Text(s.t('filter.matches', {'count': rows.length}), style: const TextStyle(color: C.muted)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.t('search.hint'),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(_query.clear)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!wide)
            phone
                ? IconButton(tooltip: s.t('filter.title'), isSelected: _showFilters, onPressed: () => setState(() => _showFilters = !_showFilters), icon: const Icon(Icons.tune))
                : OutlinedButton.icon(
                    onPressed: () => setState(() => _showFilters = !_showFilters),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(s.t('filter.title')),
                  ),
          if (rows.isNotEmpty) ...[
            const SizedBox(width: 8),
            phone
                ? IconButton(tooltip: s.t('common.export'), onPressed: () => _export(context, rows), icon: const Icon(Icons.download))
                : OutlinedButton.icon(onPressed: () => _export(context, rows), icon: const Icon(Icons.download, size: 18), label: Text(s.t('common.export'))),
          ],
        ]),
        const SizedBox(height: 8),
        _ViewsRow(
          views: app.data.views,
          onPick: (v) => setState(() {
            _fromJson(v.filter);
            _title = v.name;
          }),
          onSave: () => _saveView(context),
          onDelete: (v) async {
            final ok = await confirmDialog(context,
                title: s.t('filter.deleteViewTitle', {'name': v.name}), confirm: s.t('common.delete'), danger: true);
            if (!ok) return;
            try {
              await app.repo.deleteView(v.id);
            } catch (e) {
              app.showError(e);
            }
          },
        ),
      ]),
    );

    final filters = _Filters(state: this);
    final list = rows.isEmpty
        ? EmptyState(
            icon: Icons.search_off,
            title: q.isEmpty ? s.t('filter.noMatches') : s.t('empty.noResults', {'query': q}),
            action: TextButton(
              onPressed: () => setState(() {
                _apply(const FilterCriteria());
                _received = 'any';
                _status = {};
                _query.clear();
                _title = null;
              }),
              child: Text(s.t('empty.searchEverything')),
            ),
          )
        : ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final o = rows[i];
              final sel = _selected.contains(o.id);
              return Row(children: [
                Checkbox(
                  value: sel,
                  onChanged: (v) => setState(() => v == true ? _selected.add(o.id!) : _selected.remove(o.id)),
                ),
                Expanded(
                  child: OrderTile(
                    order: o,
                    selected: sel,
                    onTap: () => openOrder(context, o.id),
                    trailing: roomForFacts ? _RowFacts(order: o) : null,
                  ),
                ),
              ]);
            },
          );

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      if (_selected.isNotEmpty) _BulkBar(count: _selected.length, onMark: () => _bulkMark(context, rows), onExport: () => _export(context, rows.where((o) => _selected.contains(o.id)).toList()), onClear: () => setState(_selected.clear)),
      if (!wide && _showFilters) SizedBox(height: 320, child: filters),
      Expanded(child: list),
    ]);
    if (!wide) return body;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 300, child: DecoratedBox(decoration: const BoxDecoration(color: C.card, border: BorderDirectional(end: BorderSide(color: C.line))), child: filters)),
      Expanded(child: body),
    ]);
  }

  Future<void> _saveView(BuildContext context) async {
    final app = context.appRead;
    final name = await reasonDialog(context, title: app.s.t('filter.saveViewTitle'), confirm: app.s.t('common.save'), initial: _title);
    if (name == null) return;
    try {
      await app.repo.saveView(SavedView(id: app.repo.newId(), name: name, filter: _toJson(), sortOrder: app.data.views.length));
      app.showToast(app.s.t('toast.viewSaved', {'name': name}));
    } catch (e) {
      app.showError(e);
    }
  }

  Future<void> _export(BuildContext context, List<OrderInput> orders) async {
    final app = context.appRead;
    app.showToast(app.s.t('toast.preparingFile'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    try {
      final wb = app.exportDoc.dataWorkbook(orders, app.today, riyadhNowText());
      final bytes = workbookXlsx(wb);
      final saved = await saveOrShare(bytes, wb['fileName'] as String);
      if (saved != null && !saved.shared) app.showToast(app.s.t('toast.fileSaved', {'path': saved.path}));
    } catch (e) {
      app.showToast(app.s.t('toast.exportFailed', {'reason': fileErrorReason(e, app.s.t)}), error: true);
    }
  }

  Future<void> _bulkMark(BuildContext context, List<OrderInput> rows) async {
    final app = context.appRead;
    final chosen = rows.where((o) => _selected.contains(o.id)).toList();
    final keys = <String>{};
    for (final o in chosen) {
      for (final st in app.evaluate(o).steps) {
        if (!st.closed) keys.add(st.step.key);
      }
    }
    if (keys.isEmpty) return;
    final ordered = (app.rules['steps'] as Map).keys.cast<String>().where(keys.contains).toList();
    final key = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(app.s.t('bulk.pickStep', {'count': chosen.length})),
        children: [for (final k in ordered) SimpleDialogOption(onPressed: () => Navigator.pop(c, k), child: Text(app.s.step(k)))],
      ),
    );
    if (key == null || !context.mounted) return;
    final date = await pickDate(context, help: app.s.step(key));
    if (date == null || !mounted) return;
    final r = app.actions.bulkMarkDone(chosen, key, date, app.today);
    final changes = <OrderChange>[];
    for (var i = 0; i < chosen.length; i++) {
      if (!identical(chosen[i], r.orders[i])) changes.add(OrderChange(chosen[i], r.orders[i]));
    }
    if (changes.isNotEmpty) {
      await app.save(changes, toast: 'toast.bulkDone', toastParams: {'done': r.updated.length, 'skipped': r.skipped.length});
    } else {
      app.showToast(app.s.t('toast.bulkDone', {'done': 0, 'skipped': r.skipped.length}), error: true);
    }
    if (r.skipped.isNotEmpty && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(app.s.t('bulk.skippedTitle', {'count': r.skipped.length})),
          content: SizedBox(
            width: 460,
            child: ListView(shrinkWrap: true, children: [
              for (final sk in r.skipped)
                ListTile(
                  dense: true,
                  title: Mono(app.orderById(sk.id)?.woNumber ?? ''),
                  subtitle: Text(sk.errors.map(app.s.error).join(' ')),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(app.s.t('common.close')))],
        ),
      );
    }
    if (mounted) setState(_selected.clear);
  }
}

String riyadhNowText() {
  final t = DateTime.now().toUtc().add(const Duration(hours: 3));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class _RowFacts extends StatelessWidget {
  const _RowFacts({required this.order});
  final OrderInput order;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final ev = app.evaluate(order);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 150, child: Text(order.contractor ?? app.s.t('common.unassigned'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12.5))),
      SizedBox(width: 70, child: Text(order.receivedDate == null ? '' : app.dateShort(order.receivedDate!), style: const TextStyle(color: C.muted, fontSize: 12.5))),
      SizedBox(width: 120, child: ProgressLine(ev.closed, ev.total)),
      const SizedBox(width: 8),
      StatusChip(ev.status),
    ]);
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({required this.count, required this.onMark, required this.onExport, required this.onClear});
  final int count;
  final VoidCallback onMark, onExport, onClear;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(8)),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(context.t('common.selected', {'count': count}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          FilledButton(onPressed: onMark, child: Text(context.t('bulk.markStep'))),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: C.muted)),
            onPressed: onExport,
            child: Text(context.t('bulk.exportSelected')),
          ),
          TextButton(onPressed: onClear, child: Text(context.t('common.clearAll'), style: const TextStyle(color: Color(0xFFC4C9C3)))),
        ]),
      );
}

class _ViewsRow extends StatelessWidget {
  const _ViewsRow({required this.views, required this.onPick, required this.onSave, required this.onDelete});
  final List<SavedView> views;
  final ValueChanged<SavedView> onPick;
  final VoidCallback onSave;
  final ValueChanged<SavedView> onDelete;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final v in views)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: InputChip(label: Text(v.name), onPressed: () => onPick(v), onDeleted: () => onDelete(v)),
            ),
          TextButton.icon(onPressed: onSave, icon: const Icon(Icons.bookmark_add_outlined, size: 18), label: Text(context.t('common.saveView'))),
        ]),
      );
}

/// The filter panel. Changes apply at once (the count updates as you click).
class _Filters extends StatelessWidget {
  const _Filters({required this.state});
  final _OrdersScreenState state;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final st = state;
    void upd(VoidCallback f) => st.update(() {
          f();
          st._selected.clear();
          st._title = null;
        });
    Widget chips(String title, List<String> values, Set<String> set, String Function(String) label) => _FSection(
          title: title,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in values)
              FilterChip(
                label: Text(label(v)),
                selected: set.contains(v),
                onSelected: (on) => upd(() => on ? set.add(v) : set.remove(v)),
              ),
          ]),
        );
    final stepKeys = (app.rules['steps'] as Map).keys.cast<String>().toList();
    final contractors = [for (final c in app.data.contractors) if (!c.deleted) c.name];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
      Row(children: [
        Expanded(child: Text(s.t('filter.title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        TextButton(
          onPressed: () => upd(() {
            st._apply(const FilterCriteria());
            st._status = {'open', 'on_hold'};
          }),
          child: Text(s.t('common.clearAll')),
        ),
      ]),
      chips(s.t('filter.quickTitle'), const ['needs_attention', 'late_start', 'tasreeh_ending', 'expired', 'emergency', 'on_hold', 'received_today'], st._quick,
          (v) => s.t('filter.quick.$v')),
      chips(s.t('order.status'), const ['open', 'on_hold', 'completed', 'cancelled', 'merged'], st._status, s.status),
      _FSection(
        title: s.t('filter.step'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String?>(
            key: ValueKey('step-${st._stepKey}'),
            initialValue: st._stepKey,
            isExpanded: true,
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(s.t('filter.anyStep'))),
              for (final k in stepKeys) DropdownMenuItem<String?>(value: k, child: Text(s.step(k))),
            ],
            onChanged: (v) => upd(() => st._stepKey = v),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final v in const ['done', 'not_done', 'ready']) ButtonSegment(value: v, label: Text(s.t('filter.stepState.$v'))),
            ],
            selected: {st._stepState},
            onSelectionChanged: st._stepKey == null ? null : (v) => upd(() => st._stepState = v.first),
          ),
        ]),
      ),
      _FSection(
        title: s.t('order.contractor'),
        child: DropdownButtonFormField<String?>(
          key: ValueKey('con-${st._contractor}'),
          initialValue: st._contractor,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(s.t('filter.all'))),
            DropdownMenuItem<String?>(value: unassignedContractor, child: Text(s.t('common.unassigned'))),
            for (final c in contractors) DropdownMenuItem<String?>(value: c, child: Text(c)),
            // A saved view may name a contractor renamed or removed since.
            if (st._contractor != null && st._contractor != unassignedContractor && !contractors.contains(st._contractor))
              DropdownMenuItem<String?>(value: st._contractor, child: Text(st._contractor!)),
          ],
          onChanged: (v) => upd(() => st._contractor = v),
        ),
      ),
      chips(s.t('filter.surface'), const ['soil', 'asphalt_40', 'asphalt_80', 'tiled', 'no_digging'], st._surfaces, (v) => s.t('filter.surface.$v')),
      chips(s.t('order.type'), (app.rules['types'] as Map).keys.cast<String>().toList(), st._types, (v) => v),
      chips(s.t('order.category'), const ['extension', 'emergency'], st._categories, s.category),
      chips(s.t('tasreeh.title'), const ['none', 'future', 'active', 'ending', 'expired', 'not_needed'], st._tasreeh, (v) => s.t('tasreeh.state.$v')),
      _FSection(
        title: s.t('order.received'),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in const ['any', 'today', 'this_week', 'this_month', 'last_month'])
            ChoiceChip(label: Text(v == 'any' ? s.t('filter.anyTime') : s.t('filter.received.$v')), selected: st._received == v, onSelected: (_) => upd(() => st._received = v)),
        ]),
      ),
    ]);
  }
}

class _FSection extends StatelessWidget {
  const _FSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}
