// Demo mode: sample orders kept in memory. Everything works (marking steps, reports,
// exports) but nothing is saved and nothing syncs. Closing the app forgets it all.
import 'dart:async';

import '../domain/order_input.dart';
import 'models.dart';
import 'order_rows.dart';
import 'repository.dart';

class MemoryRepository extends Repository {
  MemoryRepository(List<OrderInput> orders) {
    final names = <String>{};
    for (final o in orders) {
      if (o.contractor != null && o.contractor!.trim().isNotEmpty) names.add(o.contractor!.trim());
    }
    final districts = <String>{};
    for (final o in orders) {
      if (o.district != null && o.district!.trim().isNotEmpty) districts.add(o.district!.trim());
    }
    _data = RepoData(
      orders: orders,
      contractors: [for (final n in names.toList()..sort()) Contractor(id: newId(), name: n)],
      districts: [for (final n in districts.toList()..sort()) District(id: newId(), name: n)],
      cableSizes: [for (final s in const [70, 185, 300, 500]) CableSize(id: newId(), sizeMm2: s)],
      settings: const AppSettings(),
      loaded: true,
    );
  }

  late RepoData _data;
  final _controller = StreamController<RepoData>.broadcast();
  final _refused = StreamController<List<RefusedChange>>.broadcast();
  final _sync = StreamController<SyncInfo>.broadcast();

  @override
  bool get isDemo => true;
  @override
  Stream<RepoData> get data => _controller.stream;
  @override
  RepoData get current => _data;
  @override
  Stream<SyncInfo> get syncInfo => _sync.stream;
  @override
  SyncInfo get currentSync => const SyncInfo();
  @override
  Stream<List<RefusedChange>> get refused => _refused.stream;

  void _emit(RepoData d) {
    _data = d;
    _controller.add(d);
  }

  RepoData _copy({
    List<OrderInput>? orders,
    List<Contractor>? contractors,
    List<District>? districts,
    List<CableSize>? cableSizes,
    List<SavedView>? views,
    List<FollowUpRecord>? followUps,
    AppSettings? settings,
  }) =>
      RepoData(
        orders: orders ?? _data.orders,
        contractors: contractors ?? _data.contractors,
        districts: districts ?? _data.districts,
        cableSizes: cableSizes ?? _data.cableSizes,
        views: views ?? _data.views,
        followUps: followUps ?? _data.followUps,
        settings: settings ?? _data.settings,
        loaded: true,
      );

  @override
  Future<void> saveOrders(List<OrderChange> changes, OrderCache Function(OrderInput) cacheOf) async {
    final orders = [..._data.orders];
    var contractors = [..._data.contractors];
    var districts = [..._data.districts];
    for (final c in changes) {
      var after = c.after;
      // Give new child rows ids, as the database would.
      after = after.copyWith(
        id: after.id ?? newId(),
        cableRuns: [for (final r in after.cableRuns) r.id == null ? CableRun(id: newId(), sizeMm2: r.sizeMm2, voltage: r.voltage, lengthM: r.lengthM) : r],
        permits: [
          for (final p in after.permits)
            p.id == null ? Permit(id: newId(), number: p.number, appliedDate: p.appliedDate, startDate: p.startDate, endDate: p.endDate) : p
        ],
        holdPeriods: [for (final h in after.holdPeriods) h.id == null ? HoldPeriod(id: newId(), from: h.from, to: h.to, reason: h.reason, review: h.review) : h],
      );
      final con = after.contractor?.trim();
      if (con != null && con.isNotEmpty && !contractors.any((x) => nameKey(x.name) == nameKey(con))) {
        contractors = [...contractors, Contractor(id: newId(), name: con)];
      }
      final dis = after.district?.trim();
      if (dis != null && dis.isNotEmpty && !districts.any((x) => nameKey(x.name) == nameKey(dis))) {
        districts = [...districts, District(id: newId(), name: dis)];
      }
      final i = orders.indexWhere((o) => o.id == after.id);
      if (i >= 0) {
        orders[i] = after;
      } else {
        orders.add(after);
      }
    }
    _emit(_copy(orders: orders, contractors: contractors, districts: districts));
  }

