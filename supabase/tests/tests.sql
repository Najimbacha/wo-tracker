-- Database tests. Each block raises an exception if the protection does not hold.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

create or replace function pg_temp.expect_error(stmt text, label text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    raise notice 'ok   - % (blocked: %)', label, sqlerrm;
    return;
  end;
  raise exception 'FAIL - % : statement was allowed', label;
end $$;

create or replace function pg_temp.ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if not cond then raise exception 'FAIL - %', label; end if;
  raise notice 'ok   - %', label;
end $$;

-- Act as user A.
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \g /dev/null

insert into contractors (id, name) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Al Rashid Contracting');
insert into districts (id, name) values ('aaaaaaaa-0000-0000-0000-000000000002', 'Al Malqa');
insert into work_orders (id, wo_number, category, type_code, received_date, district_id, contractor_id)
values ('aaaaaaaa-0000-0000-0000-000000000010', '441782012', 'extension', '402', date '2026-10-02',
        'aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001');
insert into permits (work_order_id, permit_number, applied_date, start_date, end_date)
values ('aaaaaaaa-0000-0000-0000-000000000010', 'P-88213', date '2026-10-04', date '2026-10-06', date '2026-10-19');
insert into segments (id, work_order_id, base, width_cm, length_m)
values ('aaaaaaaa-0000-0000-0000-000000000020', 'aaaaaaaa-0000-0000-0000-000000000010', 'asphalt', 40, 18);
insert into meters (id, work_order_id, seq) values ('aaaaaaaa-0000-0000-0000-000000000030', 'aaaaaaaa-0000-0000-0000-000000000010', 1);
insert into steps (id, work_order_id, step_key, done_date)
values ('aaaaaaaa-0000-0000-0000-000000000040', 'aaaaaaaa-0000-0000-0000-000000000010', 'kashfeya', date '2026-10-03');
insert into steps (work_order_id, step_key, segment_id, done_date)
values ('aaaaaaaa-0000-0000-0000-000000000010', 'concrete', 'aaaaaaaa-0000-0000-0000-000000000020', date '2026-10-08');
select pg_temp.ok(true, 'user A can create a full work order');

-- Validation rules.
select pg_temp.expect_error($$insert into work_orders (wo_number, category, type_code, received_date) values ('4417820', 'extension', '402', date '2026-10-02')$$,
  'extension number must be 9 digits');
select pg_temp.ok((select count(*) = 0 from work_orders where wo_number = '4417820'), 'short number not saved');
insert into work_orders (wo_number, category, type_code, received_date) values ('T-55', 'emergency', '402', date '2026-10-02');
select pg_temp.ok(true, 'emergency number can be any length');
select pg_temp.expect_error($$insert into work_orders (wo_number, category, type_code, received_date) values ('441782012', 'extension', '802', date '2026-10-02')$$,
  'duplicate work order number');
select pg_temp.expect_error($$insert into work_orders (wo_number, category, type_code, received_date) values ('441782099', 'extension', '999', date '2026-10-02')$$,
  'unknown type');
select pg_temp.expect_error($$insert into work_orders (wo_number, category, type_code, received_date, needs_excavation) values ('441782098', 'extension', '402', date '2026-10-02', true)$$,
  'excavation switch only on 409');
select pg_temp.expect_error($$insert into work_orders (wo_number, category, type_code, received_date, needs_excavation) values ('441782096', 'extension', '401', date '2026-10-02', true)$$,
  '401 never has a trench');
select pg_temp.expect_error($$update work_orders set state = 'cancelled', state_reason = 'x' where wo_number = 'T-55'$$,
  'cancel needs its date');
select pg_temp.expect_error($$update work_orders set state = 'cancelled', state_reason = 'x', state_date = public.riyadh_today() + 2 where wo_number = 'T-55'$$,
  'cancel date in the future');
select pg_temp.expect_error($$update work_orders set state = 'cancelled', state_reason = 'x', state_date = date '2026-10-01' where wo_number = 'T-55'$$,
  'cancel date before the order was received');
update work_orders set state = 'cancelled', state_reason = 'Customer withdrew', state_date = date '2026-10-03' where wo_number = 'T-55';
select pg_temp.ok((select state_date = date '2026-10-03' from work_orders where wo_number = 'T-55'), 'cancel saved with its date');
select pg_temp.expect_error($$update work_orders set state = 'open', state_reason = null where wo_number = 'T-55'$$,
  'reopen must clear the cancel date');
update work_orders set state = 'open', state_reason = null, state_date = null where wo_number = 'T-55';
select pg_temp.ok((select state = 'open' and state_date is null from work_orders where wo_number = 'T-55'), 'reopened');
select pg_temp.expect_error($$insert into work_orders (wo_number, category, type_code, received_date) values ('441782097', 'extension', '402', public.riyadh_today() + 3)$$,
  'received date in the future');
select pg_temp.expect_error($$insert into permits (work_order_id, permit_number, applied_date, start_date, end_date) values ('aaaaaaaa-0000-0000-0000-000000000010', 'P-1', date '2026-10-01', date '2026-10-10', date '2026-10-05')$$,
  'tasreeh end before start');
select pg_temp.expect_error($$insert into permits (work_order_id, permit_number) values ('aaaaaaaa-0000-0000-0000-000000000010', 'P-88213')$$,
  'duplicate tasreeh number');
select pg_temp.expect_error($$insert into segments (work_order_id, base, width_cm, length_m) values ('aaaaaaaa-0000-0000-0000-000000000010', 'asphalt', 60, 5)$$,
  'segment width must be 40 or 80');
select pg_temp.expect_error($$insert into steps (work_order_id, step_key, done_date) values ('aaaaaaaa-0000-0000-0000-000000000010', 'excavation', public.riyadh_today() + 1)$$,
  'step date in the future');
select pg_temp.expect_error($$insert into steps (work_order_id, step_key, not_applicable) values ('aaaaaaaa-0000-0000-0000-000000000010', 'warning_tape', true)$$,
  'not applicable needs a reason');
select pg_temp.expect_error($$insert into steps (work_order_id, step_key, done_date, not_applicable, na_reason) values ('aaaaaaaa-0000-0000-0000-000000000010', 'warning_tape', date '2026-10-07', true, 'x')$$,
  'a step cannot be both done and not applicable');
-- Cable length is optional (often not measured yet), but never 0 or negative.
insert into cable_runs (work_order_id, size_mm2, voltage) values ('aaaaaaaa-0000-0000-0000-000000000010', 185, 'LV');
select pg_temp.expect_error($$insert into cable_runs (work_order_id, size_mm2, voltage, length_m) values ('aaaaaaaa-0000-0000-0000-000000000010', 185, 'LV', 0)$$,
  'a cable length of 0 is refused');
select pg_temp.expect_error($$insert into steps (work_order_id, step_key, done_date) values ('aaaaaaaa-0000-0000-0000-000000000010', 'kashfeya', date '2026-10-04')$$,
  'the same step cannot be recorded twice');
select pg_temp.expect_error($$update steps set done_date = public.riyadh_today() + 2 where id = 'aaaaaaaa-0000-0000-0000-000000000040'$$,
  'cannot change a step date into the future');
update steps set note = 'photo taken' where id = 'aaaaaaaa-0000-0000-0000-000000000040';
select pg_temp.ok(true, 'editing an old step note still works');

-- No permanent delete, ever.
select pg_temp.expect_error($$delete from steps where id = 'aaaaaaaa-0000-0000-0000-000000000040'$$, 'app user cannot delete a step');
select pg_temp.expect_error($$delete from work_orders where id = 'aaaaaaaa-0000-0000-0000-000000000010'$$, 'app user cannot delete a work order');
select pg_temp.expect_error($$truncate work_orders$$, 'app user cannot truncate');
select pg_temp.expect_error($$delete from activity_log$$, 'app user cannot delete history');
select pg_temp.expect_error($$update activity_log set action = 'insert'$$, 'app user cannot edit history');
select pg_temp.expect_error($$insert into activity_log (owner_id, table_name, row_id, action) values ('11111111-1111-1111-1111-111111111111', 'x', gen_random_uuid(), 'insert')$$,
  'app user cannot forge history');

-- Ownership cannot be changed.
update work_orders set owner_id = '22222222-2222-2222-2222-222222222222', notes = 'n' where id = 'aaaaaaaa-0000-0000-0000-000000000010';
select pg_temp.ok((select owner_id = '11111111-1111-1111-1111-111111111111' from work_orders where id = 'aaaaaaaa-0000-0000-0000-000000000010'),
  'owner stays the same even if an update tries to change it');

-- Soft delete and restore are recorded.
update work_orders set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000010';
update work_orders set deleted_at = null where id = 'aaaaaaaa-0000-0000-0000-000000000010';
select pg_temp.ok((select count(*) = 1 from activity_log where row_id = 'aaaaaaaa-0000-0000-0000-000000000010' and action = 'soft_delete'), 'soft delete recorded');
select pg_temp.ok((select count(*) = 1 from activity_log where row_id = 'aaaaaaaa-0000-0000-0000-000000000010' and action = 'restore'), 'restore recorded');

-- History keeps old and new values of exactly the changed fields.
update steps set done_date = date '2026-10-04' where id = 'aaaaaaaa-0000-0000-0000-000000000040';
select pg_temp.ok((
  select old_data = '{"done_date": "2026-10-03"}'::jsonb and new_data = '{"done_date": "2026-10-04"}'::jsonb
  from activity_log where row_id = 'aaaaaaaa-0000-0000-0000-000000000040' and action = 'update' and new_data ? 'done_date'
), 'history records old and new date only');
select pg_temp.ok((select count(*) >= 8 from activity_log), 'inserts are recorded in history');
update steps set done_date = done_date where id = 'aaaaaaaa-0000-0000-0000-000000000040';
select pg_temp.ok((select count(*) = 2 from activity_log where row_id = 'aaaaaaaa-0000-0000-0000-000000000040' and action = 'update'),
  'an update that changes nothing adds no history');

-- The app's cached figures are recomputed, not history.
create temp table history_before as select count(*) as c from activity_log;
update work_orders set status_cache = 'open', stage_cache = 'civil', progress_closed = 3, progress_total = 12, last_change_date = date '2026-10-08'
  where id = 'aaaaaaaa-0000-0000-0000-000000000010';
select pg_temp.ok((select count(*) from activity_log) = (select c from history_before), 'updating only cached figures adds no history');
update work_orders set street = 'King Fahd Rd', progress_closed = 4 where id = 'aaaaaaaa-0000-0000-0000-000000000010';
select pg_temp.ok(exists (select 1 from activity_log where row_id = 'aaaaaaaa-0000-0000-0000-000000000010' and action = 'update'
  and new_data = '{"street": "King Fahd Rd"}'::jsonb), 'history keeps the real change and leaves out cached figures');

-- Act as user B: sees and touches nothing of user A.
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false) \g /dev/null
select pg_temp.ok((select count(*) = 0 from work_orders), 'user B sees none of user A''s orders');
select pg_temp.ok((select count(*) = 0 from activity_log), 'user B sees none of user A''s history');
update work_orders set notes = 'hacked' where id = 'aaaaaaaa-0000-0000-0000-000000000010';
select pg_temp.expect_error($$insert into steps (work_order_id, step_key, done_date) values ('aaaaaaaa-0000-0000-0000-000000000010', 'excavation', date '2026-10-06')$$,
  'user B cannot add a step to user A''s order');
