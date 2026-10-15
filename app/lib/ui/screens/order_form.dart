// New work order (typed from the SEC PDF) and Edit work order. Only the parts that
// apply to the chosen type are shown. Leaving with unsaved changes asks first.
import 'package:flutter/material.dart' hide Actions;
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../data/repository.dart';
import '../../domain/actions.dart';
import '../../domain/order_input.dart';
import '../../domain/rules_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../nav.dart';
import '../widgets/dialogs.dart';

class OrderFormPage extends StatefulWidget {
  const OrderFormPage({super.key, this.editing});
  final OrderInput? editing;
  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
}

class _SegDraft {
  _SegDraft({required this.id, this.base = 'asphalt', this.width = 40, this.length = '', this.tiled = false});
  final String id;
  String base;
  int width;
  String length;
  bool tiled;
}

/// Puts the same gap between cards.
List<Widget> _gapped(List<Widget> items) => [for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 14), items[i]]];

/// The types used almost every time (the picker shows these first).
const _commonTypes = ['401', '402', '801', '802'];

class _MeterDraft {
  _MeterDraft({required this.id, this.number = '', this.oldNumber = '', this.type, this.amps = ''});
  final String id;
  String number, oldNumber, amps;
  String? type;
}

class _CableDraft {
  _CableDraft({this.id, this.size, this.voltage = 'LV', this.length = ''});
  final String? id;
  int? size;
  String voltage;
  String length;
}

class _OrderFormPageState extends State<OrderFormPage> {
  late final bool _isNew = widget.editing == null;
  late String _category = widget.editing?.category ?? 'extension';
  late String _type = widget.editing?.type ?? (context.appRead.prefs.getString('lastType') ?? '402');
  late final _number = TextEditingController(text: widget.editing?.woNumber ?? '');
  late String? _received = widget.editing?.receivedDate ?? context.appRead.today;
  late bool _excavation = widget.editing?.needsExcavation ?? false;
  late final _district = TextEditingController(text: widget.editing?.district ?? '');
  late final _street = TextEditingController(text: widget.editing?.street ?? '');
  late String? _contractor = widget.editing?.contractor ?? (_isNew ? context.appRead.prefs.getString('lastContractor') : null);
  late final _network = TextEditingController(text: widget.editing?.networkRef ?? '');
  late final _notes = TextEditingController(text: widget.editing?.notes ?? '');
  late final List<_SegDraft> _segs = [
    for (final s in widget.editing?.segments ?? const <Segment>[])
      _SegDraft(id: s.id, base: s.base, width: s.width, length: _numText(s.lengthM), tiled: s.tiled),
  ];
  late final List<_MeterDraft> _meters = [
    for (final m in widget.editing?.meters ?? const <Meter>[])
      _MeterDraft(id: m.id, number: m.number ?? '', oldNumber: m.oldNumber ?? '', type: m.meterType, amps: m.breakerAmps?.toString() ?? ''),
  ];
  late final _meterCount = TextEditingController(text: '${_meters.isEmpty ? 1 : _meters.length}');
  late final List<_CableDraft> _cables = [
    for (final c in widget.editing?.cableRuns ?? const <CableRun>[]) _CableDraft(id: c.id, size: c.sizeMm2, voltage: c.voltage, length: c.lengthM == null ? '' : _numText(c.lengthM!)),
  ];
  List<Reason> _errors = [];
  bool _saving = false;
  bool _dirty = false;
  bool _showErrors = false;
  final _numberFocus = FocusNode();

  /// Breaker amps: a whole number above 0, otherwise left empty (the database refuses 0).
  static int? _amps(String t) {
    final v = int.tryParse(t.trim());
    return v == null || v <= 0 ? null : v;
  }

