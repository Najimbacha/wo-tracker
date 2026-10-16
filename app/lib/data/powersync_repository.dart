// The real data store: a database on this device (PowerSync / SQLite) that works with
// no internet and syncs with Supabase when it can. See repository.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite_async.dart' show SqliteReadContext, SqliteWriteContext;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../domain/order_input.dart';
import 'connector.dart';
import 'ids.dart';
import 'models.dart';
import 'order_rows.dart';
import 'repository.dart';
import 'schema.dart';

const _syncedTables = [
  'contractors', 'districts', 'cable_sizes', 'work_orders', 'permits', 'segments', 'meters', 'cable_runs',
  'steps', 'hold_periods', 'attachments', 'reminders', 'followups', 'saved_views', 'settings',
];

/// The one settings row (same id on every device; this app has one user).
final String settingsId = StepIds.settingsRowId('wo-tracker');

bool _supabaseStarted = false;

/// Supabase has been started in this run (it can't be started again with new addresses).
bool get supabaseStarted => _supabaseStarted;

class PowerSyncRepository extends Repository {
  PowerSyncRepository._(this.db, this.config, this.segmentStepKeys, this.photosDir);

  final PowerSyncDatabase db;
  final SyncConfig? config;
  final Set<String> segmentStepKeys;
  final String photosDir; // the pictures taken or picked on this device

  final _data = StreamController<RepoData>.broadcast();
  final _sync = StreamController<SyncInfo>.broadcast();
  final _refusedCtl = StreamController<List<RefusedChange>>.broadcast();
  RepoData _current = const RepoData();
  List<RefusedChange> _refusedNow = const [];
  SyncInfo _syncInfo = const SyncInfo();
  final List<StreamSubscription<Object?>> _subs = [];
  SupabaseConnector? _connector;
  Timer? _reloadTimer;
  bool _reloading = false;
  bool _reloadAgain = false;

  // Name → id for contractors and districts (rows include deleted ones).
  Map<String, String> _contractorIds = {};
  Map<String, String> _districtIds = {};

  bool _cloudReady = false; // Supabase started with the saved addresses
  String? _cloudError;
  bool get _online => config != null && config!.complete && _cloudReady;

  static Future<PowerSyncRepository> open({required String path, SyncConfig? config, required Set<String> segmentStepKeys, required String photosDir}) async {
    final db = PowerSyncDatabase(schema: appSchema, path: path);
    await db.initialize();
    final repo = PowerSyncRepository._(db, config, segmentStepKeys, photosDir);
    await repo._start();
    return repo;
  }

  Future<void> _start() async {
    _subs.add(db.watch('SELECT 1', triggerOnTables: _syncedTables, throttle: const Duration(milliseconds: 250)).listen((_) => _scheduleReload()));
    _subs.add(db.watch('SELECT * FROM refused_changes ORDER BY at DESC').listen((rs) {
      _refusedCtl.add(_refusedNow = [
        for (final r in rs)
          RefusedChange(
            id: r['id'] as String,
            table: r['table_name'] as String,
            rowId: r['row_id'] as String,
            op: r['op'] as String,
            data: _decodeMap(r['data'] as String?),
            code: r['code'] as String,
            value: r['value'] as String?,
            message: r['message'] as String?,
            at: DateTime.tryParse(r['at'] as String? ?? '') ?? DateTime.now(),
            workOrderId: r['work_order_id'] as String?,
          ),
      ]);
    }));
    _subs.add(db.statusStream.listen((_) => _refreshSync()));
    await _reload();

    if (config != null && config!.complete) {
      // A wrong address must never hide the data on this device: the app carries on
      // offline and Settings shows what went wrong.
      try {
        // Supabase starts once per run of the app (Demo mode on/off reopens this store).
        if (!_supabaseStarted) {
          await Supabase.initialize(url: config!.supabaseUrl.trim(), anonKey: config!.anonKey.trim());
          _supabaseStarted = true;
        }
        _cloudReady = true;
        _subs.add(Supabase.instance.client.auth.onAuthStateChange.listen((s) async {
          try {
            if (s.event == AuthChangeEvent.signedIn) {
              await _connect();
            } else if (s.event == AuthChangeEvent.signedOut) {
              _connector = null;
              await db.disconnect();
            } else if (s.event == AuthChangeEvent.tokenRefreshed) {
              unawaited(_connector?.prefetchCredentials());
            }
          } catch (e) {
            _cloudError = '$e';
          }
          await _refreshSync();
        }));
        if (Supabase.instance.client.auth.currentSession != null) await _connect();
      } catch (e) {
        _cloudError = '$e';
      }
    }
    await _refreshSync();
  }

