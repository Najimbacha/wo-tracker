// Demo mode: loads assets/demo/demo_orders.json and moves every date so that the
// file's "today" becomes the real today. Demo orders live only in memory on this
// device; they are never written to the database or synced.
import 'order_input.dart';
import 'rules_engine.dart';

class DemoData {
  /// Orders from the demo file with all dates moved to [realToday].
  static List<OrderInput> load(Map<String, dynamic> file, String realToday) {
    final days = toDay(realToday) - toDay(file['today'] as String);
    return (file['orders'] as List).map((o) => OrderInput.fromJson(shiftJson(Map<String, dynamic>.from(o as Map), days))).toList();
  }

  /// Same as shiftDates in tools/sample/demo.mjs, on the JSON form of an order.
  static Map<String, dynamic> shiftJson(Map<String, dynamic> o, int days) {
    String? sh(Object? d) => d == null ? null : fromDay(toDay(d as String) + days);
    final out = Map<String, dynamic>.from(o);
    out['receivedDate'] = sh(o['receivedDate']);
    out['lastChangeDate'] = sh(o['lastChangeDate']);
    out['permits'] = [
      for (final p in (o['permits'] as List? ?? const []))
        {...(p as Map), 'appliedDate': sh(p['appliedDate']), 'startDate': sh(p['startDate']), 'endDate': sh(p['endDate'])},
    ];
    out['steps'] = {
      for (final e in (o['steps'] as Map? ?? const {}).entries)
        e.key: (e.value as Map)['done'] != null ? {...e.value as Map, 'done': sh((e.value as Map)['done'])} : e.value,
    };
    final status = o['status'] as Map?;
    if (status != null) {
      out['status'] = {
        ...status,
        'holdPeriods': [
          for (final h in (status['holdPeriods'] as List? ?? const []))
            {...(h as Map), 'from': sh(h['from']), 'to': sh(h['to']), if (h['review'] != null) 'review': sh(h['review'])},
        ],
      };
    }
    return out;
  }
}
