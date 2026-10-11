#!/usr/bin/env bash
# Runs the database tests on a throwaway local Postgres (16+).
# Usage: supabase/tests/run.sh   (needs initdb/pg_ctl on PATH or in /usr/lib/postgresql/*/bin)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"
export PATH="$bin:$PATH"
work="$(mktemp -d)"
chmod 777 "$work"
as_pg() { if [ "$(id -u)" = "0" ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
as_pg "$bin/initdb -D '$work/data' -U postgres -A trust >/dev/null"
as_pg "$bin/pg_ctl -D '$work/data' -o '-k $work -p 54329 -c listen_addresses=' -l '$work/log' start >/dev/null"
trap 'as_pg "$bin/pg_ctl -D \"$work/data\" stop -m fast >/dev/null" || true; rm -rf "$work"' EXIT
psql_() { psql -h "$work" -p 54329 -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql_ -c "create database wo_test" >/dev/null
psql_ -d wo_test -f "$here/supabase_stub.sql" >/dev/null
for m in "$here"/../migrations/*.sql; do psql_ -d wo_test -f "$m" >/dev/null; done
psql_ -d wo_test -f "$here/tests.sql" 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //'