  @override
  Future<Contractor> addContractor(String name, {String? phone}) async {
    final existing = _data.contractors.where((x) => nameKey(x.name) == nameKey(name) && !x.deleted);
    if (existing.isNotEmpty) throw RepoException('settings.contractorExists', {'name': name.trim()});
    final c = Contractor(id: newId(), name: name.trim(), phone: phone);
    _emit(_copy(contractors: [..._data.contractors, c]));
    return c;
  }

  @override
  Future<void> updateContractor(Contractor c) async {
    final clash = _data.contractors.any((x) => x.id != c.id && !x.deleted && nameKey(x.name) == nameKey(c.name));
    if (clash) throw RepoException('settings.contractorExists', {'name': c.name.trim()});
    final old = _data.contractors.firstWhere((x) => x.id == c.id);
    final orders = old.name == c.name
        ? _data.orders
        : [for (final o in _data.orders) o.contractor == old.name ? o.copyWith(contractor: c.name) : o];
    _emit(_copy(contractors: [for (final x in _data.contractors) x.id == c.id ? c : x], orders: orders));
  }

  @override
  Future<District> addDistrict(String name) async {
    final existing = _data.districts.where((x) => nameKey(x.name) == nameKey(name) && !x.deleted);
    if (existing.isNotEmpty) return existing.first;
    final d = District(id: newId(), name: name.trim());
    _emit(_copy(districts: [..._data.districts, d]));
    return d;
  }

  @override
  Future<void> renameDistrict(String id, String name) async {
    final old = _data.districts.firstWhere((x) => x.id == id);
    _emit(_copy(
      districts: [for (final x in _data.districts) x.id == id ? District(id: id, name: name.trim()) : x],
      orders: [for (final o in _data.orders) o.district == old.name ? o.copyWith(district: name.trim()) : o],
    ));
  }

  @override
  Future<void> addCableSize(int sizeMm2) async {
    if (_data.cableSizes.any((x) => x.sizeMm2 == sizeMm2 && !x.deleted)) return;
    _emit(_copy(cableSizes: [..._data.cableSizes, CableSize(id: newId(), sizeMm2: sizeMm2)]..sort((a, b) => a.sizeMm2 - b.sizeMm2)));
  }

  @override
  Future<void> removeCableSize(String id) async {
    _emit(_copy(cableSizes: [for (final x in _data.cableSizes) if (x.id != id) x]));
  }

  @override
  Future<void> saveSettings(AppSettings s) async => _emit(_copy(settings: s));

  @override
  Future<void> saveView(SavedView v) async {
    final views = [for (final x in _data.views) if (x.id != v.id) x, v];
    _emit(_copy(views: views));
  }

  @override
  Future<void> deleteView(String id) async => _emit(_copy(views: [for (final x in _data.views) if (x.id != id) x]));

  @override
  Future<void> markFollowedUp(String contractorId, {String? note}) async {
    _emit(_copy(followUps: [..._data.followUps, FollowUpRecord(id: newId(), contractorId: contractorId, followedAt: DateTime.now(), note: note)]));
  }

  @override
  Future<void> retryRefused(String id) async {}
  @override
  Future<void> dismissRefused(String id) async {}

  @override
  Future<List<HistoryEntry>> history(OrderInput o) async => const [];

  @override
  Future<Map<String, dynamic>?> dataHealth() async => null;

  @override
  Future<void> signIn(String email, String password) async => throw const RepoException('sync.demoNoSignIn');
  @override
  Future<void> signUp(String email, String password) async => throw const RepoException('sync.demoNoSignIn');
  @override
  Future<void> signOut() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
    await _refused.close();
    await _sync.close();
  }
}