select pg_temp.expect_error($$insert into reminders (work_order_id, due_date, note) values ('aaaaaaaa-0000-0000-0000-000000000010', date '2026-10-20', 'check tasreeh')$$,
  'user B cannot add a reminder to user A''s order');
insert into work_orders (wo_number, category, type_code, received_date) values ('441782012', 'extension', '402', date '2026-10-02');
select pg_temp.ok(true, 'user B can use the same work order number in their own account');

-- Not signed in: nothing at all.
reset role;
set role anon;
select pg_temp.expect_error($$select count(*) from work_orders$$, 'signed-out visitor cannot read orders');
select pg_temp.expect_error($$select count(*) from activity_log$$, 'signed-out visitor cannot read history');

-- Back as user A: B's update did nothing.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \g /dev/null
select pg_temp.ok((select notes = 'n' from work_orders where id = 'aaaaaaaa-0000-0000-0000-000000000010'), 'user B''s update changed nothing');

-- Even the database administrator cannot hard-delete.
reset role;
select pg_temp.expect_error($$delete from work_orders$$, 'administrator cannot delete work orders');
select pg_temp.expect_error($$delete from activity_log$$, 'administrator cannot delete history');
select pg_temp.expect_error($$truncate steps$$, 'administrator cannot truncate steps');
select pg_temp.expect_error($$truncate cable_runs$$, 'administrator cannot truncate a table nothing else points to');
select pg_temp.expect_error($$truncate saved_views$$, 'administrator cannot truncate saved views');
select pg_temp.expect_error($$truncate reminders$$, 'administrator cannot truncate reminders');

