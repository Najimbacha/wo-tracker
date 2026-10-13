// Confirmations and small input dialogs. Normal work never asks "Are you sure?" —
// it saves and offers Undo. These are for things that need a reason, a date, or
// would also change other steps.
import 'package:flutter/material.dart' hide Actions;
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../theme.dart';

Future<bool> confirmDialog(BuildContext context,
    {required String title, String? body, Widget? content, required String confirm, bool danger = false, String? cancel}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: content ?? (body == null ? null : Text(body, style: const TextStyle(color: C.muted, height: 1.45))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel ?? c.t('common.cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.critical) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a written reason (required). Returns null when cancelled.
Future<String?> reasonDialog(BuildContext context,
    {required String title, String? body, required String confirm, List<String> suggestions = const [], String? initial, bool danger = false}) {
  return showDialog<String>(
    context: context,
    builder: (c) => _ReasonDialog(title: title, body: body, confirm: confirm, suggestions: suggestions, initial: initial, danger: danger),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, this.body, required this.confirm, this.suggestions = const [], this.initial, this.danger = false});
  final String title;
  final String? body;
  final String confirm;
  final List<String> suggestions;
  final String? initial;
  final bool danger;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final _ctl = TextEditingController(text: widget.initial ?? '');
  String? _error;

  void _submit() {
    final v = _ctl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = context.t('error.reason_required'));
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, minWidth: 320),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.body != null) ...[Text(widget.body!, style: const TextStyle(color: C.muted, height: 1.45)), const SizedBox(height: 12)],
            if (widget.suggestions.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final sgt in widget.suggestions)
                  ActionChip(
                    label: Text(sgt),
                    onPressed: () => setState(() {
                      _ctl.text = sgt;
                      _error = null;
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _ctl,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: context.t('common.reason'), errorText: _error),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('common.cancel'))),
          FilledButton(
            style: widget.danger ? FilledButton.styleFrom(backgroundColor: C.critical) : null,
            onPressed: _submit,
            child: Text(widget.confirm),
          ),
        ],
      );
}

String ymdOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dateOf(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Calendar picker; returns 'YYYY-MM-DD'. [last] defaults to today (no future dates).
Future<String?> pickDate(BuildContext context, {String? initial, String? first, String? last, String? help}) async {
  final app = context.appRead;
  final lastD = dateOf(last ?? app.today);
  final firstD = dateOf(first ?? '2020-01-01');
  var init = dateOf(initial ?? (last ?? app.today));
  if (init.isAfter(lastD)) init = lastD;
  if (init.isBefore(firstD)) init = firstD;
  final d = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: firstD,
    lastDate: lastD,
    helpText: help,
    currentDate: dateOf(app.today),
  );
  return d == null ? null : ymdOf(d);
}

/// Reads "16/10", "16/10/2026", "16-10-26", "2026-10-16" (Arabic digits too).
/// Returns 'YYYY-MM-DD' or null.
String? parseTypedDate(String text, String today) {
  var s = text.trim();
  s = s.replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}');
  s = s.replaceAllMapped(RegExp('[۰-۹]'), (m) => '${m[0]!.codeUnitAt(0) - 0x06f0}');
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  int? y, m, d;
  if (iso != null) {
    y = int.parse(iso[1]!);
    m = int.parse(iso[2]!);
    d = int.parse(iso[3]!);
  } else {
    // The year is 2 digits (26) or 4 digits (2026); a half-typed year (202) is not a date yet.
    final dm = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})(?:[/.\-](\d{2}|\d{4}))?$').firstMatch(s);
    if (dm == null) return null;
    d = int.parse(dm[1]!);
    m = int.parse(dm[2]!);
    final ty = int.parse(today.substring(0, 4));
    y = dm[3] == null ? ty : int.parse(dm[3]!);
    if (y < 100) y += 2000;
  }
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
  final dt = DateTime.utc(y, m, d);
  if (dt.month != m || dt.day != d) return null;
  return ymdOf(dt);
}

/// A date field: type it (16/10) or pick from the calendar. Shows the weekday and Hijri.
class DateField extends StatefulWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last, this.allowFuture = false, this.errorText, this.optional = false});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? first, last;
  final bool allowFuture;
  final String? errorText;
  final bool optional;
  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  late final _ctl = TextEditingController(text: _show(widget.value));
  String? _typedError;

  String _show(String? ymd) {
    if (ymd == null) return '';
    final p = ymd.split('-');
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  @override
  void didUpdateWidget(covariant DateField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && parseTypedDate(_ctl.text, context.appRead.today) != widget.value) {
      _ctl.text = _show(widget.value);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _typed(String text) {
    if (text.trim().isEmpty) {
      setState(() => _typedError = null);
      widget.onChanged(null);
      return;
    }
    final v = parseTypedDate(text, context.appRead.today);
    // Same limit as the calendar: no future dates unless this field allows them.
    final last = widget.allowFuture ? widget.last : (widget.last ?? context.appRead.today);
    final tooLate = v != null && last != null && v.compareTo(last) > 0;
    setState(() => _typedError = v == null ? context.t('date.typeHint') : (tooLate ? context.t('error.future_date') : null));
    if (v != null && !tooLate) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final v = widget.value;
    String? helper;
    if (v == null) {
      helper = widget.optional ? context.t('date.typeHint') : null;
    } else {
      // Weekday and Hijri under the box; a date that can't be read just shows nothing here.
      try {
        helper = '${app.s.weekday(v)} · ${app.s.hijri(v, app.calendar)}';
      } on FormatException {
        helper = null;
      }
    }
    return TextField(
      controller: _ctl,
      keyboardType: TextInputType.datetime,
      textDirection: TextDirection.ltr,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹/.\-]'))],
      onChanged: _typed,
      style: monoStyle.copyWith(fontSize: 14),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'dd/mm/yyyy',
        helperText: _typedError == null && widget.errorText == null ? helper : null,
        errorText: _typedError ?? widget.errorText,
        suffixIcon: IconButton(
          tooltip: context.t('date.pick'),
          icon: const Icon(Icons.calendar_month_outlined, size: 20),
          onPressed: () async {
            final d = await pickDate(context, initial: v, first: widget.first, last: widget.allowFuture ? (widget.last ?? '2100-12-31') : widget.last);
            if (d != null) {
              _ctl.text = _show(d);
              setState(() => _typedError = null);
              widget.onChanged(d);
            }
          },
        ),
      ),
    );
  }
}

/// Wraps a form: leaving with unsaved changes asks first.
class UnsavedGuard extends StatelessWidget {
  const UnsavedGuard({super.key, required this.dirty, required this.child});
  final bool dirty;
  final Widget child;
  @override
  Widget build(BuildContext context) => PopScope<Object?>(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await confirmDialog(
            context,
            title: context.t('confirm.unsavedTitle'),
            body: context.t('confirm.unsavedBody'),
            confirm: context.t('confirm.leave'),
            cancel: context.t('confirm.keepEditing'),
            danger: true,
          );
          if (leave && context.mounted) Navigator.of(context).pop();
        },
        child: child,
      );
}
