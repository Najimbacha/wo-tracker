// Umm al-Qura (Saudi official) Hijri dates from assets/calendar/umalqura.json.
// Mirrors tools/rules-check/hijri.mjs; both are tested on test/fixtures/hijri.json.

class HijriDate {
  final int year;
  final int month;
  final int day;
  const HijriDate(this.year, this.month, this.day);

  @override
  bool operator ==(Object other) => other is HijriDate && other.year == year && other.month == month && other.day == day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() => '$year-$month-$day AH';
}

int _dayNum(String ymd) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(ymd)) throw FormatException('bad date: $ymd');
  final p = ymd.split('-').map(int.parse).toList();
  final dt = DateTime.utc(p[0], p[1], p[2]);
  if (_fromDayNum(dt.millisecondsSinceEpoch ~/ 86400000) != ymd) throw FormatException('bad date: $ymd');
  return dt.millisecondsSinceEpoch ~/ 86400000;
}

String _fromDayNum(int n) => DateTime.fromMillisecondsSinceEpoch(n * 86400000, isUtc: true).toIso8601String().substring(0, 10);

class HijriCalendar {
  final int firstYear;
  final int lastYear;
  final List<int> _starts;

  HijriCalendar(Map<String, dynamic> table)
      : firstYear = table['firstYear'] as int,
        lastYear = table['lastYear'] as int,
        _starts = (table['monthStarts'] as List).map((e) => _dayNum(e as String)).toList() {
    if (_starts.length != (lastYear - firstYear + 1) * 12 + 1) throw StateError('month table has the wrong length');
  }

  String get firstDate => _fromDayNum(_starts.first);
  String get lastDate => _fromDayNum(_starts.last - 1);

  /// 'YYYY-MM-DD' → Hijri date, or null outside the table.
  HijriDate? toHijri(String ymd) {
    final n = _dayNum(ymd);
    if (n < _starts.first || n >= _starts.last) return null;
    var lo = 0, hi = _starts.length - 2; // last index whose start is <= n
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= n) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return HijriDate(firstYear + lo ~/ 12, lo % 12 + 1, n - _starts[lo] + 1);
  }

  int? monthLength(int year, int month) {
    final i = _index(year, month);
    return i == null ? null : _starts[i + 1] - _starts[i];
  }

  /// Hijri → 'YYYY-MM-DD', or null for an impossible or out-of-range date.
  String? fromHijri(int year, int month, int day) {
    final i = _index(year, month);
    if (i == null || day < 1 || day > _starts[i + 1] - _starts[i]) return null;
    return _fromDayNum(_starts[i] + day - 1);
  }

  int? _index(int year, int month) {
    if (month < 1 || month > 12 || year < firstYear || year > lastYear) return null;
    return (year - firstYear) * 12 + month - 1;
  }
}
