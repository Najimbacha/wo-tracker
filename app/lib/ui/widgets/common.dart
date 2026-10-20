// Small building blocks used by every screen.
import 'dart:async';

import 'package:flutter/material.dart' hide Actions;

import '../../app/scope.dart';
import '../../domain/order_input.dart';
import '../../domain/rules_engine.dart';
import '../theme.dart';

class Mono extends StatelessWidget {
  const Mono(this.text, {super.key, this.size = 13, this.weight = FontWeight.w500, this.color});
  final String text;
  final double size;
  final FontWeight weight;
  final Color? color; // null = the normal text colour
  @override
  Widget build(BuildContext context) => Text(text,
      textDirection: TextDirection.ltr, style: monoStyle.copyWith(fontSize: size, fontWeight: weight, color: color ?? C.ink));
}

/// Colours by the kind of work: meter only (violet), underground / excavation (blue),
/// overhead line (teal). Any other code is grey. Returns (background, text).
(Color, Color) typeColors(String type) => switch (type) {
      '401' || '409' || '801' => C.dark ? (const Color(0xFF2B2145), const Color(0xFFCDB6FF)) : (const Color(0xFFF1EAFB), const Color(0xFF5B2A9E)),
      '402' || '404' || '802' || '804' => (C.accentSoft, C.accentDark),
      '403' || '803' || '805' => C.dark ? (const Color(0xFF123436), const Color(0xFF7FE0E4)) : (const Color(0xFFE0F3F3), const Color(0xFF0B5F64)),
      _ => (C.chip, C.muted),
    };

/// Work order type, e.g. "402", in a small tag coloured by the kind of work.
class TypeTag extends StatelessWidget {
  const TypeTag(this.type, {super.key});
  final String type;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = typeColors(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(type, textDirection: TextDirection.ltr, style: monoStyle.copyWith(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.background, this.icon});
  final String text;
  final Color? color, background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final fg = color ?? C.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background ?? C.chip, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

Color severityColor(String? severity) => severity == 'critical' ? C.critical : (severity == 'warning' ? C.warning : C.faint);
Color severityEdge(String? severity) => severity == 'critical' ? C.critical : (severity == 'warning' ? C.warningEdge : Colors.transparent);

class SeverityDot extends StatelessWidget {
  const SeverityDot(this.severity, {super.key, this.size = 8});
  final String? severity;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: severity == null ? C.success : severityColor(severity), shape: BoxShape.circle),
      );
}

/// Highest severity of an order's alerts (critical > warning > none).
String? worstSeverity(List<Alert> alerts) {
  String? w;
  for (final a in alerts) {
    if (a.severity == 'critical') return 'critical';
    if (a.severity == 'warning') w = 'warning';
  }
  return w;
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      'completed' => (C.success, C.successSoft),
      'on_hold' => (C.warning, C.warningSoft),
      'cancelled' || 'merged' => (C.muted, C.chip),
      _ => (C.accentDark, C.accentSoft),
    };
    return Pill(context.s.status(status), color: fg, background: bg);
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine(this.closed, this.total, {super.key, this.showText = true});
  final int closed, total;
  final bool showText;
  @override
  Widget build(BuildContext context) {
    final f = total == 0 ? 0.0 : closed / total;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          // Grows smoothly when progress changes; no animation on first show, so a list
          // being scrolled doesn't replay every bar from zero.
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: f, end: f),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: C.chip, color: C.accent),
          ),
        ),
      ),
      if (showText) ...[const SizedBox(width: 8), Mono(context.t('order.progress', {'closed': closed, 'total': total}), size: 11.5, color: C.faint)],
    ]);
  }
}

/// The top of a screen: a proper title, small count chips under it, and actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.chips = const [], this.actions = const []});
  final String title;
  final List<Widget> chips;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final phone = isPhone(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 14 : 24, phone ? 16 : 24, phone ? 14 : 24, 16),
      child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, alignment: WrapAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontSize: phone ? 24 : 28, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: C.ink)),
          if (chips.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 6, children: chips)],
        ]),
        if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
      ]),
    );
  }
}

