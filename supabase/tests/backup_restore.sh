#!/usr/bin/env bash
# Rehearses the nightly backup + weekly restore test on a local Postgres:
# dump -> encrypt -> decrypt -> restore into a fresh database -> compare row counts.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"
work="$(mktemp -d)"; chmod 777 "$work"
as_pg() { if [ "$(id -u)" = "0" ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
as_pg "$bin/initdb -D '$work/data' -U postgres -A trust >/dev/null"
as_pg "$bin/pg_ctl -D '$work/data' -o '-k $work -p 54330 -c listen_addresses=' -l '$work/log' start >/dev/null"
trap 'as_pg "$bin/pg_ctl -D \"$work/data\" stop -m fast >/dev/null" || true; rm -rf "$work"' EXIT
P() { "$bin/psql" -h "$work" -p 54330 -U postgres -v ON_ERROR_STOP=1 -qAt "$@"; }

P -c "create database live" >/dev/null
P -d live -f "$here/supabase_stub.sql" >/dev/null
for m in "$here"/../migrations/*.sql; do P -d live -f "$m" >/dev/null; done

# Sample data written as a signed-in user, including an update and a soft delete.
P -d live >/dev/null <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
insert into contractors (name) values ('Al Rashid Contracting');
insert into work_orders (id, wo_number, category, type_code, received_date) values
  ('aaaaaaaa-0000-0000-0000-000000000010', '441782012', 'extension', '402', date '2026-10-02'),
  ('aaaaaaaa-0000-0000-0000-000000000011', '441782013', 'extension', '802', date '2026-10-03');
insert into steps (work_order_id, step_key, done_date) values
  ('aaaaaaaa-0000-0000-0000-000000000010', 'kashfeya', date '2026-10-03'),
  ('aaaaaaaa-0000-0000-0000-000000000011', 'kashfeya', date '2026-10-04');
update steps set done_date = date '2026-10-05' where step_key = 'kashfeya' and work_order_id = 'aaaaaaaa-0000-0000-0000-000000000011';
update work_orders set deleted_at = now() where wo_number = '441782013';
SQL

counts() { P -d "$1" -c "select (select count(*) from work_orders)||','||(select count(*) from steps)||','||(select count(*) from activity_log)||','||(select count(*) from work_orders where deleted_at is not null)"; }
before="$(counts live)"

"$bin/pg_dump" -h "$work" -p 54330 -U postgres live --schema=public --format=custom --no-owner --no-acl --file "$work/b.dump"
gpg --batch --yes --pinentry-mode loopback --passphrase test-pass --symmetric --cipher-algo AES256 --output "$work/b.dump.gpg" "$work/b.dump"
rm "$work/b.dump"
gpg --batch --yes --pinentry-mode loopback --passphrase test-pass --output "$work/r.dump" --decrypt "$work/b.dump.gpg" 2>/dev/null

P -c "create database restored" >/dev/null
P -d restored -c "drop schema public cascade" >/dev/null
P -d restored -f "$here/supabase_stub.sql" >/dev/null
"$bin/pg_restore" -h "$work" -p 54330 -U postgres -d restored --no-owner --no-acl --exit-on-error "$work/r.dump"
P -d restored -f "$here/supabase_stub.sql" >/dev/null
after="$(counts restored)"

echo "live:     orders,steps,history,deleted = $before"
echo "restored: orders,steps,history,deleted = $after"
[ "$before" = "$after" ] || { echo "FAIL: restored data differs"; exit 1; }

# Protections must survive the restore.
if P -d restored -c "delete from work_orders" 2>/dev/null; then echo "FAIL: delete allowed after restore"; exit 1; fi
P -d restored -c "select count(*) from pg_policies where tablename = 'work_orders'" | grep -q '^[1-9]' || { echo "FAIL: policies missing after restore"; exit 1; }
echo "ok   - protections and security rules survive a restore"
P -d restored -f "$here/../recovery/reapply_grants.sql" >/dev/null
seen=$(P -d restored -c "set role authenticated; select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false); select count(*) from work_orders;" | tail -1)
[ "$seen" = "2" ] || { echo "FAIL: user cannot read own orders after recovery ($seen)"; exit 1; }
if P -d restored -c "set role authenticated; delete from steps" 2>/dev/null; then echo "FAIL: delete allowed after recovery"; exit 1; fi
echo "ok   - after recovery the user reads their own orders and still cannot delete"

# Restoring into a NEW Supabase project: the new account has a new id and sees nothing
# until the rows are moved to it with recovery/reassign_owner.sql.
NEW=33333333-3333-3333-3333-333333333333
as_new() { P -d restored -c "set role authenticated; select set_config('request.jwt.claim.sub','$1',false); $2" | tail -1; }
[ "$(as_new $NEW 'select count(*) from work_orders')" = "0" ] || { echo "FAIL: new account should see nothing before the move"; exit 1; }
history_before=$(P -d restored -c "select count(*) from activity_log")
sed "s/PASTE-NEW-USER-ID-HERE/$NEW/" "$here/../recovery/reassign_owner.sql" | P -d restored >/dev/null
[ "$(as_new $NEW 'select count(*) from work_orders')" = "2" ] || { echo "FAIL: new account cannot see the restored orders"; exit 1; }
[ "$(as_new $NEW 'select count(*) from activity_log')" = "$history_before" ] || { echo "FAIL: history not moved"; exit 1; }
[ "$(as_new 11111111-1111-1111-1111-111111111111 'select count(*) from work_orders')" = "0" ] || { echo "FAIL: old id still owns rows"; exit 1; }
if P -d restored -c "delete from work_orders" 2>/dev/null; then echo "FAIL: delete allowed after the move"; exit 1; fi
as_new $NEW "update steps set done_date = date '2026-10-06' where step_key = 'kashfeya' and work_order_id = 'aaaaaaaa-0000-0000-0000-000000000010'" >/dev/null
[ "$(P -d restored -c "select count(*) from activity_log")" -gt "$history_before" ] || { echo "FAIL: history stopped recording after the move"; exit 1; }
echo "ok   - restore into a new project: rows move to the new account, protections and history work again"

# PowerSync's publication must exist after a restore (the migration is safe to run again).
P -d restored -f "$here/../migrations/20261011000002_powersync_publication.sql" >/dev/null 2>&1
[ "$(P -d restored -c "select count(*) from pg_publication_tables where pubname = 'powersync'")" = "14" ] || { echo "FAIL: powersync publication"; exit 1; }
echo "ok   - PowerSync publication present after restore"
# Data health works after a restore (function grants come back with reapply_grants.sql).
got=$(as_new $NEW "select public.data_health()->>'orders'" 2>&1); live_orders=$(as_new $NEW "select count(*) from work_orders where deleted_at is null"); [ "$got" = "$live_orders" ] || { echo "FAIL: data health after restore ($got)"; exit 1; }
if P -d restored -c "set role anon; select public.data_health()" 2>/dev/null; then echo "FAIL: anon can read data health after restore"; exit 1; fi
echo "ok   - data health works after restore, still hidden from signed-out visitors"
echo "BACKUP AND RESTORE REHEARSAL PASSED"