-- Two devices mark the same step while offline. With random row ids the second upload is
-- refused by the one-row-per-step rule (that would block the sync queue)...
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \g /dev/null
insert into steps (work_order_id, step_key, done_date) values ('aaaaaaaa-0000-0000-0000-000000000010', 'excavation', date '2026-10-06');
select pg_temp.expect_error($$insert into steps (work_order_id, step_key, done_date) values ('aaaaaaaa-0000-0000-0000-000000000010', 'excavation', date '2026-10-07')$$,
  'a second row for the same step is refused');
update steps set deleted_at = now() where work_order_id = 'aaaaaaaa-0000-0000-0000-000000000010' and step_key = 'excavation';
-- ...so the app gives every step row the same id on every device (tools/rules-check/ids.mjs) and
-- uploads with insert-or-update: the second device's change simply updates the row.
insert into steps (id, work_order_id, step_key, done_date) values ('72c5850c-7439-5030-938c-08b3175fe11e', 'aaaaaaaa-0000-0000-0000-000000000010', 'excavation', date '2026-10-06')
  on conflict (id) do update set done_date = excluded.done_date, deleted_at = null;
insert into steps (id, work_order_id, step_key, done_date) values ('72c5850c-7439-5030-938c-08b3175fe11e', 'aaaaaaaa-0000-0000-0000-000000000010', 'excavation', date '2026-10-07')
  on conflict (id) do update set done_date = excluded.done_date, deleted_at = null;