  Future<void> _connect() async {
    _connector = SupabaseConnector(config!.powersyncUrl.trim());
    await db.connect(connector: _connector!);
  }

  static Map<String, dynamic> _decodeMap(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      final v = jsonDecode(s);
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } on FormatException {
      return {};
    }
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 60), () {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    if (_reloading) {
      _reloadAgain = true;
      return;
    }
    _reloading = true;
    try {
      do {
        _reloadAgain = false;
        _current = await _load();
        _data.add(_current);
      } while (_reloadAgain);
    } finally {
      _reloading = false;
    }
    unawaited(_refreshSync());
  }

  Future<RepoData> _load() async {
    final contractorsRows = await db.getAll('SELECT * FROM contractors');
    final districtRows = await db.getAll('SELECT * FROM districts');
    final contractors = [
      for (final r in contractorsRows)
        Contractor(
            id: r['id'] as String,
            name: r['name'] as String? ?? '',
            phone: r['phone'] as String?,
            active: r['active'] == null || r['active'] == 1,
            deleted: r['deleted_at'] != null),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final districts = [
      for (final r in districtRows) District(id: r['id'] as String, name: r['name'] as String? ?? '', deleted: r['deleted_at'] != null),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final contractorName = {for (final c in contractors) c.id: c.name};
    final districtName = {for (final d in districts) d.id: d.name};
    // Name → id. A removed contractor/district still maps to its old row (so an order
    // that names it keeps pointing at it); a live one with the same name wins.
    _contractorIds = {
      for (final c in contractors.where((c) => c.deleted)) nameKey(c.name): c.id,
      for (final c in contractors.where((c) => !c.deleted)) nameKey(c.name): c.id,
    };
    _districtIds = {
      for (final d in districts.where((d) => d.deleted)) nameKey(d.name): d.id,
      for (final d in districts.where((d) => !d.deleted)) nameKey(d.name): d.id,
    };

    Map<String, List<Map<String, Object?>>> byOrder(Iterable<Map<String, Object?>> rows) {
      final m = <String, List<Map<String, Object?>>>{};
      for (final r in rows) {
        (m[r['work_order_id'] as String? ?? ''] ??= []).add(r);
      }
      return m;
    }

    List<Map<String, Object?>> rows(Iterable<Map<String, dynamic>> rs) => [for (final r in rs) Map<String, Object?>.from(r)];
    final permits = byOrder(rows(await db.getAll('SELECT * FROM permits')));
    final segments = byOrder(rows(await db.getAll('SELECT * FROM segments')));
    final meters = byOrder(rows(await db.getAll('SELECT * FROM meters')));
    final cables = byOrder(rows(await db.getAll('SELECT * FROM cable_runs')));
    final steps = byOrder(rows(await db.getAll('SELECT * FROM steps')));
    final holds = byOrder(rows(await db.getAll('SELECT * FROM hold_periods')));
    final orders = <OrderInput>[];
    for (final o in rows(await db.getAll('SELECT * FROM work_orders'))) {
      final id = o['id'] as String;
      try {
        orders.add(orderFromRows(
          OrderRows(o,
              segments: segments[id] ?? const [],
              meters: meters[id] ?? const [],
              cableRuns: cables[id] ?? const [],
              permits: permits[id] ?? const [],
              holds: holds[id] ?? const [],
              steps: steps[id] ?? const []),
          contractorName: contractorName[o['contractor_id']],
          districtName: districtName[o['district_id']],
        ));
      } catch (_) {
        // A half-synced row (e.g. a child arrived before its order finished) is skipped
        // until the next sync completes it; nothing is lost.
      }
    }

    final sizes = [
      for (final r in await db.getAll('SELECT * FROM cable_sizes WHERE deleted_at IS NULL'))
        CableSize(id: r['id'] as String, sizeMm2: (r['size_mm2'] as num?)?.toInt() ?? 0),
    ]..sort((a, b) => a.sizeMm2 - b.sizeMm2);
    final views = [
      for (final r in await db.getAll('SELECT * FROM saved_views WHERE deleted_at IS NULL ORDER BY sort_order, name'))
        SavedView(id: r['id'] as String, name: r['name'] as String? ?? '', filter: _decodeMap(r['filter'] as String?), sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0),
    ];
    final followUps = [
      for (final r in await db.getAll('SELECT * FROM followups WHERE deleted_at IS NULL'))
        FollowUpRecord(
            id: r['id'] as String,
            contractorId: r['contractor_id'] as String? ?? '',
            followedAt: DateTime.tryParse(r['followed_at'] as String? ?? '') ?? DateTime.now(),
            note: r['note'] as String?),
    ];
    final attachments = [
      for (final r in await db.getAll("SELECT * FROM attachments WHERE deleted_at IS NULL AND kind = 'photo' ORDER BY taken_at, created_at"))
        StepPhoto(
            id: r['id'] as String,
            orderId: r['work_order_id'] as String? ?? '',
            stepRowId: r['step_id'] as String?,
            fileName: r['file_name'] as String? ?? '',
            takenAt: DateTime.tryParse(r['taken_at'] as String? ?? '') ?? DateTime.now(),
            driveFileId: r['drive_file_id'] as String?),
    ];
    final reminders = [
      for (final r in await db.getAll('SELECT * FROM reminders WHERE deleted_at IS NULL ORDER BY due_date, created_at'))
        Reminder(
            id: r['id'] as String,
            orderId: r['work_order_id'] as String? ?? '',
            due: (r['due_date'] as String? ?? '').split('T').first,
            note: r['note'] as String? ?? '',
            done: r['done_at'] != null),
    ];
    final st = await db.getOptional('SELECT * FROM settings WHERE deleted_at IS NULL ORDER BY id = ? DESC LIMIT 1', [settingsId]);
    var settings = const AppSettings();
    if (st != null) {
      final overrides = _decodeMap(st['alert_overrides'] as String?);
      settings = AppSettings(
        alertOverrides: {for (final e in overrides.entries) if (e.value is num) e.key: (e.value as num).toInt()},
        preparedBy: st['prepared_by'] as String? ?? 'Engr Najim',
        language: st['language'] as String? ?? 'en',
        showHijri: st['show_hijri'] == null || st['show_hijri'] == 1,
      );
    }
    return RepoData(
      orders: orders,
      contractors: contractors,
      districts: districts,
      cableSizes: sizes,
      views: views,
      followUps: followUps,
      attachments: attachments,
      reminders: reminders,
      settings: settings,
      loaded: true,
    );
  }

  Future<void> _refreshSync() async {
    final s = db.currentStatus;
    var pending = 0;
    try {
      pending = (await db.getUploadQueueStats()).count;
    } catch (_) {}
    final session = _online ? Supabase.instance.client.auth.currentSession : null;
    final err = s.downloadError ?? s.uploadError;
    _syncInfo = SyncInfo(
      configured: _online,
      signedIn: session != null,
      connected: s.connected,
      connecting: s.connecting,
      uploading: s.uploading,
      downloading: s.downloading,
      lastSyncedAt: s.lastSyncedAt,
      pendingChanges: pending,
      error: err?.toString() ?? _cloudError,
      userEmail: session?.user.email,
    );
    _sync.add(_syncInfo);
  }

  @override
  bool get isDemo => false;
  @override
  Stream<RepoData> get data => _data.stream;
  @override
  RepoData get current => _current;
  @override
  Stream<SyncInfo> get syncInfo => _sync.stream;
  @override
  SyncInfo get currentSync => _syncInfo;
  @override
  Stream<List<RefusedChange>> get refused => _refusedCtl.stream;
  @override
  List<RefusedChange> get currentRefused => _refusedNow;

  String get _now => DateTime.now().toUtc().toIso8601String();

  // ---------------------------------------------------------------- writes

  /// A new row gets created_at here too (the server sets its own, which is never sent
  /// up), so new segments and cable runs keep the order they were added in before they
  /// sync. Rows added in one save get times a microsecond apart.
  int _stampSeq = 0;
  String _createdAt() => DateTime.now().toUtc().add(Duration(microseconds: _stampSeq++ % 1000)).toIso8601String();

  Future<void> _insert(SqliteWriteContext tx, RowWrite w) {
    final values = {...w.values, if (!w.values.containsKey('created_at')) 'created_at': _createdAt()};
    final cols = values.keys.toList();
    return tx.execute(
      'INSERT INTO ${w.table} (id, ${cols.join(', ')}) VALUES (?${', ?' * cols.length})',
      [w.id, ...cols.map((c) => values[c])],
    );
  }

  Future<void> _apply(SqliteWriteContext tx, RowWrite w) async {
    final cols = w.values.keys.toList();
    if (w.kind == 'insert') {
      await _insert(tx, w);
      return;
    }
    if (w.kind == 'upsert') {
      final exists = await tx.getOptional('SELECT id FROM ${w.table} WHERE id = ?', [w.id]);
      if (exists == null) {
        await _insert(tx, w);
        return;
      }
    }
    if (cols.isEmpty) return;
    await tx.execute(
      'UPDATE ${w.table} SET ${cols.map((c) => '$c = ?').join(', ')} WHERE id = ?',
      [...cols.map((c) => w.values[c]), w.id],
    );
  }

  /// Id of the contractor/district with this name, creating it if new (inside [tx]).
  Future<String?> _refId(SqliteWriteContext tx, String table, Map<String, String> ids, String? name) async {
    if (name == null || name.trim().isEmpty) return null;
    final k = nameKey(name);
    final found = ids[k];
    if (found != null) return found;
    final id = await _nameId(tx, table, name);
    await tx.execute('INSERT INTO $table (id, name${table == 'contractors' ? ', active' : ''}) VALUES (?, ?${table == 'contractors' ? ', 1' : ''})', [id, name.trim()]);
    ids[k] = id;
    return id;
  }

  /// Same id on every device for the same name (see StepIds.nameRowId). If that id is
  /// already taken (the name was used before and the row renamed since), a new one.
  Future<String> _nameId(SqliteReadContext tx, String table, String name) async {
    final id = StepIds.nameRowId(table, name);
    final taken = await tx.getOptional('SELECT id FROM $table WHERE id = ?', [id]);
    return taken == null ? id : newId();
  }

  @override
  Future<void> saveOrders(List<OrderChange> changes, OrderCache Function(OrderInput) cacheOf) async {
    // New contractors/districts made while saving only count once the save succeeds.
    final conIds = Map<String, String>.of(_contractorIds);
    final disIds = Map<String, String>.of(_districtIds);
    await db.writeTransaction((tx) async {
      for (final c in changes) {
        final after = c.after.id == null ? c.after.copyWith(id: newId()) : c.after;
        final before = c.before;
        final writes = orderWrites(
          before,
          after,
          contractorId: await _refId(tx, 'contractors', conIds, after.contractor),
          districtId: await _refId(tx, 'districts', disIds, after.district),
          beforeContractorId: before?.contractor == null ? null : conIds[nameKey(before!.contractor!)],
          beforeDistrictId: before?.district == null ? null : disIds[nameKey(before!.district!)],
          cache: cacheOf(after),
          beforeCache: before == null ? null : cacheOf(before),
          nowIso: _now,
          newId: newId,
          segmentStepKeys: segmentStepKeys,
        );
        for (final w in writes) {
          await _apply(tx, w);
        }
      }
    });
    _contractorIds = conIds;
    _districtIds = disIds;
  }

  @override
  Future<Contractor> addContractor(String name, {String? phone}) async {
    if (_current.contractors.any((x) => !x.deleted && nameKey(x.name) == nameKey(name))) {
      throw RepoException('settings.contractorExists', {'name': name.trim()});
    }
    final c = Contractor(id: await _nameId(db, 'contractors', name), name: name.trim(), phone: phone);
    await db.execute('INSERT INTO contractors (id, name, phone, active) VALUES (?, ?, ?, 1)', [c.id, c.name, phone]);
    return c;
  }

  @override
  Future<void> updateContractor(Contractor c) async {
    final clash = _current.contractors.any((x) => !x.deleted && x.id != c.id && nameKey(x.name) == nameKey(c.name));
    if (clash) throw RepoException('settings.contractorExists', {'name': c.name.trim()});
    await db.execute('UPDATE contractors SET name = ?, phone = ?, active = ?, deleted_at = ? WHERE id = ?',
        [c.name.trim(), c.phone, c.active ? 1 : 0, c.deleted ? _now : null, c.id]);
  }

  @override
  Future<District> addDistrict(String name) async {
    for (final x in _current.districts) {
      if (!x.deleted && nameKey(x.name) == nameKey(name)) return x;
    }
    final d = District(id: await _nameId(db, 'districts', name), name: name.trim());
    await db.execute('INSERT INTO districts (id, name) VALUES (?, ?)', [d.id, d.name]);
    return d;
  }

  @override
  Future<void> renameDistrict(String id, String name) async {
    final clash = _current.districts.any((x) => !x.deleted && x.id != id && nameKey(x.name) == nameKey(name));
    if (clash) throw RepoException('settings.districtExists', {'name': name.trim()});
    await db.execute('UPDATE districts SET name = ? WHERE id = ?', [name.trim(), id]);
  }

  @override
  Future<void> addCableSize(int sizeMm2) async {
    final exists = await db.getOptional('SELECT id FROM cable_sizes WHERE size_mm2 = ? AND deleted_at IS NULL', [sizeMm2]);
    if (exists != null) return;
    // Same id on every device for the same size; a removed size comes back on its own row.
    final id = StepIds.cableSizeRowId(sizeMm2);
    final old = await db.getOptional('SELECT id FROM cable_sizes WHERE id = ?', [id]);
    if (old != null) {
      await db.execute('UPDATE cable_sizes SET deleted_at = NULL, size_mm2 = ? WHERE id = ?', [sizeMm2, id]);
    } else {
      await db.execute('INSERT INTO cable_sizes (id, size_mm2) VALUES (?, ?)', [id, sizeMm2]);
    }
  }

  @override
  Future<void> removeCableSize(String id) => db.execute('UPDATE cable_sizes SET deleted_at = ? WHERE id = ?', [_now, id]);

  @override
  Future<void> saveSettings(AppSettings s) async {
    final values = [jsonEncode(s.alertOverrides), s.preparedBy, s.language, s.showHijri ? 1 : 0];
    await db.writeTransaction((tx) async {
      final exists = await tx.getOptional('SELECT id FROM settings WHERE id = ?', [settingsId]);
      if (exists == null) {
        await tx.execute('INSERT INTO settings (id, alert_overrides, prepared_by, language, show_hijri) VALUES (?, ?, ?, ?, ?)', [settingsId, ...values]);
      } else {
        await tx.execute('UPDATE settings SET alert_overrides = ?, prepared_by = ?, language = ?, show_hijri = ? WHERE id = ?', [...values, settingsId]);
      }
    });
  }

  @override
  Future<void> saveView(SavedView v) async {
    await db.writeTransaction((tx) async {
      final exists = await tx.getOptional('SELECT id FROM saved_views WHERE id = ?', [v.id]);
      if (exists == null) {
        await tx.execute('INSERT INTO saved_views (id, name, filter, sort_order) VALUES (?, ?, ?, ?)', [v.id, v.name, jsonEncode(v.filter), v.sortOrder]);
      } else {
        await tx.execute('UPDATE saved_views SET name = ?, filter = ?, sort_order = ? WHERE id = ?', [v.name, jsonEncode(v.filter), v.sortOrder, v.id]);
      }
    });
  }

  @override
  Future<void> deleteView(String id) => db.execute('UPDATE saved_views SET deleted_at = ? WHERE id = ?', [_now, id]);

  @override
  Future<void> markFollowedUp(String contractorId, {String? note}) =>
      db.execute('INSERT INTO followups (id, contractor_id, followed_at, note) VALUES (?, ?, ?, ?)', [newId(), contractorId, _now, note]);

  // ---------------------------------------------------------------- photos

  static String _ext(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    final e = dot <= 0 ? '' : name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(e) ? e : '.jpg';
  }

  String _local(String id, String fileName) => '$photosDir/$id${_ext(fileName)}';

  @override
  String? photoPath(StepPhoto a) {
    final path = _local(a.id, a.fileName);
    return File(path).existsSync() ? path : null;
  }

  @override
  Future<StepPhoto> addPhoto({required OrderInput order, required String? stepKey, required String sourcePath, required String label}) async {
    final orderId = order.id;
    if (orderId == null) throw const RepoException('photo.saveOrderFirst');
    final id = newId();
    final now = DateTime.now();
    final stamp = now.toIso8601String().substring(0, 19).replaceAll(':', '').replaceAll('-', '').replaceAll('T', '-');
    final fileName = '${label.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')}_$stamp${_ext(sourcePath)}';
    // Copy first: if this fails nothing is written. The original is never touched.
    await Directory(photosDir).create(recursive: true);
    final dest = _local(id, fileName);
    await File(sourcePath).copy(dest);
    try {
      await db.writeTransaction((tx) async {
        String? stepId;
        if (stepKey != null) {
          final ref = splitStepKey(stepKey, segmentStepKeys);
          stepId = StepIds.stepRowId(orderId, ref.stepKey, segmentId: ref.segmentId, meterId: ref.meterId);
          // A photo may come before the step is marked: the step needs its row first (the
          // server refuses a photo pointing at a step it has not got). An empty row means "not done".
          final have = await tx.getOptional('SELECT id FROM steps WHERE id = ?', [stepId]);
          if (have == null) {
            await _insert(
                tx,
                RowWrite('steps', stepId, 'insert', {
                  'work_order_id': orderId,
                  'step_key': ref.stepKey,
                  'segment_id': ref.segmentId,
                  'meter_id': ref.meterId,
                  'not_applicable': 0,
                }));
          } else {
            // A cleared step may be hidden (deleted_at): a photo brings it back as an empty row.
            await tx.execute('UPDATE steps SET deleted_at = NULL WHERE id = ? AND deleted_at IS NOT NULL', [stepId]);
          }
        }
        await _insert(
            tx,
            RowWrite('attachments', id, 'insert', {
              'work_order_id': orderId,
              'step_id': stepId,
              'kind': 'photo',
              'file_name': fileName,
              'taken_at': now.toUtc().toIso8601String(),
            }));
      });
    } catch (_) {
      try {
        await File(dest).delete();
      } catch (_) {}
      rethrow;
    }
    return StepPhoto(id: id, orderId: orderId, fileName: fileName, takenAt: now);
  }

  @override
  Future<void> addReminder({required String orderId, required String due, required String note}) =>
      db.execute('INSERT INTO reminders (id, work_order_id, due_date, note) VALUES (?, ?, ?, ?)', [newId(), orderId, due, note.trim()]);

  @override
  Future<void> setReminderDone(String id, bool done) => db.execute('UPDATE reminders SET done_at = ? WHERE id = ?', [done ? _now : null, id]);

  @override
  Future<void> removeReminder(String id) => db.execute('UPDATE reminders SET deleted_at = ? WHERE id = ?', [_now, id]);

  @override
  Future<void> removePhoto(String id) => db.execute('UPDATE attachments SET deleted_at = ? WHERE id = ?', [_now, id]);

  // ---------------------------------------------------------------- refused changes

  /// Sends the refused change to the server again (needs internet). If the server
  /// takes it this time, it leaves the list; otherwise the new reason is shown.
  @override
  Future<void> retryRefused(String id) async {
    final r = await db.getOptional('SELECT * FROM refused_changes WHERE id = ?', [id]);
    if (r == null) return;
    if (!_online || Supabase.instance.client.auth.currentSession == null) throw const RepoException('sync.signInFirst');
    final table = r['table_name'] as String;
    final rowId = r['row_id'] as String;
    try {
      // Send the row as it is on this device now (including any fix made since), so
      // the server ends up exactly like this device.
      final sent = await SupabaseConnector.upsertLocalRow(db, table, rowId).timeout(const Duration(seconds: 20));
      if (!sent) {
        final data = SupabaseConnector.toServer(table, _decodeMap(r['data'] as String?))..remove('id');
        await Supabase.instance.client.from(table).upsert({...data, 'id': rowId}).timeout(const Duration(seconds: 20));
      }
    } on PostgrestException catch (e) {
      await db.execute('UPDATE refused_changes SET message = ?, at = ? WHERE id = ?', [e.message, _now, id]);
      throw RepoException('refused.stillRefused', {'message': e.message});
    } catch (_) {
      throw const RepoException('sync.signInOffline');
    }
    await SupabaseConnector.clearRefused(db, rowId);
  }

  @override
  Future<void> dismissRefused(String id) async {
    // "Undo my change": this device goes back to what the server has (needs internet to
    // know it). If the server never had the row (a new order it refused), the row is
    // moved to Deleted here; nothing is erased and it can still be restored.
    final r = await db.getOptional('SELECT * FROM refused_changes WHERE id = ?', [id]);
    if (r == null) return;
    if (!_online || Supabase.instance.client.auth.currentSession == null) throw const RepoException('sync.signInFirst');
    final table = r['table_name'] as String;
    final rowId = r['row_id'] as String;
    Map<String, dynamic>? server;
    try {
      server = await Supabase.instance.client.from(table).select().eq('id', rowId).maybeSingle().timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const RepoException('sync.signInOffline');
    }
    final cols = appSchema.tables.firstWhere((t) => t.name == table).columns.map((c) => c.name).toList();
    await db.writeTransaction((tx) async {
      if (server == null) {
        await tx.execute('UPDATE $table SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL', [_now, rowId]);
      } else {
        final values = [
          for (final c in cols)
            switch (server[c]) {
              final bool b => b ? 1 : 0,
              final Map<dynamic, dynamic> m => jsonEncode(m),
              final List<dynamic> l => jsonEncode(l),
              final v => v,
            },
        ];
        await tx.execute('UPDATE $table SET ${cols.map((c) => '$c = ?').join(', ')} WHERE id = ?', [...values, rowId]);
      }
      await tx.execute('DELETE FROM refused_changes WHERE row_id = ?', [rowId]);
    });
  }

  // ---------------------------------------------------------------- server-only reads

  @override
  Future<List<HistoryEntry>> history(OrderInput o) async {
    if (!_online || Supabase.instance.client.auth.currentSession == null) throw const RepoException('history.signIn');
    final ids = <String>{o.id!};
    for (final t in ['permits', 'segments', 'meters', 'cable_runs', 'steps', 'hold_periods']) {
      for (final r in await db.getAll('SELECT id FROM $t WHERE work_order_id = ?', [o.id])) {
        ids.add(r['id'] as String);
      }
    }
    try {
      final rows = await Supabase.instance.client
          .from('activity_log')
          .select('table_name, row_id, action, old_data, new_data, changed_at')
          .inFilter('row_id', ids.toList())
          .order('changed_at', ascending: false)
          .limit(300)
          .timeout(const Duration(seconds: 15));
      return [
        for (final r in rows)
          HistoryEntry(
            at: DateTime.tryParse(r['changed_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
            table: r['table_name'] as String? ?? '',
            rowId: r['row_id'] as String? ?? '',
            action: r['action'] as String? ?? '',
            oldData: r['old_data'] is Map ? Map<String, dynamic>.from(r['old_data'] as Map) : const {},
            newData: r['new_data'] is Map ? Map<String, dynamic>.from(r['new_data'] as Map) : const {},
          ),
      ];
    } catch (_) {
      throw const RepoException('history.offline');
    }
  }

  @override
  Future<Map<String, dynamic>?> dataHealth() async {
    if (!_online || Supabase.instance.client.auth.currentSession == null) return null;
    try {
      final v = await Supabase.instance.client.rpc('data_health').timeout(const Duration(seconds: 15));
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- sign-in

  @override
  Future<void> signIn(String email, String password) async {
    if (!_online) throw const RepoException('sync.notConfigured');
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw RepoException('sync.signInFailed', {'message': e.message});
    } catch (_) {
      throw const RepoException('sync.signInOffline');
    }
  }

  @override
  Future<bool> signUp(String email, String password) async {
    if (!_online) throw const RepoException('sync.notConfigured');
    try {
      final r = await Supabase.instance.client.auth.signUp(email: email.trim(), password: password);
      return r.session != null;
    } on AuthException catch (e) {
      throw RepoException('sync.signInFailed', {'message': e.message});
    } catch (_) {
      throw const RepoException('sync.signInOffline');
    }
  }

  @override
  Future<void> signOut() async {
    final pending = (await db.getUploadQueueStats()).count;
    if (pending > 0) throw RepoException('confirm.signOutBlocked', {'count': pending});
    if (_online) await Supabase.instance.client.auth.signOut();
    await db.disconnect();
    await _refreshSync();
  }

  @override
  Future<void> dispose() async {
    _reloadTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await db.close();
    await _data.close();
    await _sync.close();
    await _refusedCtl.close();
  }
}
