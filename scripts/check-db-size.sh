#!/usr/bin/env bash
# Fails (so GitHub emails you) when the database passes the warning level of the
# free plan's 500 MB. Usage: scripts/check-db-size.sh "<postgres connection string>" [warn percent, for tests]
set -euo pipefail
# The backup only works if the dump can be opened again. If the passphrase escrow secret
# is missing, a lost BACKUP_PASSPHRASE would leave every backup permanently unreadable and
# nobody would find out until a restore was needed. Check it every night instead.
if [ "${REQUIRE_PASSPHRASE_ESCROW:-}" = "1" ] && [ -z "${BACKUP_PASSPHRASE_ESCROW:-}" ]; then
  echo "::error::BACKUP_PASSPHRASE_ESCROW is not set. Store a copy of BACKUP_PASSPHRASE outside GitHub (password manager) and put it in the secret BACKUP_PASSPHRASE_ESCROW so the backups can still be opened if the original secret is lost."
  exit 1
fi
if [ -n "${BACKUP_PASSPHRASE_ESCROW:-}" ] && [ -n "${BACKUP_PASSPHRASE:-}" ] && [ "$BACKUP_PASSPHRASE_ESCROW" != "$BACKUP_PASSPHRASE" ]; then
  echo "::error::BACKUP_PASSPHRASE_ESCROW does not match BACKUP_PASSPHRASE. The escrowed copy would not open the backups."
  exit 1
fi
health="$(psql "$1" -At -c 'select public.data_health()')"
percent="$(jq -r .percent <<<"$health")"
warn="${2:-$(jq -r .warn_percent <<<"$health")}"
mb="$(jq -r '(.db_bytes / 1048576 | floor)' <<<"$health")"
echo "Database size: ${mb} MB of 500 MB (${percent}%). Orders: $(jq -r .orders <<<"$health"). Largest tables: $(jq -c .largest_tables <<<"$health")"
if awk -v p="$percent" -v w="$warn" 'BEGIN { exit !(p >= w) }'; then
  echo "::error::The database is ${percent}% full (${mb} MB of 500 MB). At 500 MB Supabase makes it read-only, so plan a fix now (nothing is lost yet)."
  exit 1
fi
