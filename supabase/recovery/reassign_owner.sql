-- Run ONLY after restoring a backup into a NEW Supabase project.
-- Every row belongs to the account that created it (owner_id). A new project has a new
-- account with a new id, so after a restore the app would show nothing until the rows are
-- moved to the new account.
--
-- 1. Open the app once and sign in, so the new account exists.
-- 2. In Supabase: Authentication > Users, copy your user id.
-- 3. Paste it below in place of PASTE-NEW-USER-ID-HERE and run this whole script.
-- It runs as one transaction: either every row moves, or nothing changes.
do $$
declare
  new_owner uuid := 'PASTE-NEW-USER-ID-HERE';
  t text;
  moved bigint;
begin
  foreach t in array array['contractors', 'districts', 'cable_sizes', 'work_orders', 'permits', 'segments', 'meters',
                           'cable_runs', 'steps', 'hold_periods', 'attachments', 'followups', 'reminders', 'saved_views', 'settings',
                           'activity_log'] loop
    -- The protections (no delete, no owner change, append-only history) are switched off
    -- only for this move and switched back on straight after.
    execute format('alter table public.%I disable trigger user', t);
    execute format('update public.%I set owner_id = %L where owner_id is distinct from %L', t, new_owner, new_owner);
    get diagnostics moved = row_count;
    execute format('alter table public.%I enable trigger user', t);
    raise notice '%: % rows moved', t, moved;
  end loop;
end $$;