  static String _numText(double v) => v == v.truncateToDouble() ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    for (final c in [_number, _district, _street, _network, _notes, _meterCount]) {
      c.dispose();
    }
    _numberFocus.dispose();
    super.dispose();
  }

  /// "How many meters": adds blank meter rows, or removes empty rows from the end.
  /// A row that already has details is never removed here (nothing typed is lost).
  void _setMeterCount(int n) {
    final app = context.appRead;
    n = n.clamp(1, 50);
    setState(() {
      while (_meters.length < n) {
        _meters.add(_MeterDraft(id: app.repo.newId()));
      }
      while (_meters.length > n) {
        final m = _meters.last;
        if (m.number.trim().isNotEmpty || m.oldNumber.trim().isNotEmpty || m.type != null || m.amps.trim().isNotEmpty) {
          app.showToast(app.s.t('order.meterCountKept'));
          break;
        }
        _meters.removeLast();
      }
      _dirty = true;
    });
    _showMeterCount();
  }

  /// Keeps the count box equal to the number of rows (after Add meter / remove).
  void _showMeterCount() {
    final t = '${_meters.length}';
    if (_meterCount.text != t) _meterCount.text = t;
  }

  void _touch() => setState(() => _dirty = true);

  Actions get _actions => context.appRead.actions;

  OrderInput _draft() {
    final base = widget.editing;
    double len(String t) => double.tryParse(t.replaceAll(',', '.').trim()) ?? 0;
    // Only the parts the chosen type uses are kept (switching type hides the others).
    final spec = _spec;
    final draft = OrderInput(
      id: base?.id,
      type: _type,
      category: _category,
      woNumber: _number.text,
      receivedDate: _received,
      needsExcavation: _excavation,
      segments: [for (final g in _segs) if (spec.segments) Segment(id: g.id, base: g.base, width: g.width, lengthM: len(g.length), tiled: g.tiled)],
      meters: [
        for (final m in _meters)
          if (spec.meters) Meter(m.id,
              number: m.number.trim().isEmpty ? null : m.number.trim(),
              oldNumber: m.oldNumber.trim().isEmpty ? null : m.oldNumber.trim(),
              meterType: m.type,
              breakerAmps: _amps(m.amps)),
      ],
      cableRuns: [
        for (final c in _cables)
          if (spec.cableRuns && c.size != null) CableRun(id: c.id, sizeMm2: c.size!, voltage: c.voltage, lengthM: c.length.trim().isEmpty ? null : len(c.length)),
      ],
      permits: base?.permits ?? const [],
      steps: base?.steps ?? const {},
      state: base?.state ?? 'open',
      stateReason: base?.stateReason,
      stateDate: base?.stateDate,
      mergedInto: base?.mergedInto,
      holdPeriods: base?.holdPeriods ?? const [],
      lastChangeDate: base?.lastChangeDate ?? _received,
      contractor: (_contractor == null || _contractor!.trim().isEmpty) ? null : _contractor!.trim(),
      district: _district.text.trim().isEmpty ? null : _district.text.trim(),
      street: _street.text.trim().isEmpty ? null : _street.text.trim(),
      networkRef: _network.text.trim().isEmpty ? null : _network.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      deleted: base?.deleted ?? false,
      deletedReason: base?.deletedReason,
    );
    return Actions.normalizeDraft(draft, rules: context.appRead.rules);
  }

  void _pickType(String t) => setState(() {
        _type = t;
        _dirty = true;
        if (!_actions.formSpec(OrderInput(type: t, category: _category)).excavationSwitch) _excavation = false;
      });

  FormSpec get _spec => _actions.formSpec(OrderInput(type: _type, category: _category, needsExcavation: _excavation));

  /// Every type with meters starts with one meter row, so its steps have a home.
  void _ensureMeter() {
    if (_spec.meters && _meters.isEmpty) _meters.add(_MeterDraft(id: context.appRead.repo.newId()));
  }

  Future<bool> _save({bool next = false}) async {
    if (_saving) return false; // Ctrl+S pressed twice
    final app = context.appRead;
    _ensureMeter();
    final draft = _draft();
    final others = app.data.orders.where((o) => o.id != draft.id).toList();
    final errors = _actions.validateDraft(draft, others, app.today);
    // A cancelled or merged order can't be received after the day it was cancelled/merged.
    if (draft.stateDate != null && draft.receivedDate != null && toDay(draft.receivedDate!) > toDay(draft.stateDate!)) {
      errors.add(Reason('received_after_state', date: draft.stateDate));
    }
    // Segment lengths and cable lengths must be numbers above 0.
    for (final c in _spec.cableRuns ? _cables : const <_CableDraft>[]) {
      // The length may be left empty (not measured yet); a typed length must be above 0.
      final typed = c.length.trim();
      if (c.size == null || (typed.isNotEmpty && (double.tryParse(typed.replaceAll(',', '.')) ?? 0) <= 0)) {
        errors.add(const Reason('bad_cable_run'));
        break;
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _showErrors = true;
      });
      return false;
    }
    if (!_isNew) {
      final impact = _actions.editImpact(widget.editing!, draft);
      if (impact.isNotEmpty) {
        final names = impact.map((id) => app.s.step(id.split('@').first)).toSet().toList();
        final ok = await confirmDialog(context, title: app.s.t('confirm.editImpactTitle'), body: app.s.t('confirm.editImpact', {'steps': names}), confirm: app.s.t('common.save'));
        if (!ok || !mounted) return false;
      }
    }
    setState(() => _saving = true);
    final after = draft.id == null ? draft.copyWith(id: app.repo.newId()) : draft;
    final ok = await app.save([OrderChange(widget.editing, after)], toast: _isNew ? 'order.created' : 'toast.saved');
    if (!mounted) return ok;
    setState(() => _saving = false);
    if (!ok) return false;
    // Only a new order sets the defaults for the next one (editing an old order must not).
    if (_isNew) {
      await app.prefs.setString('lastType', _type);
      if (_contractor != null) await app.prefs.setString('lastContractor', _contractor!);
    }
    if (!mounted) return true;
    if (next) {
      setState(() {
        _number.clear();
        _street.clear();
        _network.clear();
        _notes.clear();
        _segs.clear();
        _meters.clear();
        _meterCount.text = '1';
        _cables.clear();
        _errors = [];
        _showErrors = false;
        _dirty = false;
      });
      // Ready for the next order: the cursor goes back to the work order number.
      _numberFocus.requestFocus();
    } else {
      _dirty = false;
      Navigator.of(context).pop();
    }
    return true;
  }

  String? _fieldError(List<String> codes) {
    if (!_showErrors) return null;
    for (final e in _errors) {
      if (codes.contains(e.code)) return context.s.error(e);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final spec = _spec;
    final phone = isPhone(context);
    final dup = _number.text.trim().isEmpty ? null : Actions.findDuplicate(app.data.orders, _number.text, exceptId: widget.editing?.id);
    final pattern = RegExp(spec.woNumberPattern ?? '.*');
    final numberOk = _number.text.trim().isEmpty || pattern.hasMatch(Actions.normalizeDraft(OrderInput(type: _type, category: _category, woNumber: _number.text)).woNumber ?? '');
    final todayAdded = app.data.orders.where((o) => o.receivedDate == app.today && !o.deleted).length;

    final left = <Widget>[
      SectionCard(
        title: s.t('order.sectionOrder'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'extension', label: Text(s.t('category.extensionLong'))),
                ButtonSegment(value: 'emergency', label: Text(s.t('category.emergencyLong'))),
              ],
              selected: {_category},
              onSelectionChanged: (v) => setState(() {
                _category = v.first;
                _dirty = true;
              }),
            ),
          ),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _number,
                focusNode: _numberFocus,
                autofocus: _isNew,
                textDirection: TextDirection.ltr,
                // The number is what you type from the SEC paper: big, so it can be checked at a glance.
                style: monoStyle.copyWith(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: 2),
                onChanged: (_) => _touch(),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  labelStyle: const TextStyle(fontSize: 16),
                  labelText: s.t('order.woNumber'),
                  helperText: dup == null && numberOk ? s.t(_category == 'extension' ? 'order.woHintExtension' : 'order.woHintEmergency') : null,
                  errorText: dup != null
                      ? s.t(dup.deleted ? 'error.duplicate_wo_deleted' : 'error.duplicate_wo', {'date': dup.receivedDate == null ? '' : app.dateShort(dup.receivedDate!), 'district': dup.district ?? ''})
                      : (!numberOk ? s.t('error.bad_wo_number') : _fieldError(['wo_number_required', 'bad_wo_number'])),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: DateField(
                label: s.t('order.received'),
                value: _received,
                onChanged: (v) => setState(() {
                  _received = v;
                  _dirty = true;
                }),
                errorText: _fieldError(['received_required', 'future_date', 'received_after_state']),
              ),
            ),
          ]),
        ]),
      ),
      if (dup != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              final d = app.orderById(dup.id);
              if (d != null) {
                if (d.deleted) {
                  app.apply(d, app.actions.restoreOrder(d, app.data.orders), toast: 'toast.restored');
                }
                app.go('today');
                final nav = app.navigatorKey.currentContext;
                if (nav != null) openOrder(nav, d.id);
              }
            },
            child: Text(dup.deleted ? s.t('action.restoreInstead') : s.t('order.openExisting')),
          ),
        ),
      SectionCard(
        title: s.t('order.type'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The four types used almost every time are big tiles; the rest are small chips.
          LayoutBuilder(builder: (context, box) {
            final per = box.maxWidth >= 560 ? 4 : 2;
            final types = app.rules['types'] as Map;
            final common = _commonTypes.where(types.containsKey).toList();
            // Rows of equal-width, equal-height tiles (a two-line name does not make one tile taller).
            return Column(children: [
              for (var r = 0; r < common.length; r += per)
                Padding(
                  padding: EdgeInsets.only(top: r == 0 ? 0 : 10),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var c = 0; c < per; c++) ...[
                        if (c > 0) const SizedBox(width: 10),
                        Expanded(
                          child: r + c < common.length
                              ? _TypeButton(code: common[r + c], label: s.type(common[r + c]), selected: _type == common[r + c], onTap: () => _pickType(common[r + c]))
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ]),
                  ),
                ),
            ]);
          }),
          if ((app.rules['types'] as Map).keys.any((t) => !_commonTypes.contains(t))) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(s.t('order.typesRare'), style: const TextStyle(fontSize: 12.5, color: C.faint)),
              for (final t in (app.rules['types'] as Map).keys.cast<String>().where((t) => !_commonTypes.contains(t)))
                Tooltip(
                  message: s.type(t),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                    label: SizedBox(width: 34, child: Center(child: Mono(t, size: 13, color: _type == t ? typeColors(t).$2 : C.ink))),
                    selected: _type == t,
                    selectedColor: C.accentSoft,
                    onSelected: (_) => _pickType(t),
                  ),
                ),
            ]),
            if (!_commonTypes.contains(_type))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('$_type · ${s.type(_type)}', style: const TextStyle(fontSize: 13, color: C.accentDark, fontWeight: FontWeight.w500)),
              ),
          ],
          if (spec.excavationSwitch)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _excavation,
              onChanged: (v) => setState(() {
                _excavation = v;
                _dirty = true;
              }),
              title: Text(s.t('order.needsExcavation')),
              subtitle: Text(s.t('order.needsExcavationHint')),
            ),
        ]),
      ),
      SectionCard(
        title: s.t('order.sectionPlace'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _Suggest(
                controller: _district,
                label: s.t('order.district'),
                options: [for (final d in app.data.districts) if (!d.deleted) d.name],
                onChanged: _touch,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(controller: _street, onChanged: (_) => _touch(), decoration: InputDecoration(labelText: s.t('order.street'))),
            ),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: _contractor,
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(labelText: s.t('order.contractor')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(s.t('common.unassigned'))),
                    for (final c in app.data.contractors)
                      if (!c.deleted && (c.active || c.name == _contractor)) DropdownMenuItem<String?>(value: c.name, child: Text(c.name)),
                    // The order's contractor may have been removed since: keep it selectable,
                    // or the list would have no item for the current value.
                    if (_contractor != null && !app.data.contractors.any((c) => !c.deleted && c.name == _contractor))
                      DropdownMenuItem<String?>(value: _contractor, child: Text(_contractor!)),
                  ],
                  onChanged: (v) => setState(() {
                    _contractor = v;
                    _dirty = true;
                  }),
                ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _network,
                onChanged: (_) => _touch(),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t('order.network'), hintText: s.t('order.networkHint')),
              ),
            ),
          ]),
        ]),
      ),
      SectionCard(
        title: s.t('order.notes'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: TextField(controller: _notes, onChanged: (_) => _touch(), minLines: 2, maxLines: 5, decoration: InputDecoration(hintText: s.t('order.notesHint'))),
      ),
    ];
    final right = <Widget>[
      if (spec.segments) _segmentsEditor(context),
      if (spec.cableRuns) _cablesEditor(context),
      if (spec.meters) _metersEditor(context, spec),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF8F9F7), borderRadius: BorderRadius.circular(8)),
        child: Text(
          s.t('order.stepsFor', {
            'type': _type,
            'steps': app.engine.generate(OrderInput(type: _type, category: _category, needsExcavation: _excavation, meters: const [Meter('m')])).map((x) => s.step(x.key)).toSet().join(' · '),
          }),
          style: const TextStyle(fontSize: 12.5, color: C.muted, height: 1.45),
        ),
      ),
    ];
    final problems = <Widget>[
      if (_showErrors && _errors.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final e in _errors)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 16, color: C.critical),
              const SizedBox(width: 6),
              Expanded(child: Text(s.error(e), style: const TextStyle(color: C.critical))),
            ]),
          ),
      ],
    ];

    return UnsavedGuard(
      dirty: _dirty,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _save(next: _isNew),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: C.card,
            surfaceTintColor: C.card,
            title: Text(_isNew ? s.t('order.newTitle') : s.t('order.editTitle', {'wo': widget.editing!.woNumber ?? ''})),
            actions: [
              if (_isNew)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: Center(child: Text(s.t('order.addedToday', {'count': todayAdded}), style: const TextStyle(color: C.faint, fontSize: 13))),
                ),
            ],
          ),
          body: LayoutBuilder(builder: (context, box) {
            // Wide screen: the form takes two columns (order, type, place | work details, notes).
            final wide = box.maxWidth >= 1200;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1500 : 900),
                child: ListView(padding: EdgeInsets.all(phone ? 16 : 28), children: [
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gapped(left))),
                      const SizedBox(width: 20),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gapped(right))),
                    ])
                  else
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gapped([...left, ...right])),
                  ...problems,
                ]),
              ),
            );
          }),
          bottomNavigationBar: SafeArea(
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFFFBFBFA), border: Border(top: BorderSide(color: C.lineSoft))),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              // On a phone: two wide buttons (back arrow cancels). On the PC: the hint can wrap.
              child: phone
                  ? Row(children: [
                      if (_isNew) ...[
                        Expanded(child: OutlinedButton(onPressed: _saving ? null : () => _save(), child: Text(s.t('common.save')))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                              onPressed: _saving ? null : () => _save(next: true),
                              child: Text(s.t('common.saveAndNext'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ),
                      ] else
                        Expanded(child: FilledButton(onPressed: _saving ? null : () => _save(), child: Text(s.t('common.save')))),
                    ])
                  : Row(children: [
                      Expanded(
                        child: _isNew
                            ? Text(s.t('order.keptForNext'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.faint, fontSize: 12.5))
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 12),
                      TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(s.t('common.cancel'))),
                      const SizedBox(width: 8),
                      if (_isNew) ...[
                        OutlinedButton(onPressed: _saving ? null : () => _save(), child: Text(s.t('common.save'))),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: _saving ? null : () => _save(next: true), child: Text(s.t('common.saveAndNext'))),
                      ] else
                        FilledButton(onPressed: _saving ? null : () => _save(), child: Text(s.t('common.save'))),
                    ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _segmentsEditor(BuildContext context) {
    final s = context.s;
    return _Group(
      title: s.t('order.segments'),
      hint: s.t('order.segmentsHint'),
      onAdd: () => setState(() {
        _segs.add(_SegDraft(id: context.appRead.repo.newId()));
        _dirty = true;
      }),
      addLabel: s.t('order.addSegment'),
      children: [
        for (final g in _segs)
          _Line(
            key: ObjectKey(g),
            cols: 3,
            footer: Row(children: [
              Checkbox(
                value: g.tiled,
                onChanged: (v) => setState(() {
                  g.tiled = v ?? false;
                  _dirty = true;
                }),
              ),
              Text(s.t('order.tiled')),
              const SizedBox(width: 16),
              Expanded(child: Text(_recipe(context, g), style: const TextStyle(fontSize: 12, color: C.faint))),
            ]),
            onRemove: () => setState(() {
              _segs.remove(g);
              _dirty = true;
            }),
            children: [
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: g.base,
                  isExpanded: true, // the box is narrow: long labels are cut with … instead of overflowing
                  decoration: InputDecoration(labelText: s.t('order.base')),
                  items: [for (final b in const ['soil', 'asphalt']) DropdownMenuItem(value: b, child: Text(s.t('order.base.$b'), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() {
                    g.base = v ?? 'soil';
                    _dirty = true;
                  }),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: g.width,
                  isExpanded: true, // the box is narrow: long labels are cut with … instead of overflowing
                  decoration: InputDecoration(labelText: s.t('order.width')),
                  items: [
                    DropdownMenuItem(value: 40, child: Text(s.t('order.width40'), overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 80, child: Text(s.t('order.width80'), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() {
                    g.width = v ?? 40;
                    _dirty = true;
                  }),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextFormField(
                  initialValue: g.length,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  onChanged: (v) {
                    g.length = v;
                    _touch();
                  },
                  decoration: InputDecoration(labelText: s.t('order.lengthM')),
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _recipe(BuildContext context, _SegDraft g) {
    final app = context.appRead;
    final steps = app.engine.segmentRecipe(Segment(id: g.id, base: g.base, width: g.width, lengthM: 1, tiled: g.tiled));
    return steps.map(app.s.step).join(' → ');
  }

  Widget _cablesEditor(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final sizes = [for (final c in app.data.cableSizes) c.sizeMm2];
    if (sizes.isEmpty) sizes.addAll(const [70, 185, 300, 500]);
    return _Group(
      title: s.t('order.cableRuns'),
      hint: s.t('order.cableHint'),
      onAdd: () => setState(() {
        _cables.add(_CableDraft(size: sizes.first));
        _dirty = true;
      }),
      addLabel: s.t('order.addCable'),
      children: [
        for (final c in _cables)
          _Line(
            key: ObjectKey(c),
            onRemove: () => setState(() {
              _cables.remove(c);
              _dirty = true;
            }),
            children: [
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<int>(
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: c.size,
                  isExpanded: true, // the box is narrow: long labels are cut with … instead of overflowing
                  decoration: InputDecoration(labelText: s.t('order.cableSize')),
                  items: [for (final z in {...sizes, if (c.size != null) c.size!}) DropdownMenuItem(value: z, child: Text('$z mm²'))],
                  onChanged: (v) => setState(() {
                    c.size = v;
                    _dirty = true;
                  }),
                ),
              ),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'LV', label: Text('LV')), ButtonSegment(value: 'MV', label: Text('MV'))],
                selected: {c.voltage},
                onSelectionChanged: (v) => setState(() {
                  c.voltage = v.first;
                  _dirty = true;
                }),
              ),
              SizedBox(
                width: 170,
                child: TextFormField(
                  initialValue: c.length,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  onChanged: (v) {
                    c.length = v;
                    _touch();
                  },
                  decoration: InputDecoration(labelText: '${s.t('order.lengthM')} (${s.t('common.optional')})'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _metersEditor(BuildContext context, FormSpec spec) {
    final s = context.s;
    if (_meters.isEmpty) _meters.add(_MeterDraft(id: context.appRead.repo.newId()));
    return _Group(
      title: s.t('order.meters'),
      hint: s.t('order.metersHint2'),
      header: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(s.t('order.meterCount'), style: const TextStyle(fontWeight: FontWeight.w500)),
        IconButton.outlined(tooltip: '−', onPressed: _meters.length <= 1 ? null : () => _setMeterCount(_meters.length - 1), icon: const Icon(Icons.remove, size: 18)),
        SizedBox(
          width: 72,
          child: TextField(
            controller: _meterCount,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: monoStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n >= 1) _setMeterCount(n);
            },
          ),
        ),
        IconButton.outlined(tooltip: '+', onPressed: () => _setMeterCount(_meters.length + 1), icon: const Icon(Icons.add, size: 18)),
      ]),
      onAdd: () {
        _setMeterCount(_meters.length + 1);
      },
      addLabel: s.t('order.addMeter'),
      children: [
        for (final m in _meters)
          _Line(
            key: ObjectKey(m),
            index: _meters.indexOf(m) + 1,
            onRemove: _meters.length <= 1
                ? null
                : () {
                    setState(() {
                      _meters.remove(m);
                      _dirty = true;
                    });
                    _showMeterCount();
                  },
            children: [
              TextFormField(
                  initialValue: m.number,
                  textDirection: TextDirection.ltr,
                  onChanged: (v) {
                    m.number = v;
                    _touch();
                  },
                  decoration: InputDecoration(labelText: s.t('order.meterNumber')),
                ),
              if (spec.oldMeterNumber)
                TextFormField(
                    initialValue: m.oldNumber,
                    textDirection: TextDirection.ltr,
                    onChanged: (v) {
                      m.oldNumber = v;
                      _touch();
                    },
                    decoration: InputDecoration(labelText: s.t('order.oldMeterNumber')),
                  ),
              DropdownButtonFormField<String?>(
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: m.type,
                  isExpanded: true, // the box is narrow: long labels are cut with … instead of overflowing
                  decoration: InputDecoration(labelText: s.t('order.meterType')),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                    for (final t in const ['single_phase', 'three_phase', 'ct']) DropdownMenuItem<String?>(value: t, child: Text(s.t('order.meterType.$t'), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() {
                    m.type = v;
                    _dirty = true;
                  }),
                ),
              TextFormField(
                  initialValue: m.amps,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    m.amps = v;
                    _touch();
                  },
                  decoration: InputDecoration(labelText: s.t('order.breakerAmps')),
                ),
            ],
          ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.code, required this.label, required this.selected, required this.onTap});
  final String code, label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (tint, ink) = typeColors(code);
    return Tooltip(
      message: label, // the name shows on hover; everybody knows the codes
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? tint : C.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? ink : C.field, width: selected ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // The thin top edge carries the kind of work (same colours as the tags on the lists).
            Container(height: 4, color: ink),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(child: Mono(code, size: 24, weight: FontWeight.w700, color: selected ? ink : C.ink)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, this.hint, this.header, required this.children, required this.onAdd, required this.addLabel});
  final String title;
  final Widget? header;
  final String? hint;
  final List<Widget> children;
  final VoidCallback onAdd;
  final String addLabel;
  @override
  Widget build(BuildContext context) => SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (hint != null) Text(hint!, style: const TextStyle(fontSize: 12.5, color: C.faint)),
          const SizedBox(height: 10),
          if (header != null) ...[header!, const SizedBox(height: 12)],
          ...children,
          Align(alignment: AlignmentDirectional.centerStart, child: OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: Text(addLabel))),
        ]),
      );
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.children, this.onRemove, this.index, this.cols, this.footer});
  final List<Widget> children;
  final VoidCallback? onRemove;
  final int? index;
  final int? cols; // fields per row on a wide card (default: all in one row)
  final Widget? footer; // full-width line under the fields
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        decoration: BoxDecoration(color: C.bg, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (index != null)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsetsDirectional.only(end: 12, top: 8),
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: C.chip, shape: BoxShape.circle),
              child: Mono('$index', size: 13, weight: FontWeight.w600, color: C.muted),
            ),
          Expanded(
            // Wide: the fields share the row evenly and line up with the card edge. Narrow: two per row.
            child: LayoutBuilder(builder: (context, box) {
              final n = box.maxWidth >= 560 ? (cols ?? children.length) : 2;
              final w = (box.maxWidth - 12 * (n - 1)) / n;
              final fields = Wrap(spacing: 12, runSpacing: 12, children: [for (final c in children) SizedBox(width: w - 0.01, child: c)]);
              return footer == null ? fields : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [fields, const SizedBox(height: 4), footer!]);
            }),
          ),
          SizedBox(
            width: 40,
            child: onRemove == null ? null : IconButton(tooltip: context.t('common.remove'), onPressed: onRemove, icon: const Icon(Icons.close, size: 18, color: C.faint)),
          ),
        ]),
      );
}

/// A text field with suggestions from a list (districts).
class _Suggest extends StatefulWidget {
  const _Suggest({required this.controller, required this.label, this.helper, required this.options, required this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? helper;
  final List<String> options;
  final VoidCallback onChanged;
  @override
  State<_Suggest> createState() => _SuggestState();
}

class _SuggestState extends State<_Suggest> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (v) {
          final q = v.text.trim().toLowerCase();
          if (q.isEmpty) return const Iterable<String>.empty();
          return widget.options.where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q).take(8);
        },
        onSelected: (_) => widget.onChanged(),
        fieldViewBuilder: (context, ctl, focus, submit) => TextField(
          controller: ctl,
          focusNode: focus,
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(labelText: widget.label, helperText: widget.helper),
        ),
        optionsViewBuilder: (context, select, opts) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                for (final o in opts) ListTile(dense: true, title: Text(o), onTap: () => select(o)),
              ]),
            ),
          ),
        ),
      );
}
