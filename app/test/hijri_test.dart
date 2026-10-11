// Runs the shared Hijri reference dates against the Dart converter.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/domain/hijri.dart';

void main() {
  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  final table = json('assets/calendar/umalqura.json');
  final fx = json('test/fixtures/hijri.json');
  final cal = HijriCalendar(table);

  test('reference dates', () {
    for (final c in (fx['dates'] as List).cast<Map<String, dynamic>>()) {
      final h = c['hijri'] as Map<String, dynamic>;
      final expected = HijriDate(h['year'] as int, h['month'] as int, h['day'] as int);
      expect(cal.toHijri(c['gregorian'] as String), expected, reason: c['note'] as String);
      expect(cal.fromHijri(expected.year, expected.month, expected.day), c['gregorian'], reason: c['note'] as String);
    }
  });

  test('every day round-trips', () {
    var d = DateTime.utc(2018, 9, 11);
    final end = DateTime.parse('${cal.lastDate}T00:00:00Z');
    var n = 0;
    while (!d.isAfter(end)) {
      final ymd = d.toIso8601String().substring(0, 10);
      final h = cal.toHijri(ymd)!;
      expect(cal.fromHijri(h.year, h.month, h.day), ymd);
      d = d.add(const Duration(days: 1));
      n++;
    }
    expect(n, greaterThan(14000));
  });

  test('month and year lengths', () {
    for (var y = cal.firstYear; y <= cal.lastYear; y++) {
      var total = 0;
      for (var m = 1; m <= 12; m++) {
        final len = cal.monthLength(y, m)!;
        expect(len == 29 || len == 30, isTrue, reason: '$y/$m');
        total += len;
      }
      expect(total == 354 || total == 355, isTrue, reason: '$y');
    }
    for (final c in (fx['monthLengths'] as List).cast<Map<String, dynamic>>()) {
      expect(cal.monthLength(c['year'] as int, c['month'] as int), c['days']);
    }
  });

  test('impossible and out-of-range dates', () {
    for (final c in (fx['invalidHijri'] as List).cast<Map<String, dynamic>>()) {
      final i = (c['input'] as List).cast<int>();
      expect(cal.fromHijri(i[0], i[1], i[2]), isNull, reason: c['note'] as String);
    }
    for (final c in (fx['outOfRange'] as List).cast<String>()) {
      expect(cal.toHijri(c), isNull, reason: c);
    }
    for (final bad in ['2026-02-30', '2026-13-01', '26-10-11', '']) {
      expect(() => cal.toHijri(bad), throwsFormatException, reason: bad);
    }
  });
}