select pg_temp.ok((select count(*) = 1 and max(done_date) = date '2026-10-07' from steps
  where work_order_id = 'aaaaaaaa-0000-0000-0000-000000000010' and step_key = 'excavation' and deleted_at is null),
  'with the shared step id, two devices end up with one row and the later date');
reset role;

-- PowerSync can only sync tables in its publication; history stays on the server.
select pg_temp.ok((select count(*) = 15 from pg_publication_tables where pubname = 'powersync'), 'PowerSync publication lists the 15 synced tables');
select pg_temp.ok(not exists (select 1 from pg_publication_tables where pubname = 'powersync' and tablename = 'activity_log'), 'history is not published to devices');

-- Data health: database size against the free plan's 500 MB.
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false) \g /dev/null
select pg_temp.ok((select (h->>'db_bytes')::bigint > 0 and (h->>'limit_bytes')::bigint = 524288000 and (h->>'warn_percent')::int = 80
  and (h->>'percent')::numeric between 0 and 100 and (h->>'orders')::int >= 1 and jsonb_typeof(h->'largest_tables') = 'object'
  from (select public.data_health() h) x), 'data health reports size, limit and orders');
reset role;
set role anon;
select pg_temp.expect_error($$select public.data_health()$$, 'signed-out visitors cannot read data health');
reset role;

\o
\echo ALL DATABASE TESTS PASSED
