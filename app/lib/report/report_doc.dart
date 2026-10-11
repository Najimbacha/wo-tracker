// The finished report as plain data: every section, label, row and number, in English
// or Arabic. Mirrors tools/rules-check/report-doc.mjs; test/report_doc_test.dart checks
// both produce exactly the same document. The PDF and Excel writers only lay this out.
import '../domain/hijri.dart';
import '../domain/insights.dart';
import '../domain/order_input.dart';
import '../domain/rules_engine.dart';
import '../i18n/strings.dart';

const _trendDays = 14;
const _topContractors = 6;
const pdfLimits = {'delays': 25, 'completed': 30};
const _impliedNext = {
  'meter_not_on': ['meter_on'],
  'tawari_tasreeh_missing': ['tasreeh_applied'],
};

class ReportDoc {
  final Insights insights;
  ReportDoc(this.insights);

  RulesEngine get _engine => insights.engine;
  Map<String, dynamic> get _rules => insights.rules;

  /// kind: 'daily' | 'weekly' | 'monthly'. [generatedAt] is 'YYYY-MM-DD HH:mm'.
  Map<String, Object?> build(
    List<OrderInput> orders,
    String kind,
    String date,
    String today, {
    required Strings s,
    HijriCalendar? hijri,
    required String preparedBy,
    String? generatedAt,
  }) {
    final range = kind == 'daily'
        ? DateRange(date, date)
        : kind == 'weekly'
            ? Insights.weekRange(date)
            : Insights.monthRange(date);
    if (toDay(range.from) > toDay(today)) throw ArgumentError('The report period starts after $today');
    final asOf = toDay(range.to) < toDay(today) ? range.to : today;
    // current: the period includes today. partial: it is still running, so it is compared
    // with the same days of the previous period.
    final current = toDay(today) <= toDay(range.to);
    final partial = toDay(asOf) < toDay(range.to);
    final r = insights.report(orders, range.from, range.to, today: asOf);
    final prevFull = kind == 'daily'
        ? DateRange(fromDay(toDay(date) - 1), fromDay(toDay(date) - 1))
        : kind == 'weekly'
            ? Insights.weekRange(fromDay(toDay(range.from) - 1))
            : Insights.monthRange(fromDay(toDay(range.from) - 1));
    final elapsed = toDay(asOf) - toDay(range.from);
    final prevEnd = toDay(prevFull.from) + elapsed;
    final prevTo = fromDay(prevEnd < toDay(prevFull.to) ? prevEnd : toDay(prevFull.to));
    final prev = insights.report(orders, prevFull.from, prevTo, today: prevTo);
    String signed(int n) => n > 0 ? '+$n' : (n < 0 ? '−${n.abs()}' : '±0');
    final vsKey = kind == 'daily'
        ? 'report.vsPrevDay'
        : kind == 'weekly'
            ? (partial ? 'report.vsPrevWeekSoFar' : 'report.vsPrevWeek')
            : (partial ? 'report.vsPrevMonthSoFar' : 'report.vsPrevMonth');
    final periodWord = s.t(current ? 'report.period.$kind' : 'report.period.${kind}Past');
    final reportName = s.t('report.${kind}Title');

    // Header
    String title, hijriText;
    String h(String d) => hijri == null ? '' : s.hijri(d, hijri);
    if (kind == 'daily') {
      title = s.t('report.weekdayDate', {'weekday': s.weekday(date), 'date': s.date(date)});
      hijriText = h(date);
    } else {
      if (kind == 'weekly') {
        title = s.t('report.range', {'from': s.date(range.from), 'to': s.date(range.to)});
      } else {
        final p = range.from.split('-');
        title = '${s.t('date.month.${int.parse(p[1])}')} ${p[0]}';
      }
      final hf = h(range.from), ht = h(range.to);
      hijriText = hf.isNotEmpty && ht.isNotEmpty ? s.t('report.range', {'from': hf, 'to': ht}) : '';
    }

    // Key figures
    final attn = r.attentionByCode.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
    final attnParts = attn.map((e) => '${s.t('alertShort.${e.key}')} ${e.value}').toList();
    final kpis = [
      {'key': 'received', 'label': s.t('report.kpiReceived', {'period': periodWord}), 'value': r.received, 'note': s.t(vsKey, {'delta': signed(r.received - prev.received)}), 'tone': 'normal'},
      {'key': 'steps', 'label': s.t('report.stepsCompleted'), 'value': r.stepsCompleted, 'note': s.t('report.onOrders', {'count': r.ordersTouched}), 'tone': 'normal'},
      {'key': 'completed', 'label': s.t('report.ordersCompleted'), 'value': r.completed, 'note': s.t(vsKey, {'delta': signed(r.completed - prev.completed)}), 'tone': 'normal'},
      {'key': 'attention', 'label': s.t('report.needAttention'), 'value': r.attention, 'note': attnParts.take(3).join(' · '), 'tone': r.attention > 0 ? 'alert' : 'normal'},
    ];

    // Trend
    final trendFrom = kind == 'daily' ? fromDay(toDay(date) - (_trendDays - 1)) : range.from;
    final series = insights.report(orders, trendFrom, asOf, today: asOf).series;
    String avg(int Function(SeriesPoint) f) =>
        (series.isEmpty ? 0 : series.fold<int>(0, (a, p) => a + f(p)) / series.length).toStringAsFixed(1);
    var max = 1;
    for (final p in series) {
      if (p.received > max) max = p.received;
      if (p.completed > max) max = p.completed;
    }
    final trend = {
      'title': kind == 'daily' ? s.t('report.receivedVsCompleted') : s.t('report.byDay'),
      'days': [for (final p in series) {'date': p.date, 'label': _shortDate(s, p.date), 'received': p.received, 'completed': p.completed}],
      'max': max,
      'legend': {'received': s.t('report.received'), 'completed': s.t('report.completedInPeriod')},
      'summary': s.t('report.trendSummary', {'received': avg((p) => p.received), 'completed': avg((p) => p.completed)}),
    };

    final stagesList = (_rules['stages'] as List).cast<Map<String, dynamic>>();
    final stages = {
      'title': s.t('report.openByStage', {'count': r.open}),
      'rows': [for (final st in stagesList) {'key': st['key'], 'label': s.t('stage.${st['key']}'), 'value': r.byStage[st['key']] ?? 0}],
    };

    final stepOrder = (_rules['steps'] as Map).keys.toList();
    final stepEntries = r.stepsByKey.entries.toList()..sort((a, b) => stepOrder.indexOf(a.key) - stepOrder.indexOf(b.key));
    final steps = {
      'title': s.t('report.stepsInPeriod', {'count': r.stepsCompleted}),
      'rows': [for (final e in stepEntries) {'key': e.key, 'label': s.step(e.key), 'value': e.value}],
    };

    // Needs attention
    final byId = {for (final o in orders) o.id: o};
    final delays = {
      'title': s.t('report.delays', {'count': r.delays.length}),
      'subtitle': s.t('report.mostUrgentFirst'),
      'columns': [for (final k in const ['wo', 'type', 'district', 'contractor', 'issue', 'days']) {'key': k, 'label': s.t('report.col.$k'), 'numeric': k == 'days'}],
      'rows': [
        for (final d in r.delays) _delayRow(d, byId[d.id]!, asOf, s),
      ],
    };

    // By contractor
    final all = r.contractors;
    final named = all.where((c) => c.contractor != unassignedContractor).toList();
    final top = named.take(_topContractors).toList();
    final rest = [...named.skip(_topContractors), ...all.where((c) => c.contractor == unassignedContractor)];
    Map<String, Object?> sumRow(List<ContractorStats> list, String label) {
      final finished = list.fold<int>(0, (a, c) => a + c.finished);
      return {
        'contractor': label,
        'open': list.fold<int>(0, (a, c) => a + c.open),
        'completed': list.fold<int>(0, (a, c) => a + c.completedInPeriod),
        'lateStarts': list.fold<int>(0, (a, c) => a + c.lateStarts),
        'avgDays': finished > 0 ? (list.fold<int>(0, (a, c) => a + c.finishDaysTotal) / finished).round() : null,
      };
    }

    final contractors = {
      'title': s.t('report.byContractor'),
      'subtitle': s.t(current ? 'report.openAsOf' : 'report.openAtEnd'),
      'columns': [
        {'key': 'contractor', 'label': s.t('report.col.contractor'), 'numeric': false},
        {'key': 'open', 'label': s.t('report.open'), 'numeric': true},
        {'key': 'completed', 'label': s.t('report.completedInPeriod'), 'numeric': true},
        {'key': 'lateStarts', 'label': s.t('report.lateStarts'), 'numeric': true},
        {'key': 'avgDays', 'label': s.t('report.avgDaysToFinish'), 'numeric': true},
      ],
      'rows': [
        for (final c in top) {'contractor': c.contractor, 'open': c.open, 'completed': c.completedInPeriod, 'lateStarts': c.lateStarts, 'avgDays': c.avgDaysToFinish},
        if (rest.length == 1 && rest.first.contractor == unassignedContractor)
          sumRow(rest, s.t('common.unassigned'))
        else if (rest.isNotEmpty)
          sumRow(rest, s.t('report.others', {'count': rest.length})),
      ],
      'total': sumRow(all, s.t('report.total')),
    };

    final completed = {
      'title': s.t('report.completedList', {'count': r.completed}),
      'subtitle': s.t('report.documentsSubmitted'),
      'rows': [for (final c in r.completedList) {'wo': c.woNumber, 'type': c.type, 'days': c.days, 'daysText': s.t('common.days', {'count': c.days})}],
    };

    const qKeys = ['cableLV', 'cableMV', 'asphalt40', 'asphalt80', 'soil', 'tiles'];
    final quantities = {
      'title': s.t('report.quantities'),
      'subtitle': s.t('report.metres'),
      'items': [for (final k in qKeys) {'key': k, 'label': s.t('report.$k'), 'value': (r.quantities[k] ?? 0).round()}],
    };

    return {
      'kind': kind,
      'lang': s.lang,
      'dir': s.isRtl ? 'rtl' : 'ltr',
      'period': {'from': range.from, 'to': range.to},
      'header': {
        'eyebrow': reportName,
        'title': title,
        'hijri': hijriText,
        'preparedBy': s.t('report.preparedBy', {'name': preparedBy}),
        'generated': s.t('report.generated', {'time': _generated(s, generatedAt)}),
      },
      'kpis': kpis,
      'trend': trend,
      'stages': stages,
      'steps': steps,
      'delays': delays,
      'contractors': contractors,
      'completed': completed,
      'quantities': quantities,
      'empty': s.t('report.none'),
      'moreText': s.t('report.moreRows', {'count': '{count}'}),
      'limits': pdfLimits,
      'footer': s.t('report.footer', {'report': reportName, 'date': s.date(today)}),
      'pageText': s.t('report.page', {'page': '{page}', 'pages': '{pages}'}),
    };
  }

