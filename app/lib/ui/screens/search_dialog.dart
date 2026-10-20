// Search anything (Ctrl+K): work order, tasreeh, meter and feeder numbers, places,
// contractors and notes, in English or Arabic, typed with any digits.
import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../domain/insights.dart';
import '../nav.dart';
import '../dark.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showSearchDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: isDark(context) ? null : const Color(0x6115181C),
      builder: (_) => const _Search(),
    );

class _Search extends StatefulWidget {
  const _Search();
  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final _ctl = TextEditingController();
  bool _completed = false;
  int _cursor = 0;
  List<SearchHit> _hits = const [];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _run() {
    final app = context.appRead;
    final q = _ctl.text.trim();
    if (q.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    final hits = app.insights.search(app.orders, q, app.today).where((h) => _completed || h.status == 'open' || h.status == 'on_hold').take(40).toList();
    setState(() {
      _hits = hits;
      _cursor = 0;
    });
  }

  void _open(SearchHit h) {
    final root = context.appRead.navigatorKey.currentContext;
    Navigator.pop(context);
    if (root != null) openOrder(root, h.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final kinds = <String, List<SearchHit>>{};
    for (final h in _hits) {
      (kinds[h.kind] ??= []).add(h);
    }
    final flat = [for (final l in kinds.values) ...l];
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Material(
        color: C.card,
        borderRadius: BorderRadius.circular(12),
        elevation: 12,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          // Up/Down move through the results, Enter opens one. The text field would
          // otherwise use Up/Down itself, so its arrow action is overridden here.
          child: Actions(
            actions: {
              ExtendSelectionVerticallyToAdjacentLineIntent: CallbackAction<ExtendSelectionVerticallyToAdjacentLineIntent>(
                onInvoke: (i) {
                  if (flat.isEmpty) return null;
                  setState(() => _cursor = (_cursor + (i.forward ? 1 : -1)).clamp(0, flat.length - 1));
                  return null;
                },
              ),
            },
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _ctl,
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  onChanged: (_) => _run(),
                  onSubmitted: (_) {
                    if (flat.isNotEmpty) _open(flat[_cursor.clamp(0, flat.length - 1)]);
                  },
                  decoration: InputDecoration(
                    hintText: s.t('search.hint'),
                    prefixIcon: const Icon(Icons.search),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(children: [
                  FilterChip(
                    label: Text(s.t('search.includeCompleted')),
                    selected: _completed,
                    onSelected: (v) {
                      _completed = v;
                      _run();
                    },
                  ),
                ]),
              ),
              Flexible(
                child: _ctl.text.trim().isEmpty
                    ? Padding(padding: const EdgeInsets.all(20), child: Text(s.t('search.footer'), style: const TextStyle(color: C.faint)))
                    : flat.isEmpty
                        ? Padding(padding: const EdgeInsets.all(20), child: Text(s.t('empty.noResults', {'query': _ctl.text.trim()}), style: const TextStyle(color: C.muted)))
                        : ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 8), children: [
                            for (final e in kinds.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(s.t('search.kind.${e.key}').toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 0.5, color: C.faint, fontWeight: FontWeight.w600)),
                              ),
                              for (final h in e.value)
                                _HitTile(hit: h, active: flat.indexOf(h) == _cursor, onTap: () => _open(h)),
                            ],
                          ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.active, required this.onTap});
  final SearchHit hit;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final o = app.orderById(hit.id);
    final sub = o == null
        ? ''
        : [
            if (hit.kind != 'workOrder') o.woNumber,
            o.type,
            o.district,
            o.contractor,
            app.s.status(hit.status),
          ].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
    return Material(
      color: active ? C.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                hit.kind == 'workOrder' || hit.kind == 'tasreeh' || hit.kind == 'meter' || hit.kind == 'network' ? Mono(hit.value) : Text(hit.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.faint, fontSize: 12)),
              ]),
            ),
            if (active) const Text('Enter', style: TextStyle(fontSize: 11, color: C.faint, fontFamily: mono)),
          ]),
        ),
      ),
    );
  }
}
