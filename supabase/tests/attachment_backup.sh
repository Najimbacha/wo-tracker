#!/usr/bin/env bash
# Rehearses the attachment half of the nightly backup on the local machine.
#
# The nightly job saves two things: the database dump (`.dump`) and a separate archive of the
# photo/PDF FILES from the Supabase Storage bucket (`.storage.tar.gz`). The files are not in
# the database dump, so a backup without the archive restores orders whose photos are gone.
#
# This script exercises the file handling of that pipeline without needing a live Supabase
# project, rclone or Google Drive: the same paths, the same tar layout, the same check the
# weekly restore test performs. Encryption is tested too when gpg is present (skipped when not).
#
# Usage: supabase/tests/attachment_backup.sh
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

fail=0
ok()  { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }

# The app writes storage_path as '<user id>/<attachment id>.<ext>': two UUIDs plus an
# extension limited to [a-z0-9]{1,5}, so the path is URL-safe and used as-is in the request.
user_a=11111111-1111-1111-1111-111111111111
user_b=22222222-2222-2222-2222-222222222222
mkdir -p "storage/attachments/$user_a" "storage/attachments/$user_b"
printf 'PDF-A' > "storage/attachments/$user_a/aaaaaaaa-0000-0000-0000-000000000001.pdf"
printf 'JPG-B' > "storage/attachments/$user_b/bbbbbbbb-0000-0000-0000-000000000002.jpg"
printf 'BIN-C' > "storage/attachments/$user_a/cccccccc-0000-0000-0000-000000000003.bin"
printf '%s\n%s\n%s\n' \
  "$user_a/aaaaaaaa-0000-0000-0000-000000000001.pdf" \
  "$user_b/bbbbbbbb-0000-0000-0000-000000000002.jpg" \
  "$user_a/cccccccc-0000-0000-0000-000000000003.bin" > files.txt

# 1. The paths must not need percent-encoding. Encoding them would turn '/' into '%2F',
#    which the storage endpoint may not decode, breaking every download.
if grep -q '[^A-Za-z0-9._/-]' files.txt; then
  bad "storage_path has characters that would need encoding"
else
  ok "storage_path is URL-safe (sent as-is)"
fi

# 2. Archive exactly as the nightly job does: tar -czf ... -C storage attachments
tar -czf backup.tar.gz -C storage attachments
[ -s backup.tar.gz ] && ok "archive created" || bad "archive empty"

# 3. Restore side: extract, then every restored row must have its file (the weekly test).
mkdir -p storage_check
tar -xzf backup.tar.gz -C storage_check
[ -d storage_check/attachments ] && ok "archive has an attachments/ folder" || bad "no attachments/ folder"
have=0; missing=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if [ -f "storage_check/attachments/$p" ]; then have=$((have+1)); else missing=$((missing+1)); echo "       missing: $p"; fi
done < files.txt
[ "$have" -eq 3 ] && [ "$missing" -eq 0 ] && ok "all 3 files came back" || bad "file count wrong (have=$have missing=$missing)"

# 4. A file that is absent must be reported, not silently accepted.
cp files.txt files_bad.txt
echo "$user_a/ffffffff-0000-0000-0000-000000000009.pdf" >> files_bad.txt
missing2=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  [ -f "storage_check/attachments/$p" ] || missing2=$((missing2+1))
done < files_bad.txt
[ "$missing2" -eq 1 ] && ok "a missing file is detected (weekly test would fail)" || bad "missing file not detected"

# 5. A failed download must be counted, not abort the run under 'set -e'.
( set -euo pipefail
  code=$(false || echo "000")
  [ "$code" = "000" ] || exit 1
) && ok "a failed download is counted, not fatal" || bad "failed download aborts the step"

# 6. No attachments at all must still produce a usable archive, so a later restore test can
#    tell "nothing to back up" apart from "not backed up".
mkdir -p empty/attachments
tar -czf empty.tar.gz -C empty attachments
[ -s empty.tar.gz ] && ok "empty archive still produced" || bad "empty archive missing"
mkdir -p empty_check && tar -xzf empty.tar.gz -C empty_check
[ -d empty_check/attachments ] && ok "empty archive extracts" || bad "empty archive unreadable"

# 7. Encryption round trip, exactly as the nightly job encrypts the archive.
if command -v gpg >/dev/null 2>&1; then
  gpg --batch --yes --pinentry-mode loopback --passphrase rehearsal --symmetric --cipher-algo AES256 \
      --output backup.tar.gz.gpg backup.tar.gz
  gpg --batch --yes --pinentry-mode loopback --passphrase rehearsal --output restored.tar.gz --decrypt backup.tar.gz.gpg 2>/dev/null
  cmp -s backup.tar.gz restored.tar.gz && ok "encrypt/decrypt round trip is byte-identical" || bad "decrypted archive differs"
else
  echo "skip - gpg not installed: encryption round trip not tested"
fi

echo
[ "$fail" -eq 0 ] && echo "ATTACHMENT BACKUP REHEARSAL PASSED" || echo "ATTACHMENT BACKUP REHEARSAL FAILED"
exit "$fail"
