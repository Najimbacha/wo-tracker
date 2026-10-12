// The device's copy of the database (PowerSync, SQLite). Same tables and columns as
// supabase/migrations, minus owner_id (set by the server). activity_log is not synced.
import 'package:powersync/powersync.dart';

/// Columns that are true/false in Postgres but 0/1 in SQLite.
const boolColumns = <String, Set<String>>{
  'contractors': {'active'},
  'work_orders': {'needs_excavation'},
  'segments': {'tiled'},
  'steps': {'not_applicable'},
  'settings': {'show_hijri'},
};

/// Columns stored as JSON text on the device and jsonb on the server.
const jsonColumns = <String, Set<String>>{
  'saved_views': {'filter'},
  'settings': {'alert_overrides'},
};

/// Columns the device never sends: the server sets them.
const serverColumns = {'owner_id', 'created_at', 'updated_at'};

const _stamps = [Column.text('created_at'), Column.text('updated_at'), Column.text('deleted_at')];

final Schema appSchema = Schema([
  const Table('contractors', [Column.text('name'), Column.text('phone'), Column.integer('active'), ..._stamps], ignoreEmptyUpdates: true),
  const Table('districts', [Column.text('name'), ..._stamps], ignoreEmptyUpdates: true),
  const Table('cable_sizes', [Column.integer('size_mm2'), ..._stamps], ignoreEmptyUpdates: true),
  const Table(
    'work_orders',
    [
      Column.text('wo_number'),
      Column.text('category'),
      Column.text('type_code'),
      Column.text('received_date'),
      Column.text('district_id'),
      Column.text('street'),
      Column.text('network_ref'),
      Column.text('contractor_id'),
      Column.integer('needs_excavation'),
      Column.text('state'),
      Column.text('state_reason'),
      Column.text('state_date'),
      Column.text('merged_into'),
      Column.text('notes'),
      Column.integer('rules_version'),
      Column.text('status_cache'),
      Column.text('stage_cache'),
      Column.integer('progress_closed'),
      Column.integer('progress_total'),
      Column.text('last_change_date'),
      Column.text('deleted_reason'),
      ..._stamps,
    ],
    indexes: [
      Index('by_number', [IndexedColumn('wo_number')]),
      Index('by_received', [IndexedColumn('received_date')]),
    ],
    ignoreEmptyUpdates: true,
  ),
  const Table(
    'permits',
    [Column.text('work_order_id'), Column.text('permit_number'), Column.text('applied_date'), Column.text('start_date'), Column.text('end_date'), ..._stamps],
    indexes: [Index('by_order', [IndexedColumn('work_order_id')])],
    ignoreEmptyUpdates: true,
  ),
  const Table(
    'segments',
    [Column.text('work_order_id'), Column.text('base'), Column.integer('width_cm'), Column.real('length_m'), Column.integer('tiled'), ..._stamps],
    indexes: [Index('by_order', [IndexedColumn('work_order_id')])],
    ignoreEmptyUpdates: true,
  ),
  const Table(
    'meters',
    [
      Column.text('work_order_id'),
      Column.integer('seq'),
      Column.text('meter_number'),
      Column.text('meter_type'),
      Column.integer('breaker_amps'),
      Column.text('old_meter_number'),
      ..._stamps,
    ],
    indexes: [Index('by_order', [IndexedColumn('work_order_id')])],
    ignoreEmptyUpdates: true,
  ),
  const Table(
    'cable_runs',
    [Column.text('work_order_id'), Column.integer('size_mm2'), Column.text('voltage'), Column.real('length_m'), ..._stamps],
    indexes: [Index('by_order', [IndexedColumn('work_order_id')])],
    ignoreEmptyUpdates: true,
  ),
  const Table(
    'steps',
    [
      Column.text('work_order_id'),
      Column.text('step_key'),
      Column.text('segment_id'),
      Column.text('meter_id'),
      Column.text('done_date'),
      Column.integer('not_applicable'),
      Column.text('na_reason'),
      Column.text('note'),
      ..._stamps,
    ],
    indexes: [Index('by_order', [IndexedColumn('work_order_id')])],
    ignoreEmptyUpdates: true,
  ),
  const Table(
    'hold_periods',
    [Column.text('work_order_id'), Column.text('from_date'), Column.text('to_date'), Column.text('reason'), Column.text('review_date'), ..._stamps],
    indexes: [Index('by_order', [IndexedColumn('work_order_id')])],
    ignoreEmptyUpdates: true,
  ),
  const Table(
    'attachments',
    [
      Column.text('work_order_id'),
      Column.text('step_id'),
      Column.text('kind'),
      Column.text('drive_file_id'),
      Column.text('file_name'),
      Column.text('sha256'),
      Column.text('taken_at'),
      ..._stamps,
    ],
    indexes: [Index('by_order', [IndexedColumn('work_order_id')])],
    ignoreEmptyUpdates: true,
  ),
  const Table('followups', [Column.text('contractor_id'), Column.text('followed_at'), Column.text('note'), ..._stamps], ignoreEmptyUpdates: true),
  const Table('saved_views', [Column.text('name'), Column.text('filter'), Column.integer('sort_order'), ..._stamps], ignoreEmptyUpdates: true),
  const Table(
    'settings',
    [Column.text('alert_overrides'), Column.text('prepared_by'), Column.text('language'), Column.integer('show_hijri'), ..._stamps],
    ignoreEmptyUpdates: true,
  ),
  // On this device only: changes the server refused for good, kept until dealt with.
  const Table.localOnly('refused_changes', [
    Column.text('table_name'),
    Column.text('row_id'),
    Column.text('op'),
    Column.text('data'),
    Column.text('code'),
    Column.text('value'),
    Column.text('message'),
    Column.text('at'),
    Column.text('work_order_id'),
  ]),
  // On this device only: photos waiting to go to Google Drive.
  const Table.localOnly('photo_queue', [
    Column.text('attachment_id'),
    Column.text('local_path'),
    Column.text('state'),
    Column.text('error'),
    Column.text('at'),
  ]),
]);
