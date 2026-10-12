// Everything the screens share: the rules, the text in both languages, the data,
// today's date in Riyadh, and the one place where changes are saved (with Undo).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Actions;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/memory_repository.dart';
import '../data/models.dart';
import '../data/order_rows.dart';
import '../data/powersync_repository.dart';
import '../data/repository.dart';
import '../domain/actions.dart';
import '../domain/demo.dart';
import '../domain/hijri.dart';
import '../domain/insights.dart';
import '../domain/order_input.dart';
import '../domain/rules_engine.dart';
import '../i18n/strings.dart';
import '../report/export_doc.dart';
import '../report/report_doc.dart';

/// Today's date in Riyadh (UTC+3, no daylight saving), as 'YYYY-MM-DD'.
String riyadhToday([DateTime? now]) {
  final t = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// 'YYYY-MM-DD HH:mm' in Riyadh time.
String riyadhNow([DateTime? now]) {
  final t = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// A change that can be undone from the toast.
class _UndoEntry {
  final List<OrderChange> redo; // what was saved
  _UndoEntry(this.redo);
}

class AppState extends ChangeNotifier {
  AppState._(this.rules, this.textEn, this.textAr, this.calendar, this.demoFile, this.prefs)
      : engine = RulesEngine(rules) {
    insights = Insights(engine);
    actions = Actions(engine);
    reportDoc = ReportDoc(insights);
    exportDoc = ExportDoc(insights);
  }

  final Map<String, dynamic> rules;
  final Map<String, dynamic> textEn;
  final Map<String, dynamic> textAr;
  final HijriCalendar calendar;
  final Map<String, dynamic> demoFile;
  final SharedPreferences prefs;
  final RulesEngine engine;
  late final Insights insights;
  late final Actions actions;
  late final ReportDoc reportDoc;
  late final ExportDoc exportDoc;

  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final navigatorKey = GlobalKey<NavigatorState>();

  Repository? _repo;
  Repository get repo => _repo!;
  bool get ready => _repo != null && data.loaded;
  RepoData data = const RepoData();
  SyncInfo sync = const SyncInfo();
  List<RefusedChange> refused = const [];
  String? startupError;
  final List<StreamSubscription<Object?>> _subs = [];

  late String today = riyadhToday();
  Timer? _midnight;

  // ---------------------------------------------------------------- start-up

  static Future<AppState> load() async {
    Future<Map<String, dynamic>> json(String path) async => jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>;
    final app = AppState._(
      await json('assets/rules/rules.json'),
      await json('assets/i18n/en.json'),
      await json('assets/i18n/ar.json'),
      HijriCalendar(await json('assets/calendar/umalqura.json')),
      await json('assets/demo/demo_orders.json'),
      await SharedPreferences.getInstance(),
    );
    await app._openRepository();
    app._scheduleMidnight();
    return app;
  }

  bool get demoMode => prefs.getBool('demoMode') ?? false;

  SyncConfig? get syncConfig {
    final url = prefs.getString('supabaseUrl') ?? const String.fromEnvironment('SUPABASE_URL');
    final key = prefs.getString('supabaseAnonKey') ?? const String.fromEnvironment('SUPABASE_ANON_KEY');
    final ps = prefs.getString('powersyncUrl') ?? const String.fromEnvironment('POWERSYNC_URL');
    final c = SyncConfig(supabaseUrl: url, anonKey: key, powersyncUrl: ps);
    return c.complete ? c : null;
  }

  Future<void> saveSyncConfig(SyncConfig c) async {
    await prefs.setString('supabaseUrl', c.supabaseUrl.trim());
    await prefs.setString('supabaseAnonKey', c.anonKey.trim());
    await prefs.setString('powersyncUrl', c.powersyncUrl.trim());
  }

  Future<void> _openRepository() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    // The old store stays in place until the new one is open, so screens always have one.
    final old = _repo;
    if (old != null) await old.dispose();
    Repository next;
    try {
      if (demoMode) {
        next = MemoryRepository(DemoData.load(demoFile, today));
      } else {
        final dir = await getApplicationSupportDirectory();
        next = await PowerSyncRepository.open(
          path: '${dir.path}/wo_tracker.db',
          config: syncConfig,
          segmentStepKeys: segmentStepKeysOf(rules),
        );
      }
      startupError = null;
    } catch (e) {
      startupError = '$e';
      next = MemoryRepository(const []);
    }
    _repo = next;
    _evalCache.clear();
    _memo.clear();
    selectedOrderId = null;
    data = repo.current;
    sync = repo.currentSync;
    _subs.add(repo.data.listen((d) {
      data = d;
      _evalCache.clear();
      _memo.clear();
      notifyListeners();
    }));
    _subs.add(repo.syncInfo.listen((s) {
      sync = s;
      notifyListeners();
    }));
    _subs.add(repo.refused.listen((r) {
      refused = r;
      notifyListeners();
    }));
    notifyListeners();
  }

  Future<void> setDemoMode(bool on) async {
    await prefs.setBool('demoMode', on);
    await _openRepository();
  }

  /// After the sync addresses change; Supabase can only start once per run.
  bool get needsRestart => prefs.getBool('needsRestart') ?? false;

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final next = DateTime.utc(now.year, now.month, now.day + 1).subtract(const Duration(hours: 3));
    _midnight = Timer(next.difference(DateTime.now().toUtc()) + const Duration(seconds: 2), () {
      today = riyadhToday();
      _evalCache.clear();
      _memo.clear();
      notifyListeners();
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _repo?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- language

  String get lang => prefs.getString('language') ?? data.settings.language;
  late Strings _s = Strings('en', textEn, textEn, rules);
  Strings get s {
    if (_s.lang != lang) _s = Strings(lang, lang == 'ar' ? textAr : textEn, textEn, rules);
    return _s;
  }

  bool get rtl => lang == 'ar';
  bool get showHijri => data.settings.showHijri;

  Future<void> setLanguage(String l) async {
    await prefs.setString('language', l);
    notifyListeners();
    try {
      await repo.saveSettings(data.settings.copyWith(language: l));
    } catch (_) {}
  }

  /// Strings for a report in a chosen language (independent of the app language).
  Strings stringsFor(String l) => Strings(l, l == 'ar' ? textAr : textEn, textEn, rules);

  String date(String ymd) => showHijri ? s.dateWithHijri(ymd, calendar) : s.date(ymd);
  String dateShort(String ymd) {
    final p = ymd.split('-');
    final m = s.t('date.month.${int.parse(p[1])}');
    return '${int.parse(p[2])} ${m.length > 3 && lang == 'en' ? m.substring(0, 3) : m}';
  }

  // ---------------------------------------------------------------- orders

  Map<String, int> get alertSettings => data.settings.alertOverrides;

  /// Active (not deleted) orders.
  List<OrderInput> get orders => [for (final o in data.orders) if (!o.deleted) o];
  List<OrderInput> get deletedOrders => [for (final o in data.orders) if (o.deleted) o];

  OrderInput? orderById(String? id) {
    if (id == null) return null;
    for (final o in data.orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  final Map<String, (OrderInput, Evaluation)> _evalCache = {};
  Evaluation evaluate(OrderInput o) {
    final key = o.id ?? '';
    final hit = _evalCache[key];
    if (hit != null && identical(hit.$1, o)) return hit.$2;
    final ev = engine.evaluate(o, today, alertSettings: alertSettings);
    if (o.id != null) _evalCache[key] = (o, ev);
    return ev;
  }

  List<Evaluated> get evaluated => memo('evaluated', () => [for (final o in orders) Evaluated(o, evaluate(o))]);

  final Map<String, Object?> _memo = {};

  /// Screen calculations (board, pipeline, follow-up...) are done once per data change.
  T memo<T>(String key, T Function() compute) {
    if (_memo.containsKey(key)) return _memo[key] as T;
    final v = compute();
    _memo[key] = v;
    return v;
  }

  OrderCache cacheOf(OrderInput o) {
    final ev = engine.evaluate(o, today, alertSettings: alertSettings);
    return OrderCache(ev.status, ev.stage, ev.closed, ev.total);
  }

  /// Saves order changes. Shows [toastKey] with Undo when given. Returns false if it
  /// failed (the message is shown).
  Future<bool> save(List<OrderChange> changes, {String? toast, Map<String, Object?> toastParams = const {}, bool undo = true}) async {
    try {
      await repo.saveOrders(changes, cacheOf);
    } catch (e) {
      showError(e);
      return false;
    }
    if (toast != null) {
      final entry = _UndoEntry(changes);
      showToast(s.t(toast, toastParams), onUndo: undo ? () => _undo(entry) : null);
    }
    return true;
  }

  Future<void> _undo(_UndoEntry e) async {
    // Put back what each order was before, starting from what is stored now.
    final back = <OrderChange>[];
    for (final c in e.redo.reversed) {
      // What was saved is what is stored now (the screens may not have reloaded yet).
      final now = c.after;
      final before = c.before;
      if (before == null) {
        back.add(OrderChange(now, now.copyWith(deleted: true, deletedReason: s.t('toast.undoneNew'))));
      } else {
        back.add(OrderChange(now, before));
      }
    }
    try {
      await repo.saveOrders(back, cacheOf);
      showToast(s.t('toast.undone'));
    } catch (err) {
      showError(err);
    }
  }

  /// Runs a domain action result: saves it, or shows why it was refused.
  Future<bool> apply(OrderInput before, ActionResult r, {String? toast, Map<String, Object?> toastParams = const {}}) async {
    if (!r.ok) {
      showToast(r.errors.map(s.error).join(' '), error: true);
      return false;
    }
    final changes = <OrderChange>[OrderChange(before, r.order!)];
    if (r.target != null) changes.add(OrderChange(orderById(r.target!.id), r.target!));
    final ok = await save(changes, toast: toast, toastParams: toastParams);
    if (ok && r.completed) {
      final ev = evaluate(r.order!);
      final days = r.order!.receivedDate == null ? 0 : activeDays(r.order!.receivedDate!, today, r.order!.holdPeriods);
      showToast('${s.t('toast.orderCompleted')} · ${s.t('toast.orderCompletedBody', {'count': ev.total, 'days': days})}');
    }
    return ok;
  }

  // ---------------------------------------------------------------- messages

  void showToast(String text, {VoidCallback? onUndo, bool error = false}) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: error ? 7 : 5),
      backgroundColor: error ? const Color(0xFF8C1D17) : null,
      showCloseIcon: error,
      action: onUndo == null ? null : SnackBarAction(label: s.t('common.undo'), onPressed: onUndo),
    ));
  }

  void showError(Object e) {
    if (e is RepoException) {
      showToast(s.t(e.key, e.params), error: true);
    } else {
      showToast(s.t('toast.saveFailed', {'reason': '$e'}), error: true);
    }
  }

  void refresh() => notifyListeners();

  // ---------------------------------------------------------------- navigation

  /// Main screens, in menu order.
  static const destinations = ['today', 'board', 'pipeline', 'followUp', 'orders', 'reports', 'settings'];
  String screen = 'today';
  String? selectedOrderId; // Today's right-hand pane on a wide screen
  FilterCriteria? ordersFilter; // set when another screen opens a filtered list
  String? ordersFilterTitle;

  void go(String to) {
    screen = to;
    notifyListeners();
  }

  void showOrders(FilterCriteria f, {String? title}) {
    ordersFilter = f;
    ordersFilterTitle = title;
    screen = 'orders';
    notifyListeners();
  }

  void select(String? id) {
    selectedOrderId = id;
    notifyListeners();
  }
}
