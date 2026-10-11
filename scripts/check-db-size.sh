#!/usr/bin/env bash
# Fails (so GitHub emails you) when the database passes the warning level of the
# free plan's 500 MB. Usage: scripts/check-db-size.sh "<postgres connection string>" [warn percent, for tests]
set -euo pipefail
health="$(psql "$1" -At -c 'select public.data_health()')"
percent="$(jq -r .percent <<<"$health")"
warn="${2:-$(jq -r .warn_percent <<<"$health")}"
mb="$(jq -r '(.db_bytes / 1048576 | floor)' <<<"$health")"
echo "Database size: ${mb} MB of 500 MB (${percent}%). Orders: $(jq -r .orders <<<"$health"). Largest tables: $(jq -c .largest_tables <<<"$health")"
if awk -v p="$percent" -v w="$warn" 'BEGIN { exit !(p >= w) }'; then
  echo "::error::The database is ${percent}% full (${mb} MB of 500 MB). At 500 MB Supabase makes it read-only, so plan a fix now (nothing is lost yet)."
  exit 1
fi
