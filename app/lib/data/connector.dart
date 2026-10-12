// Uploads this device's changes to Supabase, and gives PowerSync the sign-in token.
//
// Every refused upload is sorted (data/upload_errors.dart):
//   retry    → rethrow; PowerSync tries the whole batch again later (writes are
//              idempotent: inserts are upserts by id, updates set values).
//   sign_in  → refresh the session, then retry.
//   decision → the change is copied to the refused_changes table on this device and
//              the queue moves on, so one bad change never blocks the others.
import 'dart:async';
import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart';
import 'schema.dart';
import 'upload_errors.dart';

class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector(this.powersyncUrl);

  final String powersyncUrl;
  Future<void>? _refresh;
  final Map<String, int> _attempts = {}; // failures per queued change, for "parent not synced yet"
  final Set<String> _decided = {}; // already moved to refused_changes (the batch may be retried)

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    await _refresh;
    final session = _client.auth.currentSession;
    if (session == null) return null;
    final expiresAt = session.expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000);
    return PowerSyncCredentials(endpoint: powersyncUrl, token: session.accessToken, userId: session.user.id, expiresAt: expiresAt);
  }

  @override
  void invalidateCredentials() {
    _refresh = _client.auth.refreshSession().timeout(const Duration(seconds: 5)).then((_) => null, onError: (Object _) => null);
  }

  /// Device values → what Postgres expects (0/1 → true/false, JSON text → JSON).
  static Map<String, dynamic> toServer(String table, Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    final bools = boolColumns[table] ?? const <String>{};
    final jsons = jsonColumns[table] ?? const <String>{};
    for (final e in data.entries) {
      if (serverColumns.contains(e.key)) continue;
      var v = e.value;
      if (bools.contains(e.key) && v != null) v = v == 1 || v == true || v == '1' || v == 'true';
      if (jsons.contains(e.key) && v is String) {
        try {
          v = jsonDecode(v);
        } on FormatException {
          v = <String, dynamic>{};
        }
      }
      out[e.key] = v;
    }
    return out;
  }

  static UploadError _asUploadError(Object e) {
    if (e is PostgrestException) {
      final code = e.code ?? '';
      final http = RegExp(r'^\d{3}$').hasMatch(code);
      return UploadError(
        status: http ? int.parse(code) : null,
        code: http ? null : code,
        message: e.message,
        details: e.details?.toString(),
      );
    }
    if (e is AuthException) return const UploadError(status: 401, code: 'PGRST301', message: 'Signed out');
    return const UploadError(network: true);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final tx = await database.getNextCrudTransaction();
    if (tx == null) return;
    final rest = _client.rest;
    for (final op in tx.crud) {
      final key = '${op.table}/${op.id}/${op.clientId}';
      if (_decided.contains(key)) continue;
      try {
        final table = rest.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            await table.upsert({...toServer(op.table, Map<String, dynamic>.from(op.opData ?? const {})), 'id': op.id});
          case UpdateType.patch:
            final data = toServer(op.table, Map<String, dynamic>.from(op.opData ?? const {}));
            if (data.isNotEmpty) await table.update(data).eq('id', op.id);
          case UpdateType.delete:
            // The app never deletes; if it ever happens, keep the row and mark it deleted.
            await table.update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', op.id);
        }
        _attempts.remove(key);
      } catch (e) {
        final attempt = (_attempts[key] ?? 0) + 1;
        _attempts[key] = attempt;
        final verdict = UploadErrors.classify(_asUploadError(e), attempt: attempt, row: op.opData?.cast<String, Object?>());
        if (verdict.action == 'sign_in') {
          invalidateCredentials();
          rethrow;
        }
        if (verdict.action == 'retry') rethrow;
        // Needs the user's decision: keep the change on this device, let the queue go on.
        _attempts.remove(key);
        _decided.add(key);
        final data = op.opData ?? const <String, dynamic>{};
        final orderId = op.table == 'work_orders' ? op.id : data['work_order_id'] as String?;
        await database.execute(
          'INSERT INTO refused_changes (id, table_name, row_id, op, data, code, value, message, at, work_order_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            uuidV4(),
            op.table,
            op.id,
            op.op.name.toUpperCase(),
            jsonEncode(data),
            verdict.code,
            verdict.value,
            verdict.message ?? (e is PostgrestException ? e.message : e.toString()),
            DateTime.now().toUtc().toIso8601String(),
            orderId,
          ],
        );
      }
    }
    await tx.complete();
    _decided.clear();
  }
}
