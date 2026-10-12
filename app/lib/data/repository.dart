// Where the app's data lives. Two kinds:
//   PowerSyncRepository - the real one: a database on this device that syncs with
//                         Supabase whenever there is internet (works fully offline).
//   MemoryRepository    - Demo mode: sample orders in memory, nothing is saved.
// Screens never talk to a database directly; they read RepoData and call these methods.
import 'dart:async';
import 'dart:math';

import '../domain/order_input.dart';
import 'models.dart';
import 'order_rows.dart';

class RepoData {
  final List<OrderInput> orders; // deleted ones included (Deleted orders list), flagged
  final List<Contractor> contractors;
  final List<District> districts;
  final List<CableSize> cableSizes;
  final List<SavedView> views;
  final List<FollowUpRecord> followUps;
  final AppSettings settings;
  final bool loaded;
  const RepoData({
    this.orders = const [],
    this.contractors = const [],
    this.districts = const [],
    this.cableSizes = const [],
    this.views = const [],
    this.followUps = const [],
    this.settings = const AppSettings(),
    this.loaded = false,
  });
}

/// One order change to save: the order as read, and as it should be.
class OrderChange {
  final OrderInput? before;
  final OrderInput after;
  const OrderChange(this.before, this.after);
}

/// Addresses of the online services, entered once in Settings > Sync.
class SyncConfig {
  final String supabaseUrl;
  final String anonKey;
  final String powersyncUrl;
  const SyncConfig({required this.supabaseUrl, required this.anonKey, required this.powersyncUrl});
  bool get complete => supabaseUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty && powersyncUrl.trim().isNotEmpty;
}

/// Thrown for a problem the user should read (already in plain words, key into i18n).
class RepoException implements Exception {
  final String key; // i18n key
  final Map<String, Object?> params;
  const RepoException(this.key, [this.params = const {}]);
  @override
  String toString() => 'RepoException($key, $params)';
}

abstract class Repository {
  /// Everything the screens show; a new value after every change (local or synced).
  Stream<RepoData> get data;
  RepoData get current;

  Stream<SyncInfo> get syncInfo;
  SyncInfo get currentSync;

  Stream<List<RefusedChange>> get refused;

  bool get isDemo;

  /// Saves order changes in one go (all or nothing on this device).
  /// [cacheOf] gives the cached status/stage/progress for an order.
  Future<void> saveOrders(List<OrderChange> changes, OrderCache Function(OrderInput) cacheOf);

  Future<Contractor> addContractor(String name, {String? phone});
  Future<void> updateContractor(Contractor c);
  Future<District> addDistrict(String name);
  Future<void> renameDistrict(String id, String name);
  Future<void> addCableSize(int sizeMm2);
  Future<void> removeCableSize(String id);
  Future<void> saveSettings(AppSettings s);
  Future<void> saveView(SavedView v);
  Future<void> deleteView(String id);
  Future<void> markFollowedUp(String contractorId, {String? note});

  Future<void> retryRefused(String id);
  Future<void> dismissRefused(String id);

  /// The order's history from the server (needs internet). Throws RepoException('history.offline') offline.
  Future<List<HistoryEntry>> history(OrderInput o);

  /// public.data_health() from the server, or null offline.
  Future<Map<String, dynamic>?> dataHealth();

  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();

  Future<void> dispose();

  String newId() => uuidV4();
}

final _rand = Random.secure();

/// A random (version 4) UUID.
String uuidV4() {
  final b = List<int>.generate(16, (_) => _rand.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String nameKey(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
