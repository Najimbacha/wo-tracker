// Text lookup for English and Arabic. The text lives in assets/i18n/*.json;
// tools/rules-check/i18n.test.mjs checks that both files cover every code.
import '../domain/hijri.dart';
import '../domain/rules_engine.dart';

class Strings {
  final String lang; // 'en' | 'ar'
  final Map<String, String> _text;
  final Map<String, String> _fallback;
  final Map<String, dynamic> _rules;

  Strings(this.lang, Map<String, dynamic> text, Map<String, dynamic> english, this._rules)
      : _text = text.map((k, v) => MapEntry(k, v as String)),
        _fallback = english.map((k, v) => MapEntry(k, v as String));

  bool get isRtl => lang == 'ar';

  /// Looks up [key] and fills placeholders. Falls back to English, then to the key
  /// itself, so a missing text never crashes a screen.
  ///   {name}       → the value
  ///   {name#unit}  → number + correctly pluralised word ("9 days", "11 يوماً")
  String t(String key, [Map<String, Object?> params = const {}]) {
    final raw = _text[key] ?? _fallback[key] ?? key;
    return raw.replaceAllMapped(_placeholder, (m) {
      final v = params[m.group(1)];
      if (v == null) return m.group(0)!;
      final unit = m.group(2);
      if (unit != null && v is num) {
        final n = v.toInt();
        final word = _text['unit.$unit.${pluralForm(lang, n)}'] ??
            _text['unit.$unit.other'] ??
            _fallback['unit.$unit.${pluralForm('en', n)}'] ??
            unit;
        return '$v $word';
      }
      if (v is List) return list(v.map((e) => '$e').toList());
      return '$v';
    });
  }

  static final _placeholder = RegExp(r'\{(\w+)(?:#(\w+))?\}');

  /// CLDR plural form for a whole number (same as tools/rules-check/i18n.mjs).
  static String pluralForm(String lang, int n) {
    n = n.abs();
    if (lang == 'ar') {
      if (n == 1) return 'one';
      if (n == 2) return 'two';
      final r = n % 100;
      if (r >= 3 && r <= 10) return 'few';
      if (r >= 11 && r <= 99) return 'many';
      return 'other';
    }
    return n == 1 ? 'one' : 'other';
  }

  /// "A, B and C" in English, "A، B و C" in Arabic.
  String list(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    final sep = isRtl ? '، ' : ', ';
    final and = isRtl ? ' و' : ' and ';
    return '${items.sublist(0, items.length - 1).join(sep)}$and${items.last}';
  }

  /// '2026-10-11' → "11 October 2026" / "11 أكتوبر 2026".
  String date(String ymd) {
    final p = ymd.split('-');
    return '${int.parse(p[2])} ${t('date.month.${int.parse(p[1])}')} ${p[0]}';
  }

  /// '2026-10-11' → "Sunday" / "الأحد".
  String weekday(String ymd) => t('date.weekday.${DateTime.parse('${ymd}T00:00:00Z').weekday % 7}');

  /// '2026-10-11' → "30 Rabiʻ II 1448" / "30 ربيع الآخر 1448هـ"; empty outside the table.
  String hijri(String ymd, HijriCalendar cal) {
    final h = cal.toHijri(ymd);
    if (h == null) return '';
    return t('date.hijriFull', {'day': h.day, 'month': t('date.hijri.${h.month}'), 'year': h.year});
  }

  /// Gregorian with Hijri beside it, as shown on screens and reports when the setting is on.
  String dateWithHijri(String ymd, HijriCalendar cal) {
    final h = hijri(ymd, cal);
    return h.isEmpty ? date(ymd) : '${date(ymd)} · $h';
  }

  String _ruleLabel(Map<String, dynamic>? def, String fallback) => (def?[lang] ?? def?['en'] ?? fallback) as String;

  String step(String key) => _ruleLabel((_rules['steps'] as Map)[key] as Map<String, dynamic>?, key);
  String type(String code) => _ruleLabel((_rules['types'] as Map)[code] as Map<String, dynamic>?, code);
  String category(String c) => t('category.$c');
  String status(String s) => t('status.$s');
  String stage(String s) => t('stage.$s');

  /// Step keys from the engine ('cable_installed') turned into names.
  List<String> steps(Iterable<String> keys) => keys.map(step).toList();

  String alert(Alert a) => a.code == 'next_tasreeh_needed' && a.data['daysLeft'] == 0
      ? t('alert.next_tasreeh_needed_today')
      : t('alert.${a.code}', a.data);

  String reason(Reason r) => t('lock.${r.code}', {
        if (r.steps.isNotEmpty) 'steps': _uniqueNames(r.steps),
        if (r.date != null) 'date': date(r.date!),
      });

  /// Error from validateMarkDone or validateOrder.
  String error(Reason r) => t('error.${r.code}', {
        ...r.extra,
        if (r.steps.isNotEmpty) 'steps': _uniqueNames(r.steps),
        if (r.date != null) 'date': date(r.date!),
        if (r.permit != null) 'permit': r.permit,
      });

  // Step instance ids look like "compaction@s1" or "meter_on@m2"; the name comes from the key.
  // Two meters waiting on the same step show the name once.
  List<String> _uniqueNames(Iterable<String> ids) => ids.map((id) => step(id.split('@').first)).toSet().toList();
}
