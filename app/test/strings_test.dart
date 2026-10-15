// Text lookup, placeholders, step names and date formatting in both languages.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/hijri.dart';
import 'package:wo_tracker/domain/rules_engine.dart';
import 'package:wo_tracker/i18n/strings.dart';

void main() {
  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  final rules = json('assets/rules/rules.json');
  final enText = json('assets/i18n/en.json');
  final en = Strings('en', enText, enText, rules);
  final ar = Strings('ar', json('assets/i18n/ar.json'), enText, rules);
  final cal = HijriCalendar(json('assets/calendar/umalqura.json'));
  final fx = json('test/fixtures/hijri.json');

  test('shared formatting cases (same as the Node test)', () {
    for (final c in (json('test/fixtures/i18n.json')['cases'] as List).cast<Map<String, dynamic>>()) {
      final s = c['lang'] == 'ar' ? ar : en;
      expect(s.t(c['key'] as String, Map<String, Object?>.from(c['params'] as Map)), c['expected'], reason: '${c['lang']} ${c['key']} ${c['params']}');
    }
  });

  test('Arabic plural forms', () {
    const cases = {0: 'other', 1: 'one', 2: 'two', 3: 'few', 10: 'few', 11: 'many', 99: 'many', 100: 'other', 103: 'few', 111: 'many'};
    cases.forEach((n, f) => expect(Strings.pluralForm('ar', n), f, reason: '$n'));
    expect(Strings.pluralForm('en', 1), 'one');
    expect(Strings.pluralForm('en', 0), 'other');
  });

  test('missing text falls back to English, then to the key', () {
    final partial = Strings('ar', {'nav.today': 'اليوم'}, enText, rules);
    expect(partial.t('nav.today'), 'اليوم');
    expect(partial.t('nav.board'), 'Board');
    expect(partial.t('no.such.key'), 'no.such.key');
    expect(en.t('alert.open_trench'), 'Trench open {days#day}');
  });

  test('step and type names come from rules.json', () {
    expect(en.step('warning_tape'), 'Warning tape');
    expect(ar.step('warning_tape'), 'شريط التحذير');
    expect(en.type('402'), 'Excavation and meter');
    expect(ar.type('402'), 'حفرية وعداد');
    expect(ar.isRtl, isTrue);
    expect(en.isRtl, isFalse);
  });

  test('lock reasons list each step name once', () {
    const r = Reason('waiting_for', steps: ['warning_tape', 'compaction@s1', 'compaction@s2', 'excavation']);
    expect(en.reason(r), 'Waiting for Warning tape, Compaction and Excavation');
    expect(ar.reason(r), 'بانتظار شريط التحذير، الدك والحفرية');
    expect(en.reason(const Reason('tasreeh_starts', date: '2026-10-14')), 'Tasreeh starts 14 October 2026');
  });

  test('engine errors', () {
    expect(en.error(const Reason('duplicate_permit', permit: 'T-4471')), 'Tasreeh number T-4471 is already used.');
    expect(en.error(const Reason('waiting_for', steps: ['meter_on@m1', 'meter_on@m2'])), 'Mark Meter on done first.');
    expect(ar.error(const Reason('before_tasreeh_start', date: '2026-10-14')), 'لا يمكن أن يكون التاريخ قبل بداية التصريح (14 أكتوبر 2026).');
    expect(en.alert(const Alert('stalled', 'warning', {'days': 15})), 'No change for 15 days');
    expect(ar.alert(const Alert('stalled', 'warning', {'days': 15})), 'لا تغيير منذ 15 يوماً');
    expect(en.alert(const Alert('next_tasreeh_needed', 'warning', {'daysLeft': 0})), 'Tasreeh ends today and no next tasreeh is entered');
    expect(en.alert(const Alert('next_tasreeh_needed', 'warning', {'daysLeft': 2})), 'Tasreeh ends in 2 days and no next tasreeh is entered');
  });

  test('Gregorian and Hijri dates', () {
    expect(en.date('2026-10-11'), '11 October 2026');
    expect(ar.date('2026-10-11'), '11 أكتوبر 2026');
    for (final c in (fx['dates'] as List).cast<Map<String, dynamic>>()) {
      expect(en.hijri(c['gregorian'] as String, cal), c['en'], reason: c['note'] as String);
      expect(ar.hijri(c['gregorian'] as String, cal), c['ar'], reason: c['note'] as String);
    }
    expect(en.dateWithHijri('2026-10-11', cal), '11 October 2026 · 30 Rabiʻ II 1448');
    expect(en.dateWithHijri('2017-01-01', cal), '1 January 2017');
  });
}