/// A small count with its word: "2 open", "1 late". [tone] colours it: null = neutral, 'critical', 'warning', 'success'.
class StatChip extends StatelessWidget {
  const StatChip(this.count, this.label, {super.key, this.tone});
  final int count;
  final String label;
  final String? tone;
  @override
  Widget build(BuildContext context) {
    final (fg, bg, strong) = switch (tone) {
      'critical' => (C.critical, C.criticalSoft, C.critical),
      'warning' => (C.warning, C.warningSoft, C.warning),
      'success' => (C.success, C.successSoft, C.success),
      _ => (C.muted, C.chip, C.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$count', style: TextStyle(fontWeight: FontWeight.w600, color: strong)),
        TextSpan(text: ' $label', style: TextStyle(color: fg)),
      ]), style: const TextStyle(fontSize: 13)),
    );
  }
}

/// White card with a title row.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(14)});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (title != null || trailing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  if (title != null) Expanded(flex: 3, child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                  // Kept at the far end; a long label shrinks instead of overflowing.
                  if (trailing != null) Flexible(flex: 2, child: Align(alignment: AlignmentDirectional.centerEnd, child: trailing!)),
                ]),
              ),
            child,
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: C.chip, shape: BoxShape.circle),
              child: Icon(icon, color: C.muted, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (body != null) ...[const SizedBox(height: 6), Text(body!, textAlign: TextAlign.center, style: TextStyle(color: C.muted))],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Shows a spinner only if loading takes longer than 300 ms.
class DelayedLoader extends StatefulWidget {
  const DelayedLoader({super.key});
  @override
  State<DelayedLoader> createState() => _DelayedLoaderState();
}

class _DelayedLoaderState extends State<DelayedLoader> {
  bool _show = false;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(child: _show ? const CircularProgressIndicator(strokeWidth: 2.5) : const SizedBox.shrink());
}

/// A coloured strip across the top of a screen (offline, needs decision, demo...).
class Banner2 extends StatelessWidget {
  const Banner2({super.key, required this.text, this.icon = Icons.info_outline, this.color, this.background, this.action});
  final String text;
  final IconData icon;
  final Color? color, background;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final fg = color ?? C.muted;
    return Container(
      color: background ?? C.chip,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(icon, size: 17, color: fg),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13))),
        if (action != null) action!,
      ]),
    );
  }
}

/// One order in a list: number, type, place, contractor, next step, and the worst alert.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.onTap, this.selected = false, this.trailing, this.subtitle, this.dense = false});
  final OrderInput order;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;
  final String? subtitle;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final ev = app.evaluate(order);
    final sev = worstSeverity(ev.alerts);
    final s = app.s;
    final next = ev.next.isEmpty ? null : s.todo(ev.next.first.split('@').first);
    final issue = ev.alerts.isEmpty ? null : s.t('alertShort.${ev.alerts.first.code}');
    return Material(
      color: selected ? C.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: severityEdge(sev), width: 3))),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 5 : 8),
          child: Row(children: [
            SeverityDot(sev),
            const SizedBox(width: 10),
            Mono(order.woNumber ?? '—', size: 13),
            const SizedBox(width: 8),
            TypeTag(order.type),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle ?? [order.district, issue ?? (next == null ? null : s.t('order.nextStep', {'step': next}))].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                maxLines: 2, // a long reason goes onto a second line instead of being cut off
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: sev == null ? C.muted : severityColor(sev), fontSize: 13),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), Flexible(child: trailing!)],
          ]),
        ),
      ),
    );
  }
}

/// Small grey label above a value.
class Labeled extends StatelessWidget {
  const Labeled(this.label, this.value, {super.key, this.sub});
  final String label;
  final Widget value;
  final String? sub;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, color: C.faint)),
        const SizedBox(height: 3),
        value,
        if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: TextStyle(fontSize: 12, color: C.muted))],
      ]);
}

/// Cross-fade between screens that keeps each one at full size (the default layout
/// centres children, so a screen could show smaller than the space it has).
Widget fillLayout(Widget? current, List<Widget> previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]);

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;
bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < 700;