  Map<String, Object?> _delayRow(DelayRow d, OrderInput order, String asOf, Strings s) {
    final ev = _engine.evaluate(order, asOf);
    final nextKey = ev.next.isNotEmpty ? ev.next.first.split('@').first : null;
    final nextName = nextKey != null && !(_impliedNext[d.code] ?? const []).contains(nextKey) ? s.step(nextKey) : null;
    var issue = s.t('alertShort.${d.code}');
    if (d.code == 'next_tasreeh_needed') {
      for (final a in ev.alerts) {
        if (a.code == 'next_tasreeh_needed') {
          final left = a['daysLeft'] as int;
          issue = left == 0 ? s.t('report.tasreehEndsToday') : s.t('report.tasreehEndsIn', {'daysLeft': left});
          break;
        }
      }
    }
    var days = d.days;
    if (days == null && d.code == 'no_active_tasreeh') {
      for (final a in ev.alerts) {
        if (a.code == 'no_active_tasreeh' && a['since'] != null) {
          days = activeDays(a['since'] as String, asOf, order.holdPeriods);
          break;
        }
      }
    }
    return {
      'wo': d.woNumber,
      'type': d.type,
      'district': d.district ?? '',
      'contractor': d.contractor ?? s.t('common.unassigned'),
      'issue': nextName != null ? s.t('report.issueNext', {'issue': issue, 'step': nextName}) : issue,
      'days': days,
      'severity': d.severity,
    };
  }

  static String _shortDate(Strings s, String ymd) {
    final p = ymd.split('-');
    final month = s.t('date.month.${int.parse(p[1])}');
    return '${int.parse(p[2])} ${s.isRtl ? month : month.substring(0, 3)}';
  }

  static String _generated(Strings s, String? at) {
    if (at == null || at.isEmpty) return '';
    final parts = at.split(' ');
    return parts.length > 1 ? '${s.date(parts[0])}${s.isRtl ? '، ' : ', '}${parts[1]}' : s.date(parts[0]);
  }
}
